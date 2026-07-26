-- 为升级前遗留的永久会话设置迁移日起 30 天期限；新会话期限由签发服务逐步接管。
UPDATE sessions
SET expires_at_ms = CAST(strftime('%s', 'now', '+30 days') AS INTEGER) * 1000,
    updated_at_ms = CAST(strftime('%s', 'now') AS INTEGER) * 1000
WHERE expires_at_ms IS NULL AND revoked_at_ms IS NULL;
