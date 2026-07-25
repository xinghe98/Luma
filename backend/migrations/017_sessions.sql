-- 将已签发的登录会话迁移至独立表；历史手工令牌不再保留认证存储。
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    secret_hash TEXT NOT NULL UNIQUE,
    secret_prefix TEXT NOT NULL,
    expires_at_ms INTEGER,
    revoked_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

INSERT INTO sessions(id, user_id, name, secret_hash, secret_prefix, expires_at_ms, revoked_at_ms, created_at_ms, updated_at_ms)
SELECT id, user_id, name, token_hash, token_prefix, expires_at_ms, revoked_at_ms, created_at_ms, updated_at_ms
FROM api_tokens
WHERE kind = 'session';

CREATE INDEX idx_sessions_user ON sessions(user_id, revoked_at_ms);
DROP TABLE api_tokens;
