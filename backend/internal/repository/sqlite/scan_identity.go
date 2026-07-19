package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// displacedPathPrefix 是身份冲突时临时让出相对路径所用的保留前缀，
// 写入 media_items.relative_path，形如 .luma-displaced/{media_id}。
const displacedPathPrefix = ".luma-displaced/"

// indexedMedia 是 media_items 身份匹配所需列的只读投影（非完整媒体领域模型）。
type indexedMedia struct {
	// ID 对应 media_items.id。
	ID string
	// RelativePath 对应 media_items.relative_path。
	RelativePath string
	// MediaType 对应 media_items.media_type。
	MediaType string
	// Size 对应 media_items.file_size。
	Size int64
	// ModifiedAtMS 对应 media_items.file_modified_at_ms。
	ModifiedAtMS int64
	// FileID 对应 media_items.file_id（空串表示库中为 NULL）。
	FileID string
	// QuickHash 对应 media_items.quick_hash（空串表示库中为 NULL）。
	QuickHash string
	// Status 对应 media_items.status。
	Status string
}

// findExistingMedia 按路径、文件 ID、快速指纹顺序查找唯一媒体候选。
// 路径命中但强身份冲突时，会让出路径并继续按 FileID/指纹匹配，避免收藏挂错文件。
func findExistingMedia(ctx context.Context, q queryRower, sourceID string, file domain.DiscoveredFile, now time.Time) (indexedMedia, bool, bool, error) {
	item, err := queryOneMedia(ctx, q, `WHERE source_id = ? AND relative_path = ?`, sourceID, file.RelativePath)
	if err == nil {
		if !identityConflict(item, file) {
			return item, true, false, nil
		}
		if err := displaceMediaPath(ctx, q, item, now); err != nil {
			return indexedMedia{}, false, false, err
		}
	} else if !errors.Is(err, sql.ErrNoRows) {
		return indexedMedia{}, false, false, err
	}
	if file.FileID != "" {
		items, err := queryMediaCandidates(ctx, q, `WHERE source_id = ? AND file_id = ? LIMIT 2`, sourceID, file.FileID)
		if err != nil {
			return indexedMedia{}, false, false, err
		}
		if len(items) == 1 {
			return items[0], true, false, nil
		}
		if len(items) > 1 {
			return indexedMedia{}, false, true, nil
		}
	}
	if file.QuickHash != "" {
		items, err := queryMediaCandidates(ctx, q, `WHERE source_id = ? AND file_size = ? AND quick_hash = ? LIMIT 2`,
			sourceID, file.Size, file.QuickHash)
		if err != nil {
			return indexedMedia{}, false, false, err
		}
		if len(items) == 1 {
			return items[0], true, false, nil
		}
		if len(items) > 1 {
			return indexedMedia{}, false, true, nil
		}
	}
	return indexedMedia{}, false, false, nil
}

// identityConflict 判断路径占用者与当前发现文件是否具有互斥的强身份。
func identityConflict(existing indexedMedia, file domain.DiscoveredFile) bool {
	if file.FileID != "" && existing.FileID != "" && file.FileID != existing.FileID {
		return true
	}
	if file.QuickHash != "" && existing.QuickHash != "" &&
		(file.QuickHash != existing.QuickHash || existing.Size != file.Size) {
		return true
	}
	return false
}

// ensurePathAvailable 保证目标相对路径不被其他媒体行占用。
func ensurePathAvailable(ctx context.Context, q queryRower, sourceID, relativePath, keepID string, now time.Time) error {
	item, err := queryOneMedia(ctx, q, `WHERE source_id = ? AND relative_path = ?`, sourceID, relativePath)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if keepID != "" && item.ID == keepID {
		return nil
	}
	return displaceMediaPath(ctx, q, item, now)
}

// displaceMediaPath 将媒体行临时挪到保留前缀路径，释放真实相对路径。
func displaceMediaPath(ctx context.Context, q queryRower, item indexedMedia, now time.Time) error {
	displaced := displacedPathPrefix + item.ID
	_, err := q.ExecContext(ctx, `UPDATE media_items SET relative_path = ?, updated_at_ms = ? WHERE id = ?`,
		displaced, now.UnixMilli(), item.ID)
	if err != nil {
		return fmt.Errorf("释放冲突相对路径: %w", err)
	}
	return nil
}

// queryRower 抽象事务与数据库连接的查询执行能力。
type queryRower interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

// queryOneMedia 查询单个媒体身份候选。
func queryOneMedia(ctx context.Context, q queryRower, where string, args ...any) (indexedMedia, error) {
	var item indexedMedia
	err := q.QueryRowContext(ctx, mediaIdentitySelect+" "+where, args...).Scan(
		&item.ID, &item.RelativePath, &item.MediaType, &item.Size, &item.ModifiedAtMS,
		&item.FileID, &item.QuickHash, &item.Status,
	)
	return item, err
}

// queryMediaCandidates 查询最多两个媒体身份候选以检测歧义。
func queryMediaCandidates(ctx context.Context, q queryRower, where string, args ...any) ([]indexedMedia, error) {
	rows, err := q.QueryContext(ctx, mediaIdentitySelect+" "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []indexedMedia
	for rows.Next() {
		var item indexedMedia
		if err := rows.Scan(&item.ID, &item.RelativePath, &item.MediaType, &item.Size,
			&item.ModifiedAtMS, &item.FileID, &item.QuickHash, &item.Status); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

// mediaIdentitySelect 是媒体身份协调使用的统一查询字段。
const mediaIdentitySelect = `SELECT id, relative_path, media_type, file_size, file_modified_at_ms,
    COALESCE(file_id, ''), COALESCE(quick_hash, ''), status FROM media_items`
