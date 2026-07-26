// Catalog metadata persistence owns scrape queues, candidates, provider results, and artwork references.
package sqlite

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/catalog"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

// EnqueuePendingMetadata creates jobs for pending, failed, or stale works.
// Identity locks protect provider selection but intentionally do not suppress
// periodic metadata refreshes for that selected provider record.
func (r *CatalogRepository) EnqueuePendingMetadata(ctx context.Context, now, staleBefore time.Time) (int, error) {
	result, err := r.db.ExecContext(ctx, `INSERT INTO catalog_scrape_jobs(
		catalog_item_id, status, attempt_count, available_at_ms, created_at_ms, updated_at_ms
	)
	SELECT id, 'pending', 0, ?, ?, ? FROM catalog_items c
	WHERE (
		c.metadata_status = 'pending' OR
		(c.metadata_status = 'ready' AND COALESCE(c.metadata_updated_at_ms, 0) < ?)
	)
	AND NOT EXISTS (
		SELECT 1 FROM catalog_scrape_jobs active
		WHERE active.catalog_item_id = c.id AND active.status IN ('pending','running')
	)
	ON CONFLICT(catalog_item_id) DO UPDATE SET
		status = CASE WHEN catalog_scrape_jobs.status = 'running' THEN 'running' ELSE 'pending' END,
		attempt_count = CASE WHEN catalog_scrape_jobs.status = 'running' THEN catalog_scrape_jobs.attempt_count ELSE 0 END,
		available_at_ms = CASE WHEN catalog_scrape_jobs.status = 'running' THEN catalog_scrape_jobs.available_at_ms ELSE excluded.available_at_ms END,
		error_code = CASE WHEN catalog_scrape_jobs.status = 'running' THEN catalog_scrape_jobs.error_code ELSE NULL END,
		error_message = CASE WHEN catalog_scrape_jobs.status = 'running' THEN catalog_scrape_jobs.error_message ELSE NULL END,
		updated_at_ms = excluded.updated_at_ms`,
		now.UnixMilli(), now.UnixMilli(), now.UnixMilli(), staleBefore.UnixMilli())
	if err != nil {
		return 0, fmt.Errorf("enqueue catalog metadata: %w", err)
	}
	count, _ := result.RowsAffected()
	return int(count), nil
}

// ClaimMetadata atomically claims one due job and marks the work refreshing.
func (r *CatalogRepository) ClaimMetadata(ctx context.Context, workerID string, now time.Time) (domain.CatalogScrapeInput, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	defer tx.Rollback()
	var itemID string
	err = tx.QueryRowContext(ctx, `SELECT catalog_item_id FROM catalog_scrape_jobs
		WHERE status = 'pending' AND available_at_ms <= ?
		ORDER BY available_at_ms, created_at_ms, catalog_item_id LIMIT 1`, now.UnixMilli()).Scan(&itemID)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.CatalogScrapeInput{}, domain.ErrNoPendingJob
	}
	if err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	result, err := tx.ExecContext(ctx, `UPDATE catalog_scrape_jobs SET status='running',
		attempt_count=attempt_count+1, locked_at_ms=?, locked_by=?, updated_at_ms=?
		WHERE catalog_item_id=? AND status='pending'`,
		now.UnixMilli(), workerID, now.UnixMilli(), itemID)
	if err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	if err := requireAffected(result, domain.ErrNoPendingJob); err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET metadata_status='refreshing',
		metadata_error_code=NULL, metadata_error_message=NULL, updated_at_ms=? WHERE id=?`,
		now.UnixMilli(), itemID)
	if err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	var input domain.CatalogScrapeInput
	var year, duration sql.NullInt64
	var provider, providerItem sql.NullString
	var locked int
	err = tx.QueryRowContext(ctx, `SELECT c.id,c.source_id,c.kind,c.title,c.year,
		(SELECT m.duration_ms FROM catalog_media_links l JOIN media_items m ON m.id=l.media_id
		 WHERE l.catalog_item_id=c.id AND l.match_status='matched' AND m.duration_ms IS NOT NULL
		 ORDER BY m.duration_ms DESC LIMIT 1),
		c.provider,c.provider_item_id,c.identity_locked,c.metadata_revision
		FROM catalog_items c WHERE c.id=?`, itemID).
		Scan(&input.ItemID, &input.SourceID, &input.Kind, &input.Title, &year, &duration,
			&provider, &providerItem, &locked, &input.MetadataRevision)
	if err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	input.Year = nullInt(year)
	input.DurationMS = nullInt64(duration)
	input.Provider, input.ProviderItemID = provider.String, providerItem.String
	input.IdentityLocked = locked == 1
	paths, err := matchedCatalogPaths(ctx, tx, itemID)
	if err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	evidence := catalog.CollectScrapeEvidence(input.Title, paths)
	if input.Year == nil {
		input.Year = evidence.Year
	}
	input.AlternativeTitles = evidence.AlternativeTitles
	if err := tx.Commit(); err != nil {
		return domain.CatalogScrapeInput{}, err
	}
	return input, nil
}

// matchedCatalogPaths 返回仍参与作品的媒体相对路径，仅用于汇总刮削线索。
func matchedCatalogPaths(ctx context.Context, tx *sql.Tx, itemID string) ([]string, error) {
	rows, err := tx.QueryContext(ctx, `SELECT m.relative_path FROM catalog_media_links l
		JOIN media_items m ON m.id=l.media_id
		WHERE l.catalog_item_id=? AND l.match_status='matched' AND m.status <> 'missing'
		ORDER BY m.relative_path`, itemID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	paths := []string{}
	for rows.Next() {
		var path string
		if err := rows.Scan(&path); err != nil {
			return nil, err
		}
		paths = append(paths, path)
	}
	return paths, rows.Err()
}

// SaveMetadataCandidates persists manual choices and completes the active job.
func (r *CatalogRepository) SaveMetadataCandidates(ctx context.Context, itemID string, candidates []domain.CatalogMetadataCandidate, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM catalog_match_candidates WHERE catalog_item_id=?`, itemID); err != nil {
		return err
	}
	for _, candidate := range candidates {
		reasons, _ := json.Marshal(candidate.Reasons)
		_, err := tx.ExecContext(ctx, `INSERT INTO catalog_match_candidates(
			id,catalog_item_id,provider,provider_item_id,title,original_title,year,overview,score,reasons_json,poster_ref,created_at_ms
		) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`,
			candidate.ID, itemID, candidate.Provider, candidate.ProviderItemID, candidate.Title,
			candidate.OriginalTitle, nullableInt(candidate.Year), candidate.Overview, candidate.Score,
			string(reasons), nullableText(candidate.PosterRef), now.UnixMilli())
		if err != nil {
			return err
		}
	}
	_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET metadata_status='needs_review',
		metadata_error_code=NULL,metadata_error_message=NULL,updated_at_ms=? WHERE id=?`, now.UnixMilli(), itemID)
	if err != nil {
		return err
	}
	if err := completeScrapeJob(ctx, tx, itemID, now); err != nil {
		return err
	}
	return tx.Commit()
}

// CompleteMetadata atomically commits provider data, titles, artwork, and job completion.
func (r *CatalogRepository) CompleteMetadata(ctx context.Context, value domain.CatalogMetadataResult, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var sourceID, kind string
	err = tx.QueryRowContext(ctx, `SELECT source_id,kind FROM catalog_items WHERE id=?`, value.ItemID).Scan(&sourceID, &kind)
	if err != nil {
		return err
	}
	var duplicate string
	err = tx.QueryRowContext(ctx, `SELECT id FROM catalog_items WHERE source_id=? AND kind=? AND provider=? AND provider_item_id=? AND id<>? LIMIT 1`,
		sourceID, kind, value.Provider, value.ProviderItemID, value.ItemID).Scan(&duplicate)
	if err == nil {
		return fmt.Errorf("provider identity already belongs to catalog item %s", duplicate)
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET
		title=CASE WHEN locked=1 THEN title ELSE ? END,
		sort_title=CASE WHEN locked=1 THEN sort_title ELSE ? END,
		year=CASE WHEN locked=1 THEN year ELSE ? END,
		original_title=?,overview=?,tagline=?,release_date=?,end_date=?,runtime_ms=?,certification=?,
		community_rating=?,vote_count=?,genres_json=?,countries_json=?,studios_json=?,credits_json=?,external_ids_json=?,
		provider=CASE WHEN identity_locked=1 AND provider IS NOT NULL THEN provider ELSE ? END,
		provider_item_id=CASE WHEN identity_locked=1 AND provider_item_id IS NOT NULL THEN provider_item_id ELSE ? END,
		metadata_origin=?,metadata_status='ready',metadata_revision=metadata_revision+1,
		metadata_error_code=NULL,metadata_error_message=NULL,metadata_updated_at_ms=?,updated_at_ms=?
		WHERE id=?`,
		value.Title, catalog.NormalizeTitle(value.Title), nullableInt(value.Year),
		value.OriginalTitle, value.Overview, value.Tagline,
		value.ReleaseDate, value.EndDate, nullableInt64(value.RuntimeMS), value.Certification,
		nullableFloat(value.CommunityRating), value.VoteCount, value.GenresJSON, value.CountriesJSON,
		value.StudiosJSON, value.CreditsJSON, value.ExternalIDsJSON, value.Provider, value.ProviderItemID,
		metadataOrigin(value.Provider),
		now.UnixMilli(), now.UnixMilli(), value.ItemID)
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM catalog_titles WHERE catalog_item_id=?`, value.ItemID); err != nil {
		return err
	}
	titles := append([]struct{ title, kind string }{{value.Title, "display"}, {value.OriginalTitle, "original"}}, makeTitleRows(value.AlternativeTitles)...)
	for _, title := range titles {
		if title.title == "" || catalog.NormalizeTitle(title.title) == "" {
			continue
		}
		_, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO catalog_titles(
			catalog_item_id,title,normalized_title,language,title_type,created_at_ms
		) VALUES(?,?,?,'',?,?)`, value.ItemID, title.title, catalog.NormalizeTitle(title.title), title.kind, now.UnixMilli())
		if err != nil {
			return err
		}
	}
	if err := upsertArtwork(ctx, tx, value.ItemID, "poster", value.Provider, value.PosterRef, now); err != nil {
		return err
	}
	if err := upsertArtwork(ctx, tx, value.ItemID, "backdrop", value.Provider, value.BackdropRef, now); err != nil {
		return err
	}
	if err := replaceCreditArtwork(ctx, tx, value.ItemID, value.CreditsJSON, now); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM catalog_match_candidates WHERE catalog_item_id=?`, value.ItemID); err != nil {
		return err
	}
	if err := completeScrapeJob(ctx, tx, value.ItemID, now); err != nil {
		return err
	}
	return tx.Commit()
}

// FailMetadata records one failure and requeues at most three attempts.
func (r *CatalogRepository) FailMetadata(ctx context.Context, itemID, code, message string, retryAt, now time.Time) (bool, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	var attempts int
	if err := tx.QueryRowContext(ctx, `SELECT attempt_count FROM catalog_scrape_jobs WHERE catalog_item_id=?`, itemID).Scan(&attempts); err != nil {
		return false, err
	}
	requeue := attempts < 3 && !retryAt.IsZero()
	status, metadataStatus := "failed", "failed"
	if requeue {
		status, metadataStatus = "pending", "pending"
	}
	available := now
	if requeue {
		available = retryAt
	}
	_, err = tx.ExecContext(ctx, `UPDATE catalog_scrape_jobs SET status=?,available_at_ms=?,
		locked_at_ms=NULL,locked_by=NULL,error_code=?,error_message=?,updated_at_ms=?,
		finished_at_ms=CASE WHEN ?='failed' THEN ? ELSE NULL END WHERE catalog_item_id=?`,
		status, available.UnixMilli(), code, message, now.UnixMilli(), status, now.UnixMilli(), itemID)
	if err != nil {
		return false, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET metadata_status=?,metadata_error_code=?,
		metadata_error_message=?,updated_at_ms=? WHERE id=?`,
		metadataStatus, code, message, now.UnixMilli(), itemID)
	if err != nil {
		return false, err
	}
	return requeue, tx.Commit()
}

// RefreshMetadata 在同一事务中重排指定范围的任务并同步作品状态；任一步失败都不保留半写结果。
func (r *CatalogRepository) RefreshMetadata(ctx context.Context, itemID, sourceID string, now time.Time) (int, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	where, args := "1=1", []any{}
	if itemID != "" {
		where, args = "id=?", []any{itemID}
	} else if sourceID != "" {
		where, args = "source_id=?", []any{sourceID}
	}
	statement := `INSERT INTO catalog_scrape_jobs(catalog_item_id,status,attempt_count,available_at_ms,created_at_ms,updated_at_ms)
		SELECT id,'pending',0,?,?,? FROM catalog_items WHERE ` + where + `
		ON CONFLICT(catalog_item_id) DO UPDATE SET status='pending',attempt_count=0,available_at_ms=excluded.available_at_ms,
		locked_at_ms=NULL,locked_by=NULL,error_code=NULL,error_message=NULL,finished_at_ms=NULL,updated_at_ms=excluded.updated_at_ms`
	values := []any{now.UnixMilli(), now.UnixMilli(), now.UnixMilli()}
	values = append(values, args...)
	result, err := tx.ExecContext(ctx, statement, values...)
	if err != nil {
		return 0, fmt.Errorf("refresh metadata jobs: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("count refreshed metadata jobs: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `UPDATE catalog_items SET metadata_status='pending',
		metadata_error_code=NULL,metadata_error_message=NULL,updated_at_ms=? WHERE `+where,
		append([]any{now.UnixMilli()}, args...)...); err != nil {
		return 0, fmt.Errorf("refresh catalog metadata status: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("commit metadata refresh: %w", err)
	}
	return int(count), nil
}

// SelectMetadataIdentity locks a manually selected provider identity and requeues its work.
func (r *CatalogRepository) SelectMetadataIdentity(ctx context.Context, itemID, provider, providerItemID string, revision int, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(ctx, `UPDATE catalog_items SET provider=?,provider_item_id=?,identity_locked=1,
		metadata_status='pending',metadata_revision=metadata_revision+1,updated_at_ms=?
		WHERE id=? AND metadata_revision=?`, provider, providerItemID, now.UnixMilli(), itemID, revision)
	if err != nil {
		return err
	}
	if err := requireAffected(result, domain.ErrRevisionConflict); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO catalog_scrape_jobs(
		catalog_item_id,status,attempt_count,available_at_ms,created_at_ms,updated_at_ms
	) VALUES(?,'pending',0,?,?,?)
	ON CONFLICT(catalog_item_id) DO UPDATE SET status='pending',attempt_count=0,available_at_ms=excluded.available_at_ms,
	locked_at_ms=NULL,locked_by=NULL,error_code=NULL,error_message=NULL,finished_at_ms=NULL,updated_at_ms=excluded.updated_at_ms`,
		itemID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return err
	}
	return tx.Commit()
}

// ListMetadataCandidates returns scored candidates in deterministic order.
func (r *CatalogRepository) ListMetadataCandidates(ctx context.Context, itemID string) ([]domain.CatalogMetadataCandidate, error) {
	var exists int
	if err := r.db.QueryRowContext(ctx, `SELECT 1 FROM catalog_items WHERE id=?`, itemID).Scan(&exists); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, domain.ErrCatalogNotFound
		}
		return nil, err
	}
	rows, err := r.db.QueryContext(ctx, `SELECT id,catalog_item_id,provider,provider_item_id,title,original_title,
		year,overview,score,reasons_json,COALESCE(poster_ref,'') FROM catalog_match_candidates
		WHERE catalog_item_id=? ORDER BY score DESC,title,provider_item_id`, itemID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []domain.CatalogMetadataCandidate
	for rows.Next() {
		var value domain.CatalogMetadataCandidate
		var year sql.NullInt64
		var reasons string
		if err := rows.Scan(&value.ID, &value.ItemID, &value.Provider, &value.ProviderItemID,
			&value.Title, &value.OriginalTitle, &year, &value.Overview, &value.Score, &reasons, &value.PosterRef); err != nil {
			return nil, err
		}
		value.Year = nullInt(year)
		_ = json.Unmarshal([]byte(reasons), &value.Reasons)
		result = append(result, value)
	}
	return result, rows.Err()
}

// GetCatalogArtwork 仅在调用者有权限且来源仍启用、未删除时返回作品图片。
func (r *CatalogRepository) GetCatalogArtwork(ctx context.Context, artworkID, userID string) (domain.CatalogArtwork, error) {
	var value domain.CatalogArtwork
	err := r.db.QueryRowContext(ctx, `SELECT a.id,a.catalog_item_id,c.source_id,a.provider,a.opaque_key,
		COALESCE(a.storage_key,''),COALESCE(a.mime_type,''),COALESCE(a.content_sha256,''),a.status
		FROM (
			SELECT id,catalog_item_id,provider,opaque_key,storage_key,mime_type,content_sha256,status FROM catalog_artwork
			UNION ALL
			SELECT id,catalog_item_id,provider,opaque_key,storage_key,mime_type,content_sha256,status FROM catalog_credit_artwork
		) a JOIN catalog_items c ON c.id=a.catalog_item_id
		JOIN sources s ON s.id=c.source_id AND s.enabled=1 AND s.deleted_at_ms IS NULL
		JOIN source_grants g ON g.source_id=c.source_id AND g.user_id=?
		WHERE a.id=?`, userID, artworkID).
		Scan(&value.ID, &value.ItemID, &value.SourceID, &value.Provider, &value.OpaqueKey,
			&value.StorageKey, &value.MIMEType, &value.ContentSHA256, &value.Status)
	if errors.Is(err, sql.ErrNoRows) {
		return value, domain.ErrCatalogNotFound
	}
	return value, err
}

// UpdateCatalogArtworkCache records a validated cache file.
func (r *CatalogRepository) UpdateCatalogArtworkCache(ctx context.Context, id, key, mimeType, sha string, now time.Time) error {
	result, err := r.db.ExecContext(ctx, `UPDATE catalog_artwork SET storage_key=?,mime_type=?,
		content_sha256=?,status='ready',updated_at_ms=? WHERE id=?`, key, mimeType, sha, now.UnixMilli(), id)
	if err != nil {
		return err
	}
	if count, _ := result.RowsAffected(); count > 0 {
		return nil
	}
	result, err = r.db.ExecContext(ctx, `UPDATE catalog_credit_artwork SET storage_key=?,mime_type=?,
		content_sha256=?,status='ready',updated_at_ms=? WHERE id=?`, key, mimeType, sha, now.UnixMilli(), id)
	if err != nil {
		return err
	}
	return requireAffected(result, domain.ErrCatalogNotFound)
}

// RecoverMetadataJobs requeues interrupted work.
func (r *CatalogRepository) RecoverMetadataJobs(ctx context.Context, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `UPDATE catalog_scrape_jobs SET status='pending',locked_at_ms=NULL,
		locked_by=NULL,available_at_ms=?,updated_at_ms=? WHERE status='running'`, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET metadata_status='pending',updated_at_ms=?
		WHERE metadata_status='refreshing'`, now.UnixMilli())
	if err != nil {
		return err
	}
	return tx.Commit()
}

// MetadataSidecars returns all linked media paths and active NFO paths in the same source.
func (r *CatalogRepository) MetadataSidecars(ctx context.Context, itemID string) (domain.CatalogSidecarContext, error) {
	var result domain.CatalogSidecarContext
	if err := r.db.QueryRowContext(ctx, `SELECT source_id FROM catalog_items WHERE id=?`, itemID).Scan(&result.SourceID); err != nil {
		return result, err
	}
	mediaRows, err := r.db.QueryContext(ctx, `SELECT m.relative_path FROM catalog_media_links l
		JOIN media_items m ON m.id=l.media_id WHERE l.catalog_item_id=? AND m.status<>'missing'
		ORDER BY m.relative_path`, itemID)
	if err != nil {
		return result, err
	}
	for mediaRows.Next() {
		var path string
		if err := mediaRows.Scan(&path); err != nil {
			mediaRows.Close()
			return result, err
		}
		result.MediaPaths = append(result.MediaPaths, path)
	}
	if err := mediaRows.Close(); err != nil {
		return result, err
	}
	sidecarRows, err := r.db.QueryContext(ctx, `SELECT relative_path FROM catalog_sidecars
		WHERE source_id=? AND status='ready' ORDER BY relative_path`, result.SourceID)
	if err != nil {
		return result, err
	}
	defer sidecarRows.Close()
	for sidecarRows.Next() {
		var path string
		if err := sidecarRows.Scan(&path); err != nil {
			return result, err
		}
		result.SidecarPaths = append(result.SidecarPaths, path)
	}
	return result, sidecarRows.Err()
}

func completeScrapeJob(ctx context.Context, tx *sql.Tx, itemID string, now time.Time) error {
	_, err := tx.ExecContext(ctx, `UPDATE catalog_scrape_jobs SET status='completed',locked_at_ms=NULL,
		locked_by=NULL,error_code=NULL,error_message=NULL,finished_at_ms=?,updated_at_ms=?
		WHERE catalog_item_id=?`, now.UnixMilli(), now.UnixMilli(), itemID)
	return err
}

func upsertArtwork(ctx context.Context, tx *sql.Tx, itemID, kind, provider, ref string, now time.Time) error {
	if ref == "" {
		_, err := tx.ExecContext(ctx, `DELETE FROM catalog_artwork WHERE catalog_item_id=? AND artwork_type=?`, itemID, kind)
		return err
	}
	id := catalog.StableID("artwork", itemID, kind)
	_, err := tx.ExecContext(ctx, `INSERT INTO catalog_artwork(
		id,catalog_item_id,artwork_type,provider,opaque_key,status,created_at_ms,updated_at_ms
	) VALUES(?,?,?,?,?,'remote',?,?)
	ON CONFLICT(catalog_item_id,artwork_type) DO UPDATE SET provider=excluded.provider,opaque_key=excluded.opaque_key,
	storage_key=CASE WHEN catalog_artwork.opaque_key=excluded.opaque_key THEN catalog_artwork.storage_key ELSE NULL END,
	mime_type=CASE WHEN catalog_artwork.opaque_key=excluded.opaque_key THEN catalog_artwork.mime_type ELSE NULL END,
	content_sha256=CASE WHEN catalog_artwork.opaque_key=excluded.opaque_key THEN catalog_artwork.content_sha256 ELSE NULL END,
	status=CASE WHEN catalog_artwork.opaque_key=excluded.opaque_key THEN catalog_artwork.status ELSE 'remote' END,
	updated_at_ms=excluded.updated_at_ms`, id, itemID, kind, provider, ref, now.UnixMilli(), now.UnixMilli())
	return err
}

// replaceCreditArtwork 将本次刮削的头像引用与旧资料一起原子替换，避免向客户端暴露 Provider 地址。
func replaceCreditArtwork(ctx context.Context, tx *sql.Tx, itemID, creditsJSON string, now time.Time) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM catalog_credit_artwork WHERE catalog_item_id=?`, itemID); err != nil {
		return err
	}
	var credits []scraper.Credit
	if err := json.Unmarshal([]byte(creditsJSON), &credits); err != nil {
		return fmt.Errorf("解析演职员头像引用: %w", err)
	}
	seenPeople := make(map[string]struct{}, len(credits))
	for _, credit := range credits {
		if credit.Profile == nil || credit.Profile.Key == "" || credit.ProviderPersonID == "" {
			continue
		}
		provider := credit.Profile.ProviderID
		if provider == "" {
			continue
		}
		personKey := provider + "\x00" + credit.ProviderPersonID
		if _, exists := seenPeople[personKey]; exists {
			// 同一人员可能同时出现在演员与幕后列表，头像只需保存一次。
			continue
		}
		seenPeople[personKey] = struct{}{}
		id := catalog.StableID("credit-artwork", itemID, provider, credit.ProviderPersonID)
		_, err := tx.ExecContext(ctx, `INSERT INTO catalog_credit_artwork(
			id,catalog_item_id,provider,provider_person_id,opaque_key,status,created_at_ms,updated_at_ms
		) VALUES(?,?,?,?,?,'remote',?,?)`, id, itemID, provider, credit.ProviderPersonID,
			credit.Profile.Key, now.UnixMilli(), now.UnixMilli())
		if err != nil {
			return err
		}
	}
	return nil
}

func makeTitleRows(values []string) []struct{ title, kind string } {
	result := make([]struct{ title, kind string }, 0, len(values))
	for _, value := range values {
		result = append(result, struct{ title, kind string }{value, "alternative"})
	}
	return result
}

func nullableFloat(value *float64) any {
	if value == nil {
		return nil
	}
	return *value
}

func nullableInt64(value *int64) any {
	if value == nil {
		return nil
	}
	return *value
}

func metadataOrigin(provider string) string {
	if provider == "nfo" {
		return "nfo"
	}
	return "provider"
}
