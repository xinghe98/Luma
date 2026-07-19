-- 重建 jobs 表，使 status 支持 interrupted，与 scan_jobs 语义对齐。
CREATE TABLE jobs_new (
    -- 任务唯一标识。
    id TEXT PRIMARY KEY,
    -- 任务类型。
    job_type TEXT NOT NULL CHECK (job_type IN ('scan_source', 'probe_media', 'generate_thumbnail', 'cleanup_assets')),
    -- 任务关联实体标识。
    entity_id TEXT NOT NULL,
    -- 任务载荷 JSON。
    payload_json TEXT NOT NULL DEFAULT '{}',
    -- 任务执行状态。
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'interrupted')),
    -- 任务已尝试次数。
    attempt_count INTEGER NOT NULL DEFAULT 0,
    -- 任务最大尝试次数。
    max_attempts INTEGER NOT NULL DEFAULT 2,
    -- 任务可执行时间戳（毫秒）。
    available_at_ms INTEGER NOT NULL,
    -- 任务锁定时间戳（毫秒）。
    locked_at_ms INTEGER,
    -- 任务锁定者标识。
    locked_by TEXT,
    -- 任务错误码。
    error_code TEXT,
    -- 任务错误信息。
    error_message TEXT,
    -- 任务创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 任务更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    -- 任务完成时间戳（毫秒）。
    finished_at_ms INTEGER,
    CHECK (attempt_count >= 0),
    CHECK (max_attempts > 0)
);

INSERT INTO jobs_new (
    id, job_type, entity_id, payload_json, status, attempt_count, max_attempts,
    available_at_ms, locked_at_ms, locked_by, error_code, error_message,
    created_at_ms, updated_at_ms, finished_at_ms
)
SELECT
    id, job_type, entity_id, payload_json, status, attempt_count, max_attempts,
    available_at_ms, locked_at_ms, locked_by, error_code, error_message,
    created_at_ms, updated_at_ms, finished_at_ms
FROM jobs;

CREATE TABLE scan_jobs_new (
    -- 扫描任务唯一标识。
    id TEXT PRIMARY KEY,
    -- 扫描媒体源标识。
    source_id TEXT NOT NULL,
    -- 扫描任务状态。
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'interrupted')),
    -- 扫描任务当前阶段。
    phase TEXT,
    -- 扫描发现的媒体数量。
    discovered_count INTEGER NOT NULL DEFAULT 0,
    -- 扫描已处理的媒体数量。
    processed_count INTEGER NOT NULL DEFAULT 0,
    -- 扫描处理失败的媒体数量。
    failed_count INTEGER NOT NULL DEFAULT 0,
    -- 扫描开始时间戳（毫秒）。
    started_at_ms INTEGER,
    -- 扫描结束时间戳（毫秒）。
    finished_at_ms INTEGER,
    -- 扫描任务错误码。
    error_code TEXT,
    -- 扫描任务错误信息。
    error_message TEXT,
    -- 扫描任务创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 扫描任务更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY(id) REFERENCES jobs_new(id) ON DELETE CASCADE,
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE RESTRICT
);

INSERT INTO scan_jobs_new (
    id, source_id, status, phase, discovered_count, processed_count, failed_count,
    started_at_ms, finished_at_ms, error_code, error_message, created_at_ms, updated_at_ms
)
SELECT
    id, source_id, status, phase, discovered_count, processed_count, failed_count,
    started_at_ms, finished_at_ms, error_code, error_message, created_at_ms, updated_at_ms
FROM scan_jobs;

DROP TABLE scan_jobs;
DROP TABLE jobs;
ALTER TABLE jobs_new RENAME TO jobs;
ALTER TABLE scan_jobs_new RENAME TO scan_jobs;

CREATE UNIQUE INDEX idx_jobs_active_entity ON jobs(job_type, entity_id) WHERE status IN ('pending', 'running');
CREATE INDEX idx_jobs_runnable ON jobs(status, available_at_ms, created_at_ms);
CREATE INDEX idx_scan_jobs_source_created ON scan_jobs(source_id, created_at_ms DESC);

-- 将历史“中断但 jobs 记为 failed”的记录对齐为 interrupted。
UPDATE jobs SET status = 'interrupted'
WHERE job_type = 'scan_source'
  AND status = 'failed'
  AND error_code = 'SCAN_INTERRUPTED';
