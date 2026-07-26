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

// FindPrincipalBySessionSecretHash 查询仍有效的设备会话对应身份。
func (r *AccessRepository) FindPrincipalBySessionSecretHash(ctx context.Context, hash string, now time.Time) (domain.Principal, error) {
	var principal domain.Principal
	err := r.db.QueryRowContext(ctx, `SELECT s.id, u.id, u.name, u.role FROM sessions s
		JOIN users u ON u.id = s.user_id
		WHERE s.secret_hash = ? AND s.revoked_at_ms IS NULL AND u.enabled = 1
		AND (s.expires_at_ms IS NULL OR s.expires_at_ms > ?)`, hash, now.UnixMilli()).Scan(
		&principal.CredentialID, &principal.UserID, &principal.Name, &principal.Role)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Principal{}, domain.ErrUnauthorized
	}
	if err != nil {
		return domain.Principal{}, fmt.Errorf("查询登录会话: %w", err)
	}
	return principal, nil
}

// FindUserByUsername 查询登录所需的账号字段，不将密码摘要暴露给 API 层。
func (r *AccessRepository) FindUserByUsername(ctx context.Context, username string) (domain.User, error) {
	user, err := scanAccessUser(r.db.QueryRowContext(ctx, `SELECT id, name, COALESCE(username, ''), COALESCE(password_hash, ''), role, enabled, created_at_ms, updated_at_ms
		FROM users WHERE username = ?`, username))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.User{}, domain.ErrUnauthorized
	}
	return user, err
}

func (r *AccessRepository) ListUsers(ctx context.Context) ([]domain.User, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id, name, COALESCE(username, ''), COALESCE(password_hash, ''), role, enabled, created_at_ms, updated_at_ms
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
	user, err := scanAccessUser(r.db.QueryRowContext(ctx, `SELECT id, name, COALESCE(username, ''), COALESCE(password_hash, ''), role, enabled, created_at_ms, updated_at_ms
		FROM users WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.User{}, domain.ErrUserNotFound
	}
	return user, err
}

func (r *AccessRepository) FindUserByRequestID(ctx context.Context, requestID string) (domain.User, error) {
	user, err := scanAccessUser(r.db.QueryRowContext(ctx, `SELECT id, name, COALESCE(username, ''), COALESCE(password_hash, ''), role, enabled, created_at_ms, updated_at_ms
		FROM users WHERE request_id = ?`, requestID))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.User{}, domain.ErrUserNotFound
	}
	return user, err
}

func (r *AccessRepository) CreateUser(ctx context.Context, user domain.User) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO users(id, request_id, name, username, password_hash, role, enabled, created_at_ms, updated_at_ms)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`, user.ID, nullableText(user.RequestID), user.Name, user.Username, user.PasswordHash, user.Role, boolInt(user.Enabled),
		user.CreatedAt.UnixMilli(), user.UpdatedAt.UnixMilli())
	if err != nil {
		return fmt.Errorf("创建用户: %w", err)
	}
	return nil
}

// UpdateUser 更新用户资料；停用用户时会在同一事务内撤销全部有效会话。
func (r *AccessRepository) UpdateUser(ctx context.Context, user domain.User) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(ctx, `UPDATE users SET name = ?, enabled = ?, updated_at_ms = ? WHERE id = ?`,
		user.Name, boolInt(user.Enabled), user.UpdatedAt.UnixMilli(), user.ID)
	if err != nil {
		return fmt.Errorf("更新用户: %w", err)
	}
	if err := requireAffected(result, domain.ErrUserNotFound); err != nil {
		return err
	}
	if !user.Enabled {
		if _, err := tx.ExecContext(ctx, `UPDATE sessions SET revoked_at_ms = ?, updated_at_ms = ?
			WHERE user_id = ? AND revoked_at_ms IS NULL`, user.UpdatedAt.UnixMilli(), user.UpdatedAt.UnixMilli(), user.ID); err != nil {
			return fmt.Errorf("停用用户时撤销会话: %w", err)
		}
	}
	return tx.Commit()
}

// InitializeAdminCredentials 仅在管理员尚未初始化时写入用户名和密码摘要。
func (r *AccessRepository) InitializeAdminCredentials(ctx context.Context, username, passwordHash string, now time.Time) (bool, error) {
	result, err := r.db.ExecContext(ctx, `UPDATE users SET username = ?, password_hash = ?, updated_at_ms = ?
		WHERE id = 'user_local' AND password_hash IS NULL`, username, passwordHash, now.UnixMilli())
	if err != nil {
		return false, fmt.Errorf("初始化管理员账号: %w", err)
	}
	affected, err := result.RowsAffected()
	return affected == 1, err
}

// ResetPassword 在同一事务内更新密码摘要并撤销用户的全部有效会话。
func (r *AccessRepository) ResetPassword(ctx context.Context, userID, passwordHash string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(ctx, `UPDATE users SET password_hash = ?, updated_at_ms = ? WHERE id = ?`, passwordHash, now.UnixMilli(), userID)
	if err != nil {
		return fmt.Errorf("更新密码: %w", err)
	}
	if err := requireAffected(result, domain.ErrUserNotFound); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE sessions SET revoked_at_ms = ?, updated_at_ms = ?
		WHERE user_id = ? AND revoked_at_ms IS NULL`, now.UnixMilli(), now.UnixMilli(), userID); err != nil {
		return fmt.Errorf("重置密码时撤销会话: %w", err)
	}
	return tx.Commit()
}

// ListSessions 返回指定账号尚未撤销的设备会话，不读取密钥摘要与 device_key。
func (r *AccessRepository) ListSessions(ctx context.Context, userID string) ([]domain.Session, error) {
	if _, err := r.GetUser(ctx, userID); err != nil {
		return nil, err
	}
	rows, err := r.db.QueryContext(ctx, `SELECT id, user_id, name, secret_prefix, expires_at_ms,
		revoked_at_ms, created_at_ms, updated_at_ms FROM sessions
		WHERE user_id = ? AND revoked_at_ms IS NULL ORDER BY created_at_ms DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	sessions := []domain.Session{}
	for rows.Next() {
		var session domain.Session
		var expires, revoked sql.NullInt64
		var created, updated int64
		if err := rows.Scan(&session.ID, &session.UserID, &session.Name, &session.SecretPrefix, &expires, &revoked, &created, &updated); err != nil {
			return nil, err
		}
		session.ExpiresAt = nullableTime(expires)
		session.RevokedAt = nullableTime(revoked)
		session.CreatedAt = time.UnixMilli(created).UTC()
		session.UpdatedAt = time.UnixMilli(updated).UTC()
		sessions = append(sessions, session)
	}
	return sessions, rows.Err()
}

// ReplaceSession 在单个事务中撤销同设备旧会话并保存新会话，明文密钥不落库。
func (r *AccessRepository) ReplaceSession(ctx context.Context, session domain.Session) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if session.DeviceKey != "" {
		if _, err := tx.ExecContext(ctx, `UPDATE sessions SET revoked_at_ms = ?, updated_at_ms = ?
			WHERE user_id = ? AND device_key = ? AND revoked_at_ms IS NULL`,
			session.CreatedAt.UnixMilli(), session.UpdatedAt.UnixMilli(), session.UserID, session.DeviceKey); err != nil {
			return fmt.Errorf("撤销同设备旧会话: %w", err)
		}
	}
	deviceKey := nullableText(session.DeviceKey)
	_, err = tx.ExecContext(ctx, `INSERT INTO sessions(id, user_id, name, device_key, secret_hash, secret_prefix,
		expires_at_ms, created_at_ms, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		session.ID, session.UserID, session.Name, deviceKey, session.SecretHash, session.SecretPrefix, nullableTimeMS(session.ExpiresAt),
		session.CreatedAt.UnixMilli(), session.UpdatedAt.UnixMilli())
	if err != nil {
		return fmt.Errorf("创建登录会话: %w", err)
	}
	return tx.Commit()
}

// RevokeSession 使指定设备会话立即失效，不删除审计元数据。
func (r *AccessRepository) RevokeSession(ctx context.Context, id string, now time.Time) error {
	result, err := r.db.ExecContext(ctx, `UPDATE sessions SET revoked_at_ms = ?, updated_at_ms = ?
		WHERE id = ? AND revoked_at_ms IS NULL`, now.UnixMilli(), now.UnixMilli(), id)
	if err != nil {
		return err
	}
	return requireAffected(result, domain.ErrSessionNotFound)
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
	err := row.Scan(&user.ID, &user.Name, &user.Username, &user.PasswordHash, &user.Role, &enabled, &created, &updated)
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
