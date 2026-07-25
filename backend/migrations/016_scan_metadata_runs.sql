-- 将一次成功扫描与其后续影视资料任务绑定，供客户端追踪两阶段进度。
CREATE TABLE catalog_scrape_runs (
    scan_job_id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    FOREIGN KEY(scan_job_id) REFERENCES scan_jobs(id) ON DELETE CASCADE,
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE CASCADE
);

CREATE TABLE catalog_scrape_run_items (
    scan_job_id TEXT NOT NULL,
    catalog_item_id TEXT NOT NULL,
    PRIMARY KEY(scan_job_id, catalog_item_id),
    FOREIGN KEY(scan_job_id) REFERENCES catalog_scrape_runs(scan_job_id) ON DELETE CASCADE,
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

CREATE INDEX idx_catalog_scrape_run_items_item
ON catalog_scrape_run_items(catalog_item_id, scan_job_id);
