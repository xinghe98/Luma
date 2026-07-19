-- 按任务类型覆盖媒体处理 Worker 的可运行任务领取顺序。
CREATE INDEX idx_jobs_processing_runnable
ON jobs(job_type, status, available_at_ms, created_at_ms, id)
WHERE job_type IN ('probe_media', 'generate_thumbnail');
