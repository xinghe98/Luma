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

// UserDataRepository 使用 SQLite 原子保存用户媒体数据和标签关系。
type UserDataRepository struct {
	db *sql.DB
}

// NewUserDataRepository 创建用户数据 Repository。
func NewUserDataRepository(db *sql.DB) (*UserDataRepository, error) {
	if db == nil {
		return nil, errors.New("数据库不能为空")
	}
	return &UserDataRepository{db: db}, nil
}

type userDataQuerier interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}

// Get 返回可见媒体的当前用户数据；没有记录时返回 revision=0 的默认值。
func (r *UserDataRepository) Get(ctx context.Context, userID, mediaID string) (domain.MediaUserData, error) {
	if err := requireVisibleMedia(ctx, r.db, userID, mediaID); err != nil {
		return domain.MediaUserData{}, err
	}
	return readUserData(ctx, r.db, userID, mediaID)
}

// Update 在同一事务中更新用户数据并可选地完整替换标签关系。
func (r *UserDataRepository) Update(ctx context.Context, command domain.UpdateUserDataCommand, now time.Time) (domain.MediaUserData, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.MediaUserData{}, fmt.Errorf("开始用户数据事务: %w", err)
	}
	defer tx.Rollback()
	if err := requireVisibleMedia(ctx, tx, command.UserID, command.MediaID); err != nil {
		return domain.MediaUserData{}, err
	}
	current, err := readUserDataRecord(ctx, tx, command.UserID, command.MediaID)
	if err != nil {
		return domain.MediaUserData{}, err
	}
	if current.Revision != command.BaseRevision {
		return domain.MediaUserData{}, domain.ErrRevisionConflict
	}
	if command.CustomTitle.Set {
		current.CustomTitle = command.CustomTitle.Value
	}
	if command.Favorite.Set {
		current.Favorite = *command.Favorite.Value
	}
	if command.Notes.Set {
		current.Notes = command.Notes.Value
	}
	if command.TagIDs.Set {
		if command.TagIDs.Value == nil {
			return domain.MediaUserData{}, fmt.Errorf("%w: tag_ids 不能为 null", domain.ErrInvalidRequest)
		}
		if err := requireOwnedTags(ctx, tx, command.UserID, *command.TagIDs.Value); err != nil {
			return domain.MediaUserData{}, err
		}
	}

	now = now.UTC()
	nowMS := now.UnixMilli()
	nextRevision := current.Revision + 1
	if current.Revision == 0 {
		_, err = tx.ExecContext(ctx, `INSERT INTO media_user_data(
            user_id, media_id, custom_title, favorite, notes, progress_ms, completed,
            last_played_at_ms, created_at_ms, updated_at_ms, revision
        ) VALUES (?, ?, ?, ?, ?, 0, 0, NULL, ?, ?, 1)`, command.UserID, command.MediaID,
			nullableString(current.CustomTitle), boolInt(current.Favorite), nullableString(current.Notes), nowMS, nowMS)
	} else {
		var result sql.Result
		result, err = tx.ExecContext(ctx, `UPDATE media_user_data SET custom_title = ?, favorite = ?, notes = ?,
            updated_at_ms = ?, revision = ? WHERE user_id = ? AND media_id = ? AND revision = ?`,
			nullableString(current.CustomTitle), boolInt(current.Favorite), nullableString(current.Notes), nowMS,
			nextRevision, command.UserID, command.MediaID, command.BaseRevision)
		if err == nil {
			err = requireAffected(result, domain.ErrRevisionConflict)
		}
	}
	if err != nil {
		if isUniqueConstraint(err) {
			return domain.MediaUserData{}, domain.ErrRevisionConflict
		}
		return domain.MediaUserData{}, fmt.Errorf("保存用户数据: %w", err)
	}
	if command.TagIDs.Set {
		if _, err := tx.ExecContext(ctx, `DELETE FROM media_tags WHERE user_id = ? AND media_id = ?`, command.UserID, command.MediaID); err != nil {
			return domain.MediaUserData{}, fmt.Errorf("清除媒体标签: %w", err)
		}
		for _, tagID := range *command.TagIDs.Value {
			if _, err := tx.ExecContext(ctx, `INSERT INTO media_tags(user_id, media_id, tag_id, created_at_ms)
                    VALUES (?, ?, ?, ?)`, command.UserID, command.MediaID, tagID, nowMS); err != nil {
				if isForeignKeyConstraint(err) {
					return domain.MediaUserData{}, domain.ErrTagNotFound
				}
				return domain.MediaUserData{}, fmt.Errorf("关联媒体标签: %w", err)
			}
		}
	}
	result, err := readUserData(ctx, tx, command.UserID, command.MediaID)
	if err != nil {
		return domain.MediaUserData{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.MediaUserData{}, fmt.Errorf("提交用户数据事务: %w", err)
	}
	return result, nil
}

// UpdateProgress 在同一事务内读取媒体时长、截断进度并只更新播放状态。
func (r *UserDataRepository) UpdateProgress(ctx context.Context, command domain.UpdateProgressCommand) (domain.MediaUserData, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.MediaUserData{}, fmt.Errorf("开始进度事务: %w", err)
	}
	defer tx.Rollback()
	if err := requireVisibleMedia(ctx, tx, command.UserID, command.MediaID); err != nil {
		return domain.MediaUserData{}, err
	}
	mediaType, durationMS, err := readPlayableDuration(ctx, tx, command.UserID, command.MediaID)
	if err != nil {
		return domain.MediaUserData{}, err
	}
	if mediaType != domain.MediaTypeVideo {
		return domain.MediaUserData{}, domain.ErrMediaNotPlayable
	}
	if durationMS == nil || *durationMS <= 0 {
		return domain.MediaUserData{}, domain.ErrMediaDurationUnavailable
	}
	duration := *durationMS
	positionMS := command.PositionMS
	if positionMS > duration {
		positionMS = duration
	}
	completed := positionMS >= duration-duration/10

	current, err := readUserDataRecord(ctx, tx, command.UserID, command.MediaID)
	if err != nil {
		return domain.MediaUserData{}, err
	}
	if current.Revision != command.BaseRevision {
		return domain.MediaUserData{}, domain.ErrRevisionConflict
	}
	nowMS := command.Now.UTC().UnixMilli()
	if current.Revision == 0 {
		_, err = tx.ExecContext(ctx, `INSERT INTO media_user_data(
            user_id, media_id, favorite, progress_ms, completed, last_played_at_ms,
            created_at_ms, updated_at_ms, revision
        ) VALUES (?, ?, 0, ?, ?, ?, ?, ?, 1)`, command.UserID, command.MediaID,
			positionMS, boolInt(completed), nowMS, nowMS, nowMS)
	} else {
		var result sql.Result
		result, err = tx.ExecContext(ctx, `UPDATE media_user_data SET progress_ms = ?, completed = ?,
            last_played_at_ms = ?, updated_at_ms = ?, revision = revision + 1
            WHERE user_id = ? AND media_id = ? AND revision = ?`, positionMS,
			boolInt(completed), nowMS, nowMS, command.UserID, command.MediaID, command.BaseRevision)
		if err == nil {
			err = requireAffected(result, domain.ErrRevisionConflict)
		}
	}
	if err != nil {
		if isUniqueConstraint(err) {
			return domain.MediaUserData{}, domain.ErrRevisionConflict
		}
		return domain.MediaUserData{}, fmt.Errorf("保存播放进度: %w", err)
	}
	result, err := readUserData(ctx, tx, command.UserID, command.MediaID)
	if err != nil {
		return domain.MediaUserData{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.MediaUserData{}, fmt.Errorf("提交进度事务: %w", err)
	}
	return result, nil
}

func requireVisibleMedia(ctx context.Context, query userDataQuerier, userID, mediaID string) error {
	var exists int
	err := query.QueryRowContext(ctx, `SELECT EXISTS(
        SELECT 1 FROM media_items m JOIN sources s ON s.id = m.source_id
        WHERE m.id = ? AND m.status <> 'missing' AND s.enabled = 1 AND s.deleted_at_ms IS NULL
		AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)
    )`, mediaID, userID).Scan(&exists)
	if err != nil {
		return fmt.Errorf("检查媒体可见性: %w", err)
	}
	if exists == 0 {
		return domain.ErrMediaNotFound
	}
	return nil
}

func readPlayableDuration(ctx context.Context, query userDataQuerier, userID, mediaID string) (string, *int64, error) {
	var mediaType string
	var duration sql.NullInt64
	err := query.QueryRowContext(ctx, `SELECT m.media_type, m.duration_ms
        FROM media_items m JOIN sources s ON s.id = m.source_id
        WHERE m.id = ? AND m.status <> 'missing' AND s.enabled = 1 AND s.deleted_at_ms IS NULL
		AND EXISTS (SELECT 1 FROM source_grants g WHERE g.source_id = s.id AND g.user_id = ?)`, mediaID, userID).Scan(&mediaType, &duration)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil, domain.ErrMediaNotFound
	}
	if err != nil {
		return "", nil, fmt.Errorf("读取媒体时长: %w", err)
	}
	if !duration.Valid {
		return mediaType, nil, nil
	}
	value := duration.Int64
	return mediaType, &value, nil
}

func readUserDataRecord(ctx context.Context, query userDataQuerier, userID, mediaID string) (domain.MediaUserData, error) {
	data := domain.MediaUserData{UserID: userID, MediaID: mediaID}
	var customTitle, notes sql.NullString
	var lastPlayed sql.NullInt64
	var favorite, completed int
	var createdMS, updatedMS int64
	err := query.QueryRowContext(ctx, `SELECT custom_title, favorite, notes, progress_ms, completed,
        last_played_at_ms, revision, created_at_ms, updated_at_ms
        FROM media_user_data WHERE user_id = ? AND media_id = ?`, userID, mediaID).Scan(
		&customTitle, &favorite, &notes, &data.ProgressMS, &completed, &lastPlayed,
		&data.Revision, &createdMS, &updatedMS)
	if errors.Is(err, sql.ErrNoRows) {
		return data, nil
	}
	if err != nil {
		return domain.MediaUserData{}, fmt.Errorf("读取用户数据: %w", err)
	}
	data.CustomTitle = nullString(customTitle)
	data.Notes = nullString(notes)
	data.Favorite = favorite == 1
	data.Completed = completed == 1
	data.LastPlayedAt = nullTime(lastPlayed)
	created := time.UnixMilli(createdMS).UTC()
	updated := time.UnixMilli(updatedMS).UTC()
	data.CreatedAt = &created
	data.UpdatedAt = &updated
	return data, nil
}

func readUserData(ctx context.Context, query userDataQuerier, userID, mediaID string) (domain.MediaUserData, error) {
	data, err := readUserDataRecord(ctx, query, userID, mediaID)
	if err != nil {
		return domain.MediaUserData{}, err
	}
	rows, err := query.QueryContext(ctx, `SELECT t.id, t.user_id, t.name, t.normalized_name,
        (SELECT COUNT(*) FROM media_tags usage WHERE usage.user_id = t.user_id AND usage.tag_id = t.id),
		t.revision, t.created_at_ms, t.updated_at_ms FROM tags t
        JOIN media_tags mt ON mt.tag_id = t.id AND mt.user_id = t.user_id
        WHERE mt.user_id = ? AND mt.media_id = ? ORDER BY t.normalized_name, t.id`, userID, mediaID)
	if err != nil {
		return domain.MediaUserData{}, fmt.Errorf("查询媒体标签: %w", err)
	}
	defer rows.Close()
	data.Tags = make([]domain.Tag, 0)
	for rows.Next() {
		var tag domain.Tag
		var createdMS, updatedMS int64
		if err := rows.Scan(&tag.ID, &tag.UserID, &tag.Name, &tag.NormalizedName, &tag.UsageCount, &tag.Revision, &createdMS, &updatedMS); err != nil {
			return domain.MediaUserData{}, fmt.Errorf("读取媒体标签: %w", err)
		}
		tag.CreatedAt = time.UnixMilli(createdMS).UTC()
		tag.UpdatedAt = time.UnixMilli(updatedMS).UTC()
		data.Tags = append(data.Tags, tag)
	}
	if err := rows.Err(); err != nil {
		return domain.MediaUserData{}, fmt.Errorf("遍历媒体标签: %w", err)
	}
	return data, nil
}

func requireOwnedTags(ctx context.Context, query userDataQuerier, userID string, tagIDs []string) error {
	if len(tagIDs) == 0 {
		return nil
	}
	placeholders := strings.TrimRight(strings.Repeat("?,", len(tagIDs)), ",")
	args := make([]any, 0, len(tagIDs)+1)
	args = append(args, userID)
	for _, id := range tagIDs {
		args = append(args, id)
	}
	var count int
	if err := query.QueryRowContext(ctx, `SELECT COUNT(*) FROM tags WHERE user_id = ? AND id IN (`+placeholders+`)`, args...).Scan(&count); err != nil {
		return fmt.Errorf("验证媒体标签: %w", err)
	}
	if count != len(tagIDs) {
		return domain.ErrTagNotFound
	}
	return nil
}

func nullableString(value *string) any {
	if value == nil {
		return nil
	}
	return *value
}

func nullString(value sql.NullString) *string {
	if !value.Valid {
		return nil
	}
	result := value.String
	return &result
}
