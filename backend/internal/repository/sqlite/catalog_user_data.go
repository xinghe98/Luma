// 作品用户数据持久化作品级收藏，避免清晰度版本切换影响用户偏好。
package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// UpdateFavorite 使用乐观并发更新作品收藏，并确认调用者仍有对应来源权限。
func (r *CatalogRepository) UpdateFavorite(ctx context.Context, itemID, userID string, favorite bool, revision int64, now time.Time) (domain.CatalogUserData, error) {
	result := domain.CatalogUserData{CatalogItemID: itemID, Favorite: favorite}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return result, err
	}
	defer tx.Rollback()
	var exists int
	err = tx.QueryRowContext(ctx, `SELECT 1 FROM catalog_items c JOIN source_grants g ON g.source_id=c.source_id
		WHERE c.id=? AND g.user_id=?`, itemID, userID).Scan(&exists)
	if errors.Is(err, sql.ErrNoRows) {
		return result, domain.ErrCatalogNotFound
	}
	if err != nil {
		return result, err
	}
	var currentRevision int64
	var currentFavorite int
	err = tx.QueryRowContext(ctx, `SELECT favorite,revision FROM catalog_user_data
		WHERE user_id=? AND catalog_item_id=?`, userID, itemID).Scan(&currentFavorite, &currentRevision)
	if errors.Is(err, sql.ErrNoRows) {
		if revision != 0 {
			return result, domain.ErrRevisionConflict
		}
		result.Revision = 1
		_, err = tx.ExecContext(ctx, `INSERT INTO catalog_user_data(
			user_id,catalog_item_id,favorite,revision,created_at_ms,updated_at_ms
		) VALUES(?,?,?,?,?,?)`, userID, itemID, boolInt(favorite), result.Revision, now.UnixMilli(), now.UnixMilli())
	} else if err == nil {
		if currentRevision != revision {
			return result, domain.ErrRevisionConflict
		}
		result.Revision = currentRevision + 1
		_, err = tx.ExecContext(ctx, `UPDATE catalog_user_data SET favorite=?,revision=?,updated_at_ms=?
			WHERE user_id=? AND catalog_item_id=? AND revision=?`, boolInt(favorite), result.Revision,
			now.UnixMilli(), userID, itemID, revision)
	} else {
		return result, err
	}
	if err != nil {
		return result, err
	}
	result.UpdatedAt = now.UTC()
	if err := tx.Commit(); err != nil {
		return result, err
	}
	return result, nil
}
