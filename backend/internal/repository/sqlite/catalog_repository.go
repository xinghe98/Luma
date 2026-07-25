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
	var previousItemID sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT catalog_item_id FROM catalog_media_links WHERE media_id = ?`, match.MediaID).
		Scan(&previousItemID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("查询原作品文件关系: %w", err)
	}
	if match.Ignored {
		_, err = tx.ExecContext(ctx, `INSERT INTO catalog_media_links(media_id, match_status, confidence, rule_version, locked, media_updated_at_ms, created_at_ms, updated_at_ms)
			VALUES (?, 'ignored', 100, ?, 1, ?, ?, ?)
			ON CONFLICT(media_id) DO UPDATE SET catalog_item_id = NULL, season_id = NULL, episode_id = NULL,
			match_status = 'ignored', confidence = 100, locked = 1, media_updated_at_ms = excluded.media_updated_at_ms, updated_at_ms = excluded.updated_at_ms`,
			match.MediaID, catalog.RuleVersion, match.MediaUpdatedAt.UnixMilli(), nowMS, nowMS)
		if err != nil {
			return err
		}
		if previousItemID.Valid {
			if err := refreshCatalogMatchStatus(ctx, tx, previousItemID.String, nowMS); err != nil {
				return err
			}
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
		metadata_status = CASE
			WHEN catalog_items.identity_locked = 0 AND catalog_items.title <> excluded.title THEN 'pending'
			ELSE catalog_items.metadata_status
		END,
		updated_at_ms = excluded.updated_at_ms`, itemID, match.SourceID, match.Kind, match.Title, match.SortTitle,
		nullableInt(match.Year), origin(match.Locked), match.Status, boolInt(match.Locked), nowMS, nowMS)
	if err != nil {
		return fmt.Errorf("保存作品: %w", err)
	}
	if match.Provider != "" && match.ProviderItemID != "" {
		_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET provider=?,provider_item_id=?,
			metadata_status='pending',updated_at_ms=? WHERE id=? AND identity_locked=0`,
			match.Provider, match.ProviderItemID, nowMS, itemID)
		if err != nil {
			return fmt.Errorf("保存作品 Provider 身份: %w", err)
		}
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
	if err := refreshCatalogMatchStatus(ctx, tx, itemID, nowMS); err != nil {
		return err
	}
	if previousItemID.Valid && previousItemID.String != itemID {
		if err := refreshCatalogMatchStatus(ctx, tx, previousItemID.String, nowMS); err != nil {
			return err
		}
	}
	return nil
}

func refreshCatalogMatchStatus(ctx context.Context, tx *sql.Tx, itemID string, nowMS int64) error {
	_, err := tx.ExecContext(ctx, `UPDATE catalog_items SET
		match_status = CASE WHEN EXISTS (
			SELECT 1 FROM catalog_media_links l
			WHERE l.catalog_item_id = catalog_items.id AND l.match_status = 'needs_review'
		) THEN 'needs_review' ELSE 'matched' END,
		updated_at_ms = ?
		WHERE id = ?`, nowMS, itemID)
	if err != nil {
		return fmt.Errorf("汇总作品匹配状态: %w", err)
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
