// NFO sidecar persistence is separate from playable media indexing and processing.
package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ReconcileSidecar indexes one NFO and marks source works pending when it changes.
func (r *ScanRepository) ReconcileSidecar(ctx context.Context, scanID, sourceID string,
	file domain.DiscoveredFile, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var oldSize, oldModified int64
	err = tx.QueryRowContext(ctx, `SELECT file_size,file_modified_at_ms FROM catalog_sidecars
		WHERE source_id=? AND relative_path=?`, sourceID, file.RelativePath).Scan(&oldSize, &oldModified)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("读取 NFO 侧车索引: %w", err)
	}
	changed := errors.Is(err, sql.ErrNoRows) || oldSize != file.Size || oldModified != file.ModifiedAt.UnixMilli()
	_, err = tx.ExecContext(ctx, `INSERT INTO catalog_sidecars(
		source_id,relative_path,filename,file_size,file_modified_at_ms,last_seen_scan_id,status,created_at_ms,updated_at_ms
	) VALUES(?,?,?,?,?,?,'ready',?,?)
	ON CONFLICT(source_id,relative_path) DO UPDATE SET filename=excluded.filename,file_size=excluded.file_size,
	file_modified_at_ms=excluded.file_modified_at_ms,last_seen_scan_id=excluded.last_seen_scan_id,status='ready',
	updated_at_ms=excluded.updated_at_ms`,
		sourceID, file.RelativePath, file.Filename, file.Size, file.ModifiedAt.UnixMilli(),
		scanID, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return fmt.Errorf("保存 NFO 侧车索引: %w", err)
	}
	if changed {
		_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET metadata_status='pending',updated_at_ms=?
			WHERE source_id=?`, now.UnixMilli(), sourceID)
		if err != nil {
			return err
		}
	}
	return tx.Commit()
}
