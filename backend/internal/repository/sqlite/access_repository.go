package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// AccessRepository 使用 SQLite 实现身份与来源授权持久化。
type AccessRepository struct{ db *sql.DB }

func NewAccessRepository(db *sql.DB) (*AccessRepository, error) {
	if db == nil {
		return nil, errors.New("数据库不能为空")
	}
	return &AccessRepository{db: db}, nil
}

func (r *AccessRepository) FindPrincipalByTokenHash(ctx context.Context, hash string, now time.Time) (domain.Principal, error) {
	var principal domain.Principal
	err := r.db.QueryRowContext(ctx, `SELECT u.id, u.name, u.role FROM api_tokens t
		JOIN users u ON u.id = t.user_id
		WHERE t.token_hash = ? AND t.revoked_at_ms IS NULL AND u.enabled = 1
		AND (t.expires_at_ms IS NULL OR t.expires_at_ms > ?)`, hash, now.UnixMilli()).Scan(
		&principal.UserID, &principal.Name, &principal.Role)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Principal{}, domain.ErrUnauthorized
	}
	if err != nil {
		return domain.Principal{}, fmt.Errorf("查询访问令牌: %w", err)
	}
	return principal, nil
}

func (r *AccessRepository) ListUsers(ctx context.Context) ([]domain.User, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id, name, role, enabled, created_at_ms, updated_at_ms
		FROM users ORDER BY created_at_ms, id`)
	if err != nil {
		return nil, fmt.Errorf("查询用户: %w", err)
	}
	defer rows.Close()
	users := []domain.User{}
	for rows.Next() {
		user, err := scanAccessUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, user)
	}
	return users, rows.Err()
}

func (r *AccessRepository) GetUser(ctx context.Context, id string) (domain.User, error) {
	user, err := scanAccessUser(r.db.QueryRowContext(ctx, `SELECT id, name, role, enabled, created_at_ms, updated_at_ms
		FROM users WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.User{}, domain.ErrUserNotFound
	}
	return user, err
}

func (r *AccessRepository) FindUserByRequestID(ctx context.Context, requestID string) (domain.User, error) {
	user, err := scanAccessUser(r.db.QueryRowContext(ctx, `SELECT id, name, role, enabled, created_at_ms, updated_at_ms
		FROM users WHERE request_id = ?`, requestID))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.User{}, domain.ErrUserNotFound
	}
	return user, err
}

func (r *AccessRepository) CreateUser(ctx context.Context, user domain.User) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO users(id, request_id, name, role, enabled, created_at_ms, updated_at_ms)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, user.ID, nullableText(user.RequestID), user.Name, user.Role, boolInt(user.Enabled),
		user.CreatedAt.UnixMilli(), user.UpdatedAt.UnixMilli())
	if err != nil {
		return fmt.Errorf("创建用户: %w", err)
	}
	return nil
}

func (r *AccessRepository) UpdateUser(ctx context.Context, user domain.User) error {
	result, err := r.db.ExecContext(ctx, `UPDATE users SET name = ?, enabled = ?, updated_at_ms = ? WHERE id = ?`,
		user.Name, boolInt(user.Enabled), user.UpdatedAt.UnixMilli(), user.ID)
	if err != nil {
		return fmt.Errorf("更新用户: %w", err)
	}
	return requireAffected(result, domain.ErrUserNotFound)
}

func (r *AccessRepository) ListTokens(ctx context.Context, userID string) ([]domain.APIToken, error) {
	if _, err := r.GetUser(ctx, userID); err != nil {
		return nil, err
	}
	rows, err := r.db.QueryContext(ctx, `SELECT id, user_id, name, token_prefix, expires_at_ms,
		revoked_at_ms, created_at_ms, updated_at_ms FROM api_tokens WHERE user_id = ? ORDER BY created_at_ms DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	tokens := []domain.APIToken{}
	for rows.Next() {
		var token domain.APIToken
		var expires, revoked sql.NullInt64
		var created, updated int64
		if err := rows.Scan(&token.ID, &token.UserID, &token.Name, &token.TokenPrefix, &expires, &revoked, &created, &updated); err != nil {
			return nil, err
		}
		token.ExpiresAt = nullableTime(expires)
		token.RevokedAt = nullableTime(revoked)
		token.CreatedAt = time.UnixMilli(created).UTC()
		token.UpdatedAt = time.UnixMilli(updated).UTC()
		tokens = append(tokens, token)
	}
	return tokens, rows.Err()
}

func (r *AccessRepository) CreateToken(ctx context.Context, token domain.APIToken) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO api_tokens(id, request_id, user_id, name, token_hash, token_prefix,
		expires_at_ms, created_at_ms, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		token.ID, nullableText(token.RequestID), token.UserID, token.Name, token.TokenHash, token.TokenPrefix, nullableTimeMS(token.ExpiresAt),
		token.CreatedAt.UnixMilli(), token.UpdatedAt.UnixMilli())
	if err != nil {
		return fmt.Errorf("签发访问令牌: %w", err)
	}
	return nil
}

func (r *AccessRepository) FindTokenByRequestID(ctx context.Context, requestID string) (domain.APIToken, error) {
	var token domain.APIToken
	var expires, revoked sql.NullInt64
	var created, updated int64
	err := r.db.QueryRowContext(ctx, `SELECT id, user_id, name, token_prefix, expires_at_ms,
		revoked_at_ms, created_at_ms, updated_at_ms FROM api_tokens WHERE request_id = ?`, requestID).Scan(
		&token.ID, &token.UserID, &token.Name, &token.TokenPrefix, &expires, &revoked, &created, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.APIToken{}, domain.ErrTokenNotFound
	}
	if err != nil {
		return domain.APIToken{}, err
	}
	token.ExpiresAt = nullableTime(expires)
	token.RevokedAt = nullableTime(revoked)
	token.CreatedAt = time.UnixMilli(created).UTC()
	token.UpdatedAt = time.UnixMilli(updated).UTC()
	return token, nil
}

func (r *AccessRepository) RevokeToken(ctx context.Context, id string, now time.Time) error {
	result, err := r.db.ExecContext(ctx, `UPDATE api_tokens SET revoked_at_ms = ?, updated_at_ms = ?
		WHERE id = ? AND revoked_at_ms IS NULL`, now.UnixMilli(), now.UnixMilli(), id)
	if err != nil {
		return err
	}
	return requireAffected(result, domain.ErrTokenNotFound)
}

func (r *AccessRepository) ListGrants(ctx context.Context, userID string) ([]string, error) {
	if _, err := r.GetUser(ctx, userID); err != nil {
		return nil, err
	}
	rows, err := r.db.QueryContext(ctx, `SELECT source_id FROM source_grants WHERE user_id = ? ORDER BY source_id`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *AccessRepository) GrantSource(ctx context.Context, userID, sourceID string, now time.Time) error {
	if _, err := r.GetUser(ctx, userID); err != nil {
		return err
	}
	var exists int
	if err := r.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sources WHERE id = ? AND deleted_at_ms IS NULL)`, sourceID).Scan(&exists); err != nil {
		return err
	}
	if exists == 0 {
		return domain.ErrSourceNotFound
	}
	_, err := r.db.ExecContext(ctx, `INSERT OR IGNORE INTO source_grants(user_id, source_id, created_at_ms)
		VALUES (?, ?, ?)`, userID, sourceID, now.UnixMilli())
	return err
}

func (r *AccessRepository) RevokeSource(ctx context.Context, userID, sourceID string) error {
	user, err := r.GetUser(ctx, userID)
	if err != nil {
		return err
	}
	if user.Role == domain.RoleAdmin {
		return fmt.Errorf("%w: 不能移除管理员的来源授权", domain.ErrInvalidRequest)
	}
	_, err = r.db.ExecContext(ctx, `DELETE FROM source_grants WHERE user_id = ? AND source_id = ?`, userID, sourceID)
	return err
}

type accessUserScanner interface{ Scan(...any) error }

func scanAccessUser(row accessUserScanner) (domain.User, error) {
	var user domain.User
	var enabled int
	var created, updated int64
	err := row.Scan(&user.ID, &user.Name, &user.Role, &enabled, &created, &updated)
	user.Enabled = enabled == 1
	user.CreatedAt = time.UnixMilli(created).UTC()
	user.UpdatedAt = time.UnixMilli(updated).UTC()
	return user, err
}

func nullableTime(value sql.NullInt64) *time.Time {
	if !value.Valid {
		return nil
	}
	result := time.UnixMilli(value.Int64).UTC()
	return &result
}

func nullableTimeMS(value *time.Time) any {
	if value == nil {
		return nil
	}
	return value.UnixMilli()
}
