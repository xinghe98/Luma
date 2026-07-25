-- 用户名密码登录替换旧的手工 Token。历史 Token 统一撤销，永不再参与认证。
ALTER TABLE users ADD COLUMN username TEXT COLLATE NOCASE;
ALTER TABLE users ADD COLUMN password_hash TEXT;

CREATE UNIQUE INDEX idx_users_username
ON users(username COLLATE NOCASE) WHERE username IS NOT NULL;

ALTER TABLE api_tokens ADD COLUMN kind TEXT NOT NULL DEFAULT 'legacy'
    CHECK (kind IN ('legacy', 'session'));

UPDATE api_tokens
SET kind = 'legacy',
    revoked_at_ms = COALESCE(revoked_at_ms, CAST(strftime('%s', 'now') AS INTEGER) * 1000),
    updated_at_ms = CAST(strftime('%s', 'now') AS INTEGER) * 1000;
