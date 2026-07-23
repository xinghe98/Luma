package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/catalog"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

type CatalogRepository struct{ db *sql.DB }

func NewCatalogRepository(db *sql.DB) (*CatalogRepository, error) {
	if db == nil {
		return nil, errors.New("数据库不能为空")
	}
	return &CatalogRepository{db: db}, nil
}

func (r *CatalogRepository) ListCandidates(ctx context.Context, limit int) ([]domain.CatalogCandidate, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT m.id, m.source_id, s.library_kind, m.relative_path, m.filename, m.updated_at_ms
		FROM media_items m JOIN sources s ON s.id = m.source_id
		LEFT JOIN catalog_media_links l ON l.media_id = m.id
		WHERE m.media_type = 'video' AND m.status <> 'missing' AND s.enabled = 1 AND s.deleted_at_ms IS NULL
		AND s.library_kind IN ('movies', 'tv')
		AND (l.media_id IS NULL OR (l.locked = 0 AND (
			l.media_updated_at_ms <> m.updated_at_ms OR l.rule_version <> ? OR
			(s.library_kind = 'movies' AND EXISTS (SELECT 1 FROM catalog_items ci WHERE ci.id = l.catalog_item_id AND ci.kind <> 'movie')) OR
			(s.library_kind = 'tv' AND EXISTS (SELECT 1 FROM catalog_items ci WHERE ci.id = l.catalog_item_id AND ci.kind <> 'series'))
		)))
		ORDER BY m.updated_at_ms, m.id LIMIT ?`, catalog.RuleVersion, limit)
	if err != nil {
		return nil, fmt.Errorf("查询待整理媒体: %w", err)
	}
	defer rows.Close()
	items := make([]domain.CatalogCandidate, 0, limit)
	for rows.Next() {
		var item domain.CatalogCandidate
		var updated int64
		if err := rows.Scan(&item.MediaID, &item.SourceID, &item.LibraryKind, &item.RelativePath, &item.Filename, &updated); err != nil {
			return nil, err
		}
		item.MediaUpdatedAt = time.UnixMilli(updated).UTC()
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *CatalogRepository) GetCandidate(ctx context.Context, mediaID string) (domain.CatalogCandidate, error) {
	var item domain.CatalogCandidate
	var updated int64
	err := r.db.QueryRowContext(ctx, `SELECT m.id, m.source_id, s.library_kind, m.relative_path, m.filename, m.updated_at_ms
		FROM media_items m JOIN sources s ON s.id = m.source_id
		WHERE m.id = ? AND m.media_type = 'video' AND m.status <> 'missing' AND s.enabled = 1 AND s.deleted_at_ms IS NULL`, mediaID).
		Scan(&item.MediaID, &item.SourceID, &item.LibraryKind, &item.RelativePath, &item.Filename, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		return item, domain.ErrMediaNotFound
	}
	if err != nil {
		return item, err
	}
	item.MediaUpdatedAt = time.UnixMilli(updated).UTC()
	return item, nil
}

func (r *CatalogRepository) SaveMatch(ctx context.Context, match domain.CatalogMatch, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := r.saveMatch(ctx, tx, match, now); err != nil {
		return err
	}
	return tx.Commit()
}

// SaveMatches keeps one transaction open for a synchronization batch.  This
// removes hundreds of begin/commit cycles and their SQLite write-lock churn.
func (r *CatalogRepository) SaveMatches(ctx context.Context, matches []domain.CatalogMatch, now time.Time) error {
	if len(matches) == 0 {
		return nil
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, match := range matches {
		if err := r.saveMatch(ctx, tx, match, now); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (r *CatalogRepository) saveMatch(ctx context.Context, tx *sql.Tx, match domain.CatalogMatch, now time.Time) error {
	var err error
	nowMS := now.UnixMilli()
	if match.Ignored {
		_, err = tx.ExecContext(ctx, `INSERT INTO catalog_media_links(media_id, match_status, confidence, rule_version, locked, media_updated_at_ms, created_at_ms, updated_at_ms)
			VALUES (?, 'ignored', 100, ?, 1, ?, ?, ?)
			ON CONFLICT(media_id) DO UPDATE SET catalog_item_id = NULL, season_id = NULL, episode_id = NULL,
			match_status = 'ignored', confidence = 100, locked = 1, media_updated_at_ms = excluded.media_updated_at_ms, updated_at_ms = excluded.updated_at_ms`,
			match.MediaID, catalog.RuleVersion, match.MediaUpdatedAt.UnixMilli(), nowMS, nowMS)
		if err != nil {
			return err
		}
		return nil
	}
	yearKey := ""
	if match.Year != nil {
		yearKey = fmt.Sprint(*match.Year)
	}
	itemID := catalog.StableID("catalog", match.SourceID, match.Kind, match.SortTitle, yearKey)
	_, err = tx.ExecContext(ctx, `INSERT INTO catalog_items(id, source_id, kind, title, sort_title, year, metadata_origin, match_status, locked, created_at_ms, updated_at_ms)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET title = CASE WHEN catalog_items.locked = 1 THEN catalog_items.title ELSE excluded.title END,
		match_status = CASE WHEN catalog_items.match_status = 'needs_review' OR excluded.match_status = 'needs_review' THEN 'needs_review' ELSE 'matched' END,
		updated_at_ms = excluded.updated_at_ms`, itemID, match.SourceID, match.Kind, match.Title, match.SortTitle,
		nullableInt(match.Year), origin(match.Locked), match.Status, boolInt(match.Locked), nowMS, nowMS)
	if err != nil {
		return fmt.Errorf("保存作品: %w", err)
	}
	var seasonID, episodeID any
	if match.Kind == domain.CatalogKindSeries && match.SeasonNumber != nil && match.EpisodeNumber != nil {
		seasonKey := fmt.Sprint(*match.SeasonNumber)
		sid := catalog.StableID("season", itemID, seasonKey)
		seasonTitle := "第 " + seasonKey + " 季"
		if *match.SeasonNumber == 0 {
			seasonTitle = "特别篇"
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO catalog_seasons(id, catalog_item_id, season_number, title, created_at_ms, updated_at_ms)
			VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET updated_at_ms = excluded.updated_at_ms`, sid, itemID, *match.SeasonNumber, seasonTitle, nowMS, nowMS)
		if err != nil {
			return err
		}
		eid := catalog.StableID("episode", sid, fmt.Sprint(*match.EpisodeNumber))
		_, err = tx.ExecContext(ctx, `INSERT INTO catalog_episodes(id, season_id, episode_number, title, created_at_ms, updated_at_ms)
			VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title = CASE WHEN ? THEN excluded.title ELSE catalog_episodes.title END, updated_at_ms = excluded.updated_at_ms`,
			eid, sid, *match.EpisodeNumber, match.EpisodeTitle, nowMS, nowMS, match.Locked)
		if err != nil {
			return err
		}
		seasonID, episodeID = sid, eid
	}
	if !match.Locked {
		var duplicateCount int
		if match.Kind == domain.CatalogKindSeries && episodeID != nil {
			err = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM catalog_media_links
				WHERE episode_id = ? AND media_id <> ? AND match_status = 'matched'`, episodeID, match.MediaID).Scan(&duplicateCount)
		} else if match.Kind == domain.CatalogKindMovie {
			err = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM catalog_media_links
				WHERE catalog_item_id = ? AND media_id <> ? AND match_status = 'matched'`, itemID, match.MediaID).Scan(&duplicateCount)
		}
		if err != nil {
			return err
		}
		if duplicateCount > 0 {
			match.Status = domain.CatalogMatchNeedsReview
			match.Confidence = 40
		}
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO catalog_media_links(media_id, catalog_item_id, season_id, episode_id, match_status, confidence, rule_version, locked, media_updated_at_ms, created_at_ms, updated_at_ms)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(media_id) DO UPDATE SET catalog_item_id = excluded.catalog_item_id, season_id = excluded.season_id,
		episode_id = excluded.episode_id, match_status = excluded.match_status, confidence = excluded.confidence,
		rule_version = excluded.rule_version, locked = excluded.locked, media_updated_at_ms = excluded.media_updated_at_ms, updated_at_ms = excluded.updated_at_ms
		WHERE catalog_media_links.locked = 0 OR excluded.locked = 1`, match.MediaID, itemID, seasonID, episodeID,
		match.Status, match.Confidence, catalog.RuleVersion, boolInt(match.Locked), match.MediaUpdatedAt.UnixMilli(), nowMS, nowMS)
	if err != nil {
		return fmt.Errorf("保存作品文件关系: %w", err)
	}
	return nil
}

func (r *CatalogRepository) Prune(ctx context.Context, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `DELETE FROM catalog_media_links WHERE locked = 0 AND media_id IN (
		SELECT m.id FROM media_items m JOIN sources s ON s.id = m.source_id
		WHERE m.status = 'missing' OR s.enabled = 0 OR s.deleted_at_ms IS NOT NULL OR s.library_kind NOT IN ('movies','tv'))`)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `DELETE FROM catalog_items WHERE locked = 0 AND NOT EXISTS (
		SELECT 1 FROM catalog_media_links l WHERE l.catalog_item_id = catalog_items.id)`)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (r *CatalogRepository) List(ctx context.Context, request domain.CatalogListRequest, userID string) ([]domain.CatalogItem, error) {
	return r.queryItems(ctx, request, userID, "", false)
}

func (r *CatalogRepository) Get(ctx context.Context, id, userID string) (domain.CatalogItem, error) {
	items, err := r.queryItems(ctx, domain.CatalogListRequest{Limit: 1}, userID, id, true)
	if err != nil {
		return domain.CatalogItem{}, err
	}
	if len(items) == 0 {
		return domain.CatalogItem{}, domain.ErrCatalogNotFound
	}
	return items[0], nil
}

func (r *CatalogRepository) queryItems(ctx context.Context, request domain.CatalogListRequest, userID, id string, includeEpisodes bool) ([]domain.CatalogItem, error) {
	where := `WHERE EXISTS (SELECT 1 FROM catalog_media_links visible WHERE visible.catalog_item_id = c.id AND visible.match_status = 'matched')
		AND EXISTS (SELECT 1 FROM source_grants grant_access WHERE grant_access.source_id = c.source_id AND grant_access.user_id = ?)`
	args := []any{userID}
	if id != "" {
		where += ` AND c.id = ?`
		args = append(args, id)
	}
	if request.Kind != "" {
		where += ` AND c.kind = ?`
		args = append(args, request.Kind)
	}
	if request.Query != "" {
		where += ` AND instr(lower(c.title), lower(?)) > 0`
		args = append(args, request.Query)
	}
	limit := request.Limit
	if limit <= 0 {
		limit = 50
	}
	if !includeEpisodes {
		return r.querySummaries(ctx, where, args, limit, userID)
	}
	args = append(args, limit, userID)
	statement := `WITH wanted AS (
		SELECT c.id FROM catalog_items c ` + where + ` ORDER BY c.updated_at_ms DESC, c.id DESC LIMIT ?
	) SELECT c.id, c.source_id, c.kind, c.title, c.year, c.match_status, c.updated_at_ms,
		l.media_id, se.season_number, e.episode_number, COALESCE(e.title, ''), m.duration_ms, m.width, m.height,
		COALESCE(u.progress_ms, 0), COALESCE(u.completed, 0), EXISTS(
			SELECT 1 FROM media_assets a WHERE a.media_id = m.id AND a.asset_type = 'thumbnail' AND a.variant = 'default' AND a.status = 'ready'
		), COALESCE((
			SELECT poster.id FROM media_items poster
			WHERE poster.source_id = c.source_id AND poster.media_type = 'image' AND poster.status = 'ready'
			AND lower(poster.filename) IN ('poster.jpg','poster.jpeg','poster.png','poster.webp','folder.jpg','folder.jpeg','folder.png','folder.webp','cover.jpg','cover.jpeg','cover.png','cover.webp')
			AND length(poster.relative_path) > length(poster.filename)
			AND EXISTS (SELECT 1 FROM media_assets poster_asset WHERE poster_asset.media_id = poster.id
				AND poster_asset.asset_type = 'thumbnail' AND poster_asset.variant = 'default' AND poster_asset.status = 'ready')
			AND EXISTS (SELECT 1 FROM catalog_media_links poster_link
				JOIN media_items poster_video ON poster_video.id = poster_link.media_id
				WHERE poster_link.catalog_item_id = c.id AND poster_link.match_status = 'matched'
				AND substr(poster_video.relative_path, 1, length(poster.relative_path) - length(poster.filename)) =
					substr(poster.relative_path, 1, length(poster.relative_path) - length(poster.filename)))
			ORDER BY length(poster.relative_path) - length(poster.filename) DESC,
				CASE lower(poster.filename) WHEN 'poster.jpg' THEN 0 WHEN 'poster.jpeg' THEN 1 WHEN 'poster.png' THEN 2 WHEN 'poster.webp' THEN 3 WHEN 'folder.jpg' THEN 4 ELSE 5 END,
				poster.id LIMIT 1
		), '')
		FROM wanted w JOIN catalog_items c ON c.id = w.id
		JOIN catalog_media_links l ON l.catalog_item_id = c.id AND l.match_status = 'matched'
		JOIN media_items m ON m.id = l.media_id AND m.status <> 'missing'
		LEFT JOIN catalog_seasons se ON se.id = l.season_id
		LEFT JOIN catalog_episodes e ON e.id = l.episode_id
		LEFT JOIN media_user_data u ON u.media_id = m.id AND u.user_id = ?
		ORDER BY c.updated_at_ms DESC, c.id DESC, COALESCE(se.season_number, 0), COALESCE(e.episode_number, 0), l.media_id`
	rows, err := r.db.QueryContext(ctx, statement, args...)
	if err != nil {
		return nil, fmt.Errorf("查询作品库: %w", err)
	}
	defer rows.Close()
	items := []domain.CatalogItem{}
	index := map[string]int{}
	for rows.Next() {
		var id, sourceID, kind, title, status, mediaID, episodeTitle, posterMediaID string
		var year, season, episode, duration, width, height sql.NullInt64
		var updatedMS, progress int64
		var completed, hasThumbnail int
		if err := rows.Scan(&id, &sourceID, &kind, &title, &year, &status, &updatedMS, &mediaID, &season, &episode, &episodeTitle, &duration, &width, &height, &progress, &completed, &hasThumbnail, &posterMediaID); err != nil {
			return nil, err
		}
		position, exists := index[id]
		if !exists {
			item := domain.CatalogItem{ID: id, SourceID: sourceID, Kind: kind, Title: title, Year: nullInt(year), MatchStatus: status, UpdatedAt: time.UnixMilli(updatedMS).UTC()}
			if includeEpisodes {
				item.Episodes = []domain.CatalogEpisode{}
			}
			items = append(items, item)
			position = len(items) - 1
			index[id] = position
		}
		item := &items[position]
		item.MediaCount++
		if completed == 1 {
			item.CompletedCount++
		}
		if item.PlayableMediaID == "" || (item.Completed && completed == 0) {
			item.PlayableMediaID = mediaID
			item.DurationMS = nullInt64(duration)
			item.Resolution = catalogResolution(width, height)
			item.ProgressMS = progress
			item.Completed = completed == 1
		}
		if item.ThumbnailMediaID == "" && hasThumbnail == 1 {
			item.ThumbnailMediaID = mediaID
		}
		if item.PosterMediaID == "" && posterMediaID != "" {
			item.PosterMediaID = posterMediaID
		}
		if episode.Valid {
			item.EpisodeCount++
			if includeEpisodes {
				item.Episodes = append(item.Episodes, domain.CatalogEpisode{ID: catalog.StableID("episodeview", mediaID), SeasonNumber: int(season.Int64), EpisodeNumber: int(episode.Int64), Title: episodeTitle, MediaID: mediaID, DurationMS: nullInt64(duration), Resolution: catalogResolution(width, height), ProgressMS: progress, Completed: completed == 1, ThumbnailMediaID: mediaID})
			}
		}
	}
	return items, rows.Err()
}

// querySummaries keeps the catalog landing page at one result row per work.
// Episode detail is intentionally loaded only by Get, rather than materialized
// into list responses and then discarded by the HTTP presenter.
func (r *CatalogRepository) querySummaries(ctx context.Context, where string, args []any, limit int, userID string) ([]domain.CatalogItem, error) {
	args = append(args, limit, userID)
	statement := `WITH wanted AS (
		SELECT c.id FROM catalog_items c ` + where + ` ORDER BY c.updated_at_ms DESC, c.id DESC LIMIT ?
	), media_rows AS (
		SELECT c.id, c.source_id, c.kind, c.title, c.year, c.match_status, c.updated_at_ms,
			l.media_id, m.duration_ms, m.width, m.height, COALESCE(u.progress_ms, 0) AS progress_ms,
			COALESCE(u.completed, 0) AS completed,
			CASE WHEN e.id IS NULL THEN 0 ELSE 1 END AS has_episode,
			CASE WHEN EXISTS(
				SELECT 1 FROM media_assets a WHERE a.media_id = m.id
				AND a.asset_type = 'thumbnail' AND a.variant = 'default' AND a.status = 'ready'
			) THEN 1 ELSE 0 END AS has_thumbnail,
			ROW_NUMBER() OVER (
				PARTITION BY c.id ORDER BY CASE WHEN COALESCE(u.completed, 0) = 0 THEN 0 ELSE 1 END,
				COALESCE(se.season_number, 0), COALESCE(e.episode_number, 0), l.media_id
			) AS playable_rank,
			ROW_NUMBER() OVER (
				PARTITION BY c.id ORDER BY CASE WHEN EXISTS(
					SELECT 1 FROM media_assets a WHERE a.media_id = m.id
					AND a.asset_type = 'thumbnail' AND a.variant = 'default' AND a.status = 'ready'
				) THEN 0 ELSE 1 END, COALESCE(se.season_number, 0), COALESCE(e.episode_number, 0), l.media_id
			) AS thumbnail_rank
		FROM wanted w JOIN catalog_items c ON c.id = w.id
		JOIN catalog_media_links l ON l.catalog_item_id = c.id AND l.match_status = 'matched'
		JOIN media_items m ON m.id = l.media_id AND m.status <> 'missing'
		LEFT JOIN catalog_seasons se ON se.id = l.season_id
		LEFT JOIN catalog_episodes e ON e.id = l.episode_id
		LEFT JOIN media_user_data u ON u.media_id = m.id AND u.user_id = ?
	) SELECT id, source_id, kind, title, year, match_status, updated_at_ms,
		COUNT(*) AS media_count, SUM(has_episode) AS episode_count, SUM(completed) AS completed_count,
		COALESCE(MAX(CASE WHEN playable_rank = 1 THEN media_id END), '') AS playable_media_id,
		MAX(CASE WHEN playable_rank = 1 THEN duration_ms END) AS playable_duration_ms,
		MAX(CASE WHEN playable_rank = 1 THEN width END) AS playable_width,
		MAX(CASE WHEN playable_rank = 1 THEN height END) AS playable_height,
		COALESCE(MAX(CASE WHEN playable_rank = 1 THEN progress_ms END), 0) AS playable_progress_ms,
		COALESCE(MAX(CASE WHEN playable_rank = 1 THEN completed END), 0) AS playable_completed,
		COALESCE(MAX(CASE WHEN thumbnail_rank = 1 AND has_thumbnail = 1 THEN media_id END), '') AS thumbnail_media_id,
		COALESCE((
			SELECT poster.id FROM media_items poster
			WHERE poster.source_id = media_rows.source_id AND poster.media_type = 'image' AND poster.status = 'ready'
			AND lower(poster.filename) IN ('poster.jpg','poster.jpeg','poster.png','poster.webp','folder.jpg','folder.jpeg','folder.png','folder.webp','cover.jpg','cover.jpeg','cover.png','cover.webp')
			AND length(poster.relative_path) > length(poster.filename)
			AND EXISTS (SELECT 1 FROM media_assets poster_asset WHERE poster_asset.media_id = poster.id
				AND poster_asset.asset_type = 'thumbnail' AND poster_asset.variant = 'default' AND poster_asset.status = 'ready')
			AND EXISTS (SELECT 1 FROM catalog_media_links poster_link
				JOIN media_items poster_video ON poster_video.id = poster_link.media_id
				WHERE poster_link.catalog_item_id = media_rows.id AND poster_link.match_status = 'matched'
				AND substr(poster_video.relative_path, 1, length(poster.relative_path) - length(poster.filename)) =
					substr(poster.relative_path, 1, length(poster.relative_path) - length(poster.filename)))
			ORDER BY length(poster.relative_path) - length(poster.filename) DESC,
				CASE lower(poster.filename) WHEN 'poster.jpg' THEN 0 WHEN 'poster.jpeg' THEN 1 WHEN 'poster.png' THEN 2 WHEN 'poster.webp' THEN 3 WHEN 'folder.jpg' THEN 4 ELSE 5 END,
				poster.id LIMIT 1
		), '') AS poster_media_id
		FROM media_rows GROUP BY id, source_id, kind, title, year, match_status, updated_at_ms
		ORDER BY updated_at_ms DESC, id DESC`
	rows, err := r.db.QueryContext(ctx, statement, args...)
	if err != nil {
		return nil, fmt.Errorf("查询作品库摘要: %w", err)
	}
	defer rows.Close()
	items := make([]domain.CatalogItem, 0, limit)
	for rows.Next() {
		var item domain.CatalogItem
		var year sql.NullInt64
		var updatedMS int64
		var duration, width, height sql.NullInt64
		var completed int
		if err := rows.Scan(&item.ID, &item.SourceID, &item.Kind, &item.Title, &year, &item.MatchStatus, &updatedMS,
			&item.MediaCount, &item.EpisodeCount, &item.CompletedCount, &item.PlayableMediaID, &duration, &width, &height,
			&item.ProgressMS, &completed, &item.ThumbnailMediaID, &item.PosterMediaID); err != nil {
			return nil, err
		}
		item.Year = nullInt(year)
		item.UpdatedAt = time.UnixMilli(updatedMS).UTC()
		item.DurationMS = nullInt64(duration)
		item.Resolution = catalogResolution(width, height)
		item.Completed = completed == 1
		items = append(items, item)
	}
	return items, rows.Err()
}

func catalogResolution(width, height sql.NullInt64) string {
	if !width.Valid || !height.Valid || width.Int64 <= 0 || height.Int64 <= 0 {
		return ""
	}
	return fmt.Sprintf("%d×%d", width.Int64, height.Int64)
}

func (r *CatalogRepository) ListIssues(ctx context.Context, limit int) ([]domain.CatalogIssue, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT m.id, m.filename, m.source_id, s.library_kind, COALESCE(c.title, ''), se.season_number, e.episode_number
		FROM catalog_media_links l JOIN media_items m ON m.id = l.media_id JOIN sources s ON s.id = m.source_id
		LEFT JOIN catalog_items c ON c.id = l.catalog_item_id LEFT JOIN catalog_seasons se ON se.id = l.season_id
		LEFT JOIN catalog_episodes e ON e.id = l.episode_id WHERE l.match_status = 'needs_review'
		ORDER BY l.updated_at_ms DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []domain.CatalogIssue{}
	for rows.Next() {
		var item domain.CatalogIssue
		var season, episode sql.NullInt64
		if err := rows.Scan(&item.MediaID, &item.Filename, &item.SourceID, &item.LibraryKind, &item.SuggestedTitle, &season, &episode); err != nil {
			return nil, err
		}
		item.SeasonNumber = nullInt(season)
		item.EpisodeNumber = nullInt(episode)
		items = append(items, item)
	}
	return items, rows.Err()
}

func nullableInt(value *int) any {
	if value == nil {
		return nil
	}
	return *value
}
func origin(locked bool) string {
	if locked {
		return "user"
	}
	return "filename"
}
