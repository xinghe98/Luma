-- 扩展持久化任务类型，为已就绪媒体独立补齐卡片缩略图。
CREATE TABLE jobs_new (
    id TEXT PRIMARY KEY,
    job_type TEXT NOT NULL CHECK (job_type IN ('scan_source', 'probe_media', 'generate_thumbnail', 'generate_card_thumbnail', 'cleanup_assets')),
    entity_id TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'interrupted')),
    attempt_count INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 2,
    available_at_ms INTEGER NOT NULL,
    locked_at_ms INTEGER,
    locked_by TEXT,
    error_code TEXT,
    error_message TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    finished_at_ms INTEGER,
    CHECK (attempt_count >= 0),
    CHECK (max_attempts > 0)
);

INSERT INTO jobs_new SELECT * FROM jobs;

CREATE TABLE scan_jobs_new (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'interrupted')),
    phase TEXT,
    discovered_count INTEGER NOT NULL DEFAULT 0,
    processed_count INTEGER NOT NULL DEFAULT 0,
    failed_count INTEGER NOT NULL DEFAULT 0,
    started_at_ms INTEGER,
    finished_at_ms INTEGER,
    error_code TEXT,
    error_message TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY(id) REFERENCES jobs_new(id) ON DELETE CASCADE,
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE RESTRICT
);

INSERT INTO scan_jobs_new SELECT * FROM scan_jobs;
DROP TABLE scan_jobs;
DROP TABLE jobs;
ALTER TABLE jobs_new RENAME TO jobs;
ALTER TABLE scan_jobs_new RENAME TO scan_jobs;

CREATE UNIQUE INDEX idx_jobs_active_entity ON jobs(job_type, entity_id) WHERE status IN ('pending', 'running');
CREATE INDEX idx_jobs_runnable ON jobs(status, available_at_ms, created_at_ms);
CREATE INDEX idx_scan_jobs_source_created ON scan_jobs(source_id, created_at_ms DESC);
CREATE INDEX idx_jobs_processing_runnable
ON jobs(job_type, status, available_at_ms, created_at_ms, id)
WHERE job_type IN ('probe_media', 'generate_thumbnail', 'generate_card_thumbnail');
