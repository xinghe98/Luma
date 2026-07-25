// Catalog read queries load user-visible catalog summaries and episode detail.
// They share CatalogRepository's SQLite connection and user-grant visibility rules.
package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/catalog"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

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
