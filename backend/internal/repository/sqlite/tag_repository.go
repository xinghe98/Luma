package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// TagRepository 使用 SQLite 保存用户私有标签。
type TagRepository struct {
	db *sql.DB
}

// NewTagRepository 创建标签 Repository。
func NewTagRepository(db *sql.DB) (*TagRepository, error) {
	if db == nil {
		return nil, errors.New("数据库不能为空")
	}
	return &TagRepository{db: db}, nil
}

// List 返回当前用户的全部标签和使用次数。
func (r *TagRepository) List(ctx context.Context, userID string) ([]domain.Tag, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT t.id, t.user_id, t.name, t.normalized_name,
        COUNT(mt.media_id), t.revision, t.created_at_ms, t.updated_at_ms
        FROM tags t LEFT JOIN media_tags mt ON mt.tag_id = t.id AND mt.user_id = t.user_id
        WHERE t.user_id = ? GROUP BY t.id ORDER BY t.normalized_name, t.id`, userID)
	if err != nil {
		return nil, fmt.Errorf("查询标签: %w", err)
	}
	defer rows.Close()
	tags := make([]domain.Tag, 0)
	for rows.Next() {
		tag, err := scanTag(rows)
		if err != nil {
			return nil, fmt.Errorf("读取标签: %w", err)
		}
		tags = append(tags, tag)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("遍历标签: %w", err)
	}
	return tags, nil
}

// Create 插入经过规范化的标签。
func (r *TagRepository) Create(ctx context.Context, tag domain.Tag) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO tags(
        id, user_id, name, normalized_name, revision, created_at_ms, updated_at_ms
    ) VALUES (?, ?, ?, ?, 1, ?, ?)`, tag.ID, tag.UserID, tag.Name, tag.NormalizedName,
		tag.CreatedAt.UnixMilli(), tag.UpdatedAt.UnixMilli())
	if err != nil {
		if isUniqueConstraint(err) {
			var exists int
			if checkErr := r.db.QueryRowContext(ctx, `SELECT EXISTS(
                    SELECT 1 FROM tags WHERE user_id = ? AND normalized_name = ?
                )`, tag.UserID, tag.NormalizedName).Scan(&exists); checkErr != nil {
				return fmt.Errorf("检查标签名称冲突: %w", checkErr)
			}
			if exists == 1 {
				return domain.ErrTagConflict
			}
		}
		return fmt.Errorf("创建标签: %w", err)
	}
	return nil
}

// Update 使用 revision 乐观锁重命名标签。
func (r *TagRepository) Update(ctx context.Context, tag domain.Tag, baseRevision int64) (domain.Tag, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Tag{}, fmt.Errorf("开始标签更新事务: %w", err)
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(ctx, `UPDATE tags SET name = ?, normalized_name = ?,
        revision = revision + 1, updated_at_ms = ? WHERE id = ? AND user_id = ? AND revision = ?`,
		tag.Name, tag.NormalizedName, tag.UpdatedAt.UnixMilli(), tag.ID, tag.UserID, baseRevision)
	if err != nil {
		if isUniqueConstraint(err) {
			return domain.Tag{}, domain.ErrTagConflict
		}
		return domain.Tag{}, fmt.Errorf("更新标签: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return domain.Tag{}, err
	}
	if count == 0 {
		var exists int
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM tags WHERE id = ? AND user_id = ?)`, tag.ID, tag.UserID).Scan(&exists); err != nil {
			return domain.Tag{}, fmt.Errorf("检查标签: %w", err)
		}
		if exists == 0 {
			return domain.Tag{}, domain.ErrTagNotFound
		}
		return domain.Tag{}, domain.ErrRevisionConflict
	}
	updated, err := readTag(ctx, tx, tag.UserID, tag.ID)
	if err != nil {
		return domain.Tag{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.Tag{}, fmt.Errorf("提交标签更新事务: %w", err)
	}
	return updated, nil
}

// Delete 删除标签，并由外键级联删除媒体标签关系。
func (r *TagRepository) Delete(ctx context.Context, userID, id string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("开始标签删除事务: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `UPDATE media_user_data SET revision = revision + 1, updated_at_ms = ?
        WHERE user_id = ? AND media_id IN (
            SELECT media_id FROM media_tags WHERE user_id = ? AND tag_id = ?
        )`, now.UTC().UnixMilli(), userID, userID, id); err != nil {
		return fmt.Errorf("更新标签关联媒体版本: %w", err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM tags WHERE id = ? AND user_id = ?`, id, userID)
	if err != nil {
		return fmt.Errorf("删除标签: %w", err)
	}
	if err := requireAffected(result, domain.ErrTagNotFound); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("提交标签删除事务: %w", err)
	}
	return nil
}

type tagQuerier interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func readTag(ctx context.Context, query tagQuerier, userID, id string) (domain.Tag, error) {
	row := query.QueryRowContext(ctx, `SELECT t.id, t.user_id, t.name, t.normalized_name,
        COUNT(mt.media_id), t.revision, t.created_at_ms, t.updated_at_ms
        FROM tags t LEFT JOIN media_tags mt ON mt.tag_id = t.id AND mt.user_id = t.user_id
        WHERE t.user_id = ? AND t.id = ? GROUP BY t.id`, userID, id)
	tag, err := scanTag(row)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Tag{}, domain.ErrTagNotFound
	}
	if err != nil {
		return domain.Tag{}, fmt.Errorf("查询标签: %w", err)
	}
	return tag, nil
}

func scanTag(row rowScanner) (domain.Tag, error) {
	var tag domain.Tag
	var createdMS, updatedMS int64
	if err := row.Scan(&tag.ID, &tag.UserID, &tag.Name, &tag.NormalizedName, &tag.UsageCount,
		&tag.Revision, &createdMS, &updatedMS); err != nil {
		return domain.Tag{}, err
	}
	tag.CreatedAt = time.UnixMilli(createdMS).UTC()
	tag.UpdatedAt = time.UnixMilli(updatedMS).UTC()
	return tag, nil
}
