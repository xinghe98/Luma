-- 已登录设备不再按时间过期，只能由用户、管理员或账号状态变更撤销。
UPDATE sessions
SET expires_at_ms = NULL
WHERE expires_at_ms IS NOT NULL;
