-- 安装级 device_key 用于同设备重登时顶替旧会话；不对外暴露。
ALTER TABLE sessions ADD COLUMN device_key TEXT;

CREATE UNIQUE INDEX idx_sessions_active_user_device_key
ON sessions(user_id, device_key)
WHERE device_key IS NOT NULL AND length(device_key) > 0 AND revoked_at_ms IS NULL;
