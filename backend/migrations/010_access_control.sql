-- 将单一服务 Token 扩展为用户身份与媒体源授权。旧用户保留为管理员。
ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('admin', 'member'));
ALTER TABLE users ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1
    CHECK (enabled IN (0, 1));
UPDATE users SET role = 'admin' WHERE id = 'user_local';

-- 成员 Token 只保存不可逆摘要；明文仅在签发时返回一次。
CREATE TABLE api_tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    token_prefix TEXT NOT NULL,
    expires_at_ms INTEGER,
    revoked_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- 媒体源是权限边界；没有显式授权时默认不可见。
CREATE TABLE source_grants (
    user_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    PRIMARY KEY(user_id, source_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE CASCADE
);

CREATE INDEX idx_api_tokens_user ON api_tokens(user_id, revoked_at_ms);
CREATE INDEX idx_source_grants_source ON source_grants(source_id, user_id);

-- 管理员始终拥有全部来源；以后新建来源也自动获得授权。
INSERT OR IGNORE INTO source_grants(user_id, source_id, created_at_ms)
SELECT u.id, s.id, CAST(strftime('%s', 'now') AS INTEGER) * 1000
FROM users u CROSS JOIN sources s
WHERE u.role = 'admin' AND s.deleted_at_ms IS NULL;

CREATE TRIGGER grant_new_source_to_admins
AFTER INSERT ON sources
BEGIN
    INSERT OR IGNORE INTO source_grants(user_id, source_id, created_at_ms)
    SELECT id, NEW.id, CAST(strftime('%s', 'now') AS INTEGER) * 1000 FROM users WHERE role = 'admin';
END;
