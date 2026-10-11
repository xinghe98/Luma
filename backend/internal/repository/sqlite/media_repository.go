package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// MediaRepository 使用 SQLite 实现媒体列表、详情和默认缩略图查询。
type MediaRepository struct {
	// db 是媒体查询使用的数据库连接。
	db *sql.DB
}

// NewMediaRepository 创建只读媒体查询 Repository。
func NewMediaRepository(db *sql.DB) (*MediaRepository, error) {
	if db == nil {
		return nil, errors.New("数据库不能为空")
	}
	return &MediaRepository{db: db}, nil
}

const mediaSelect = `SELECT m.id, m.source_id, s.library_kind,
	COALESCE((SELECT l.catalog_item_id FROM catalog_media_links l
		WHERE l.media_id = m.id AND l.match_status = 'matched' AND l.catalog_item_id IS NOT NULL
		LIMIT 1), ''), m.filename,
    COALESCE(NULLIF(u.custom_title, ''), NULLIF(m.detected_title, ''), m.filename),
    m.media_type, COALESCE(m.mime_type, ''), m.file_size, m.duration_ms, m.width, m.height,
    COALESCE(m.video_codec, ''), COALESCE(m.audio_codec, ''), COALESCE(m.container, ''),
    COALESCE(m.bitrate, 0), m.frame_rate_num, m.frame_rate_den, m.audio_track_count,
    m.orientation, m.captured_at_ms, m.status, m.discovered_at_ms, m.file_created_at_ms, m.indexed_at_ms,
    COALESCE(u.favorite, 0), COALESCE(u.progress_ms, 0), COALESCE(u.completed, 0),
    u.last_played_at_ms, COALESCE(u.revision, 0),
    EXISTS (
        SELECT 1 FROM media_assets a
        WHERE a.media_id = m.id AND a.asset_type = 'thumbnail'
          AND a.variant = 'default' AND a.status = 'ready'
    ), EXISTS (
		SELECT 1 FROM media_assets a
		WHERE a.media_id = m.id AND a.asset_type = 'thumbnail'
		  AND a.variant = 'card' AND a.status = 'ready'
	)
    FROM media_items m
    JOIN sources s ON s.id = m.source_id
    LEFT JOIN media_user_data u ON u.media_id = m.id AND u.user_id = ?`

// List 执行白名单排序的稳定 keyset 媒体查询。
func (r *MediaRepository) List(ctx context.Context, query domain.MediaListQuery) ([]domain.Media, error) {
	var statement strings.Builder
	statement.WriteString(mediaSelect)
	statement.WriteString(` WHERE s.enabled = 1 AND s.deleted_at_ms IS NULL AND m.status <> 'missing'`)
	args := []any{query.UserID}
	statement.WriteString(` AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)`)
	args = append(args, query.UserID)
	if query.Search != "" {
		statement.WriteString(` AND instr(lower(m.filename), lower(?)) > 0`)
		args = append(args, query.Search)
	}
	if query.MediaType != "" {
		statement.WriteString(` AND m.media_type = ?`)
		args = append(args, query.MediaType)
	}
	if query.LibraryKind != "" {
		statement.WriteString(` AND s.library_kind = ?`)
		args = append(args, query.LibraryKind)
	}
	if query.Favorite != nil {
		statement.WriteString(` AND COALESCE(u.favorite, 0) = ?`)
		args = append(args, boolInt(*query.Favorite))
	}
	if query.TagID != "" {
		statement.WriteString(` AND EXISTS (
            SELECT 1 FROM media_tags mt
            WHERE mt.user_id = ? AND mt.media_id = m.id AND mt.tag_id = ?
        )`)
		args = append(args, query.UserID, query.TagID)
	}
	switch query.WatchStatus {
	case domain.WatchStatusUnwatched:
		statement.WriteString(` AND COALESCE(u.progress_ms, 0) = 0 AND COALESCE(u.completed, 0) = 0`)
	case domain.WatchStatusWatching:
		statement.WriteString(` AND u.progress_ms > 0 AND u.completed = 0`)
	case domain.WatchStatusCompleted:
		statement.WriteString(` AND u.completed = 1`)
	}
	if query.ContinueWatching {
		statement.WriteString(` AND u.progress_ms > 0 AND u.completed = 0 AND u.last_played_at_ms IS NOT NULL`)
	}
	if clause := mediaStableSortFilter(query.Sort); clause != "" {
		statement.WriteString(" AND ")
		statement.WriteString(clause)
	}
	if query.After != nil {
		clause, values := mediaAfterClause(query.Sort, query.Order, *query.After)
		statement.WriteString(" AND (")
		statement.WriteString(clause)
		statement.WriteByte(')')
		args = append(args, values...)
	}
	statement.WriteString(" ORDER BY ")
	statement.WriteString(mediaOrderBy(query.Sort, query.Order))
	statement.WriteString(" LIMIT ?")
	args = append(args, query.Limit)

	rows, err := r.db.QueryContext(ctx, statement.String(), args...)
	if err != nil {
		return nil, fmt.Errorf("查询媒体列表: %w", err)
	}
	defer rows.Close()
	items := make([]domain.Media, 0, query.Limit)
	for rows.Next() {
		item, err := scanMedia(rows)
		if err != nil {
			return nil, fmt.Errorf("读取媒体列表: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("遍历媒体列表: %w", err)
	}
	return items, nil
}

func (r *MediaRepository) Count(ctx context.Context, query domain.MediaListQuery) (int, error) {
	var statement strings.Builder
	statement.WriteString(`SELECT COUNT(*) FROM media_items m
		JOIN sources s ON s.id = m.source_id
		LEFT JOIN media_user_data u ON u.media_id = m.id AND u.user_id = ?
		WHERE s.enabled = 1 AND s.deleted_at_ms IS NULL AND m.status <> 'missing'`)
	args := []any{query.UserID}
	statement.WriteString(` AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)`)
	args = append(args, query.UserID)
	if query.Search != "" {
		statement.WriteString(` AND instr(lower(m.filename), lower(?)) > 0`)
		args = append(args, query.Search)
	}
	if query.MediaType != "" {
		statement.WriteString(` AND m.media_type = ?`)
		args = append(args, query.MediaType)
	}
	if query.LibraryKind != "" {
		statement.WriteString(` AND s.library_kind = ?`)
		args = append(args, query.LibraryKind)
	}
	if query.Favorite != nil {
		statement.WriteString(` AND COALESCE(u.favorite, 0) = ?`)
		args = append(args, boolInt(*query.Favorite))
	}
	if query.TagID != "" {
		statement.WriteString(` AND EXISTS (
			SELECT 1 FROM media_tags mt
			WHERE mt.user_id = ? AND mt.media_id = m.id AND mt.tag_id = ?
		)`)
		args = append(args, query.UserID, query.TagID)
	}
	switch query.WatchStatus {
	case domain.WatchStatusUnwatched:
		statement.WriteString(` AND COALESCE(u.progress_ms, 0) = 0 AND COALESCE(u.completed, 0) = 0`)
	case domain.WatchStatusWatching:
		statement.WriteString(` AND u.progress_ms > 0 AND u.completed = 0`)
	case domain.WatchStatusCompleted:
		statement.WriteString(` AND u.completed = 1`)
	}
	if query.ContinueWatching {
		statement.WriteString(` AND u.progress_ms > 0 AND u.completed = 0 AND u.last_played_at_ms IS NOT NULL`)
	}
	var total int
	if err := r.db.QueryRowContext(ctx, statement.String(), args...).Scan(&total); err != nil {
		return 0, fmt.Errorf("统计媒体列表: %w", err)
	}
	return total, nil
}

// Get 返回可见媒体详情。
func (r *MediaRepository) Get(ctx context.Context, id, userID string) (domain.Media, error) {
	row := r.db.QueryRowContext(ctx, mediaSelect+` WHERE m.id = ? AND s.enabled = 1
		AND s.deleted_at_ms IS NULL AND m.status <> 'missing'
		AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)`, userID, id, userID)
	item, err := scanMedia(row)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Media{}, domain.ErrMediaNotFound
	}
	if err != nil {
		return domain.Media{}, fmt.Errorf("查询媒体详情: %w", err)
	}
	return item, nil
}

// GetThumbnail 返回可见媒体当前最高生成版本的 ready 默认缩略图。
func (r *MediaRepository) GetThumbnail(ctx context.Context, mediaID, variant, userID string) (domain.ThumbnailAsset, error) {
	var asset domain.ThumbnailAsset
	var updatedMS int64
	err := r.db.QueryRowContext(ctx, `SELECT a.id, a.media_id, a.storage_key, COALESCE(a.mime_type, ''),
        COALESCE(a.content_sha256, ''), a.generator_version, a.updated_at_ms
        FROM media_assets a
        JOIN media_items m ON m.id = a.media_id
        JOIN sources s ON s.id = m.source_id
		WHERE a.media_id = ? AND a.asset_type = 'thumbnail' AND a.variant = ? AND a.status = 'ready'
		  AND m.status <> 'missing' AND s.enabled = 1 AND s.deleted_at_ms IS NULL
		  AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)
		ORDER BY a.generator_version DESC, a.id DESC LIMIT 1`, mediaID, variant, userID).Scan(
		&asset.ID, &asset.MediaID, &asset.StorageKey, &asset.MIMEType,
		&asset.ContentSHA256, &asset.GeneratorVersion, &updatedMS)
	if errors.Is(err, sql.ErrNoRows) {
		var exists int
		if checkErr := r.db.QueryRowContext(ctx, `SELECT EXISTS(
            SELECT 1 FROM media_items m JOIN sources s ON s.id = m.source_id
			WHERE m.id = ? AND m.status <> 'missing' AND s.enabled = 1 AND s.deleted_at_ms IS NULL
			AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)
		)`, mediaID, userID).Scan(&exists); checkErr != nil {
			return domain.ThumbnailAsset{}, fmt.Errorf("检查媒体缩略图: %w", checkErr)
		}
		if exists == 0 {
			return domain.ThumbnailAsset{}, domain.ErrMediaNotFound
		}
		return domain.ThumbnailAsset{}, domain.ErrThumbnailNotFound
	}
	if err != nil {
		return domain.ThumbnailAsset{}, fmt.Errorf("查询缩略图变体: %w", err)
	}
	asset.UpdatedAt = time.UnixMilli(updatedMS).UTC()
	return asset, nil
}

// GetStreamLocation 返回可见原始媒体的服务端内容定位字段。
func (r *MediaRepository) GetStreamLocation(ctx context.Context, mediaID, userID string) (domain.StreamLocation, error) {
	var location domain.StreamLocation
	err := r.db.QueryRowContext(ctx, `SELECT m.id, m.filename, m.media_type, COALESCE(m.mime_type, ''),
        s.source_type, s.root_path, m.relative_path FROM media_items m
        JOIN sources s ON s.id = m.source_id
        WHERE m.id = ? AND m.status <> 'missing' AND s.enabled = 1
		AND s.deleted_at_ms IS NULL AND s.source_type = 'local'
		AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)`, mediaID, userID).Scan(
		&location.ID, &location.Filename, &location.MediaType, &location.MIMEType,
		&location.SourceType, &location.RootPath, &location.RelativePath)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.StreamLocation{}, domain.ErrMediaNotFound
	}
	if err != nil {
		return domain.StreamLocation{}, fmt.Errorf("查询原始媒体定位信息: %w", err)
	}
	return location, nil
}

// GetImageDeleteTarget 返回当前用户可见的图片删除定位。
// 可见性判定与详情一致：未授权、软删除来源、missing 媒体一律视为不存在；
// 非图片媒体返回参数级错误；来源禁用或状态非在线时返回 ErrSourceOffline（503），
// 保证磁盘上仍存在的离线媒体源不会被静默删除。
func (r *MediaRepository) GetImageDeleteTarget(ctx context.Context, mediaID, userID string) (domain.DeleteImageTarget, error) {
	var target domain.DeleteImageTarget
	var mediaType, sourceStatus string
	var sourceEnabled int
	err := r.db.QueryRowContext(ctx, `SELECT m.id, m.source_id, s.root_path, m.relative_path, m.media_type,
        s.enabled, s.status
        FROM media_items m
        JOIN sources s ON s.id = m.source_id
        WHERE m.id = ? AND m.status <> 'missing'
		AND s.deleted_at_ms IS NULL AND s.source_type = 'local'
		AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)`,
		mediaID, userID).Scan(&target.MediaID, &target.SourceID, &target.RootPath, &target.RelativePath,
		&mediaType, &sourceEnabled, &sourceStatus)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.DeleteImageTarget{}, domain.ErrMediaNotFound
	}
	if err != nil {
		return domain.DeleteImageTarget{}, fmt.Errorf("查询图片删除定位: %w", err)
	}
	if mediaType != domain.MediaTypeImage {
		return domain.DeleteImageTarget{}, fmt.Errorf("%w: 仅支持删除图片媒体", domain.ErrInvalidRequest)
	}
	// 与上传同一状态规则：禁用或任何非在线状态都拒绝写入操作。
	if sourceEnabled != 1 || (sourceStatus != domain.SourceStatusOnline && sourceStatus != "") {
		return domain.DeleteImageTarget{}, fmt.Errorf("%w: 媒体源当前不可写", domain.ErrSourceOffline)
	}
	return target, nil
}

// DeleteImageRecord 在文件删除后硬删除媒体行、清除其全部处理任务，
// 并在同一事务内写入 (source_id, relative_path) 删除墓碑。
// 墓碑以删除时刻为水位：删除发生前已启动的扫描若仍持有旧文件快照，
// 其对同路径的 reconcile 被判定过期而拒绝复活；删除后启动的新扫描
// 正常入库并顺带清掉墓碑（判定与清理在 reconcileFileTx 内完成）。
// 行消失后同一媒体 ID 不可能被复用；media_assets、media_user_data、
// media_tags、catalog_media_links 均 ON DELETE CASCADE 随主行清除。
// 运行中的 probe/thumbnail 任务因 GetMedia/status<>'missing' 版本复核得到
// ErrMediaNotFound，其完成/失败路径又因 jobs 行被删而返回 ErrNoPendingJob，
// 两条路径都按既有 isBenignJobError 视为正常结束。
// 媒体行按已授权定位的 ID 无条件删除，不附加 status 过滤——
// 并发的 CompleteJob 可能先把它标成 missing，文件既已删除，索引也必须清除。
func (r *MediaRepository) DeleteImageRecord(ctx context.Context, target domain.DeleteImageTarget, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	// 先写墓碑再删行：任何在墓碑之后提交的同路径过期 reconcile 必然看到它；
	// 已先完成的 reconcile 让旧行保留——该文件已不存在，由扫描水位正常收敛。
	if _, err := tx.ExecContext(ctx, `INSERT INTO media_delete_tombstones(
        source_id, relative_path, media_id, deleted_at_ms
    ) VALUES (?, ?, ?, ?)
    ON CONFLICT(source_id, relative_path) DO UPDATE SET
        media_id = excluded.media_id,
        deleted_at_ms = excluded.deleted_at_ms`,
		target.SourceID, target.RelativePath, target.MediaID, now.UnixMilli()); err != nil {
		return fmt.Errorf("写入删除墓碑: %w", err)
	}
	// 清除媒体处理任务（jobs.entity_id 无外键，必须手工删除）；
	// pending/running 一并删掉而不是 cancel，让活跃唯一索引即刻释放。
	if _, err := tx.ExecContext(ctx, `DELETE FROM jobs
        WHERE entity_id = ? AND job_type IN ('probe_media', 'generate_thumbnail', 'generate_card_thumbnail')`,
		target.MediaID); err != nil {
		return fmt.Errorf("删除媒体处理任务: %w", err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM media_items WHERE id = ?`, target.MediaID)
	if err != nil {
		return fmt.Errorf("删除媒体索引: %w", err)
	}
	if err := requireAffected(result, domain.ErrMediaNotFound); err != nil {
		return err
	}
	return tx.Commit()
}

// mediaStableSortFilter 对可变排序键收紧可见集合，降低处理中翻页漏项。
func mediaStableSortFilter(sort string) string {
	switch sort {
	case domain.MediaSortDuration:
		return `(m.duration_ms IS NOT NULL OR m.status IN ('ready', 'failed'))`
	case domain.MediaSortFileSize:
		return `m.status IN ('ready', 'failed')`
	default:
		return ""
	}
}

func mediaOrderBy(sort, order string) string {
	direction := "DESC"
	if order == domain.SortAscending {
		direction = "ASC"
	}
	switch sort {
	case domain.MediaSortFilename:
		return "m.filename COLLATE NOCASE " + direction + ", m.id " + direction
	case domain.MediaSortDuration:
		return "(m.duration_ms IS NULL) ASC, m.duration_ms " + direction + ", m.id " + direction
	case domain.MediaSortFileSize:
		return "m.file_size " + direction + ", m.id " + direction
	case domain.MediaSortLastPlayedAt:
		return "u.last_played_at_ms " + direction + ", m.id " + direction
	default:
		return mediaAddedAtExpr + " " + direction + ", m.id " + direction
	}
}

const mediaAddedAtExpr = "COALESCE(m.file_created_at_ms, m.discovered_at_ms)"

func mediaAfterClause(sort, order string, key domain.MediaPageKey) (string, []any) {
	op := "<"
	if order == domain.SortAscending {
		op = ">"
	}
	switch sort {
	case domain.MediaSortFilename:
		return fmt.Sprintf(`m.filename COLLATE NOCASE %s ? OR
            (m.filename COLLATE NOCASE = ? COLLATE NOCASE AND m.id %s ?)`, op, op),
			[]any{key.StringValue, key.StringValue, key.ID}
	case domain.MediaSortDuration:
		if key.Null {
			return fmt.Sprintf(`m.duration_ms IS NULL AND m.id %s ?`, op), []any{key.ID}
		}
		return fmt.Sprintf(`(m.duration_ms IS NOT NULL AND (m.duration_ms %s ? OR
            (m.duration_ms = ? AND m.id %s ?))) OR m.duration_ms IS NULL`, op, op),
			[]any{key.IntValue, key.IntValue, key.ID}
	case domain.MediaSortFileSize:
		return fmt.Sprintf(`m.file_size %s ? OR (m.file_size = ? AND m.id %s ?)`, op, op),
			[]any{key.IntValue, key.IntValue, key.ID}
	case domain.MediaSortLastPlayedAt:
		return fmt.Sprintf(`u.last_played_at_ms %s ? OR (u.last_played_at_ms = ? AND m.id %s ?)`, op, op),
			[]any{key.IntValue, key.IntValue, key.ID}
	default:
		return fmt.Sprintf(`%s %s ? OR (%s = ? AND m.id %s ?)`, mediaAddedAtExpr, op, mediaAddedAtExpr, op),
			[]any{key.IntValue, key.IntValue, key.ID}
	}
}

func scanMedia(row rowScanner) (domain.Media, error) {
	var item domain.Media
	var duration, width, height, frameNum, frameDen, tracks, orientation sql.NullInt64
	var captured, fileCreated, indexed, lastPlayed sql.NullInt64
	var discoveredMS int64
	var favorite, completed, hasThumbnail, hasCardThumbnail int
	err := row.Scan(&item.ID, &item.SourceID, &item.LibraryKind, &item.CatalogItemID, &item.Filename, &item.Title, &item.MediaType,
		&item.MIMEType, &item.FileSize, &duration, &width, &height, &item.VideoCodec,
		&item.AudioCodec, &item.Container, &item.Bitrate, &frameNum, &frameDen, &tracks,
		&orientation, &captured, &item.Status, &discoveredMS, &fileCreated, &indexed, &favorite, &item.ProgressMS,
		&completed, &lastPlayed, &item.UserDataRevision,
		&hasThumbnail, &hasCardThumbnail)
	if err != nil {
		return domain.Media{}, err
	}
	item.DurationMS = nullInt64(duration)
	item.Width = nullInt(width)
	item.Height = nullInt(height)
	item.FrameRateNum = nullInt(frameNum)
	item.FrameRateDen = nullInt(frameDen)
	item.AudioTrackCount = nullInt(tracks)
	item.Orientation = nullInt(orientation)
	item.CapturedAt = nullTime(captured)
	item.FileCreatedAt = nullTime(fileCreated)
	item.IndexedAt = nullTime(indexed)
	item.DiscoveredAt = time.UnixMilli(discoveredMS).UTC()
	item.Favorite = favorite == 1
	item.Completed = completed == 1
	item.LastPlayedAt = nullTime(lastPlayed)
	item.HasThumbnail = hasThumbnail == 1
	item.HasCardThumbnail = hasCardThumbnail == 1
	return item, nil
}

func nullInt64(value sql.NullInt64) *int64 {
	if !value.Valid {
		return nil
	}
	result := value.Int64
	return &result
}

func nullInt(value sql.NullInt64) *int {
	if !value.Valid {
		return nil
	}
	result := int(value.Int64)
	return &result
}

func nullTime(value sql.NullInt64) *time.Time {
	if !value.Valid {
		return nil
	}
	result := time.UnixMilli(value.Int64).UTC()
	return &result
}
