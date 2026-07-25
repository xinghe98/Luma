-- 作品级丰富元数据与刮削状态；所有在线内容仅写入 Luma 数据目录。
ALTER TABLE catalog_items ADD COLUMN original_title TEXT;
ALTER TABLE catalog_items ADD COLUMN overview TEXT;
ALTER TABLE catalog_items ADD COLUMN tagline TEXT;
ALTER TABLE catalog_items ADD COLUMN release_date TEXT;
ALTER TABLE catalog_items ADD COLUMN end_date TEXT;
ALTER TABLE catalog_items ADD COLUMN runtime_ms INTEGER CHECK (runtime_ms IS NULL OR runtime_ms >= 0);
ALTER TABLE catalog_items ADD COLUMN certification TEXT;
ALTER TABLE catalog_items ADD COLUMN community_rating REAL;
ALTER TABLE catalog_items ADD COLUMN vote_count INTEGER NOT NULL DEFAULT 0 CHECK (vote_count >= 0);
ALTER TABLE catalog_items ADD COLUMN genres_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE catalog_items ADD COLUMN countries_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE catalog_items ADD COLUMN studios_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE catalog_items ADD COLUMN credits_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE catalog_items ADD COLUMN external_ids_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE catalog_items ADD COLUMN metadata_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (metadata_status IN ('pending', 'refreshing', 'ready', 'needs_review', 'failed'));
ALTER TABLE catalog_items ADD COLUMN metadata_revision INTEGER NOT NULL DEFAULT 1 CHECK (metadata_revision > 0);
ALTER TABLE catalog_items ADD COLUMN metadata_error_code TEXT;
ALTER TABLE catalog_items ADD COLUMN metadata_error_message TEXT;
ALTER TABLE catalog_items ADD COLUMN metadata_updated_at_ms INTEGER;
ALTER TABLE catalog_items ADD COLUMN provider TEXT;
ALTER TABLE catalog_items ADD COLUMN provider_item_id TEXT;
ALTER TABLE catalog_items ADD COLUMN identity_locked INTEGER NOT NULL DEFAULT 0 CHECK (identity_locked IN (0, 1));

CREATE UNIQUE INDEX idx_catalog_provider_identity
ON catalog_items(source_id, kind, provider, provider_item_id)
WHERE provider IS NOT NULL AND provider_item_id IS NOT NULL;

-- 保存所有可搜索标题，资料刷新时按 Provider 快照重建。
CREATE TABLE catalog_titles (
    catalog_item_id TEXT NOT NULL,
    title TEXT NOT NULL,
    normalized_title TEXT NOT NULL,
    language TEXT NOT NULL DEFAULT '',
    title_type TEXT NOT NULL CHECK (title_type IN ('display', 'original', 'alternative')),
    created_at_ms INTEGER NOT NULL,
    PRIMARY KEY(catalog_item_id, normalized_title, language, title_type),
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

CREATE INDEX idx_catalog_titles_normalized ON catalog_titles(normalized_title, catalog_item_id);

-- 暂存低置信搜索结果，前端后续只消费 Luma 统一候选结构。
CREATE TABLE catalog_match_candidates (
    id TEXT PRIMARY KEY,
    catalog_item_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_item_id TEXT NOT NULL,
    title TEXT NOT NULL,
    original_title TEXT NOT NULL DEFAULT '',
    year INTEGER,
    overview TEXT NOT NULL DEFAULT '',
    score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
    reasons_json TEXT NOT NULL DEFAULT '[]',
    poster_ref TEXT,
    created_at_ms INTEGER NOT NULL,
    UNIQUE(catalog_item_id, provider, provider_item_id),
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

-- 每个作品只有一个持久化刮削任务；刷新通过 upsert 重新置为 pending。
CREATE TABLE catalog_scrape_jobs (
    catalog_item_id TEXT PRIMARY KEY,
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    available_at_ms INTEGER NOT NULL,
    locked_at_ms INTEGER,
    locked_by TEXT,
    error_code TEXT,
    error_message TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    finished_at_ms INTEGER,
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

CREATE INDEX idx_catalog_scrape_runnable
ON catalog_scrape_jobs(status, available_at_ms, created_at_ms, catalog_item_id);

-- NFO 作为只读侧车单独索引，不进入 media_items 或媒体处理队列。
CREATE TABLE catalog_sidecars (
    source_id TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL CHECK (file_size >= 0),
    file_modified_at_ms INTEGER NOT NULL,
    last_seen_scan_id TEXT,
    status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('ready', 'missing')),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY(source_id, relative_path),
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE CASCADE
);

CREATE INDEX idx_catalog_sidecars_source_status
ON catalog_sidecars(source_id, status, relative_path);

-- 海报和背景图只保存 Provider 不透明引用；图片内容缓存在 storage.cache_dir。
CREATE TABLE catalog_artwork (
    id TEXT PRIMARY KEY,
    catalog_item_id TEXT NOT NULL,
    artwork_type TEXT NOT NULL CHECK (artwork_type IN ('poster', 'backdrop')),
    provider TEXT NOT NULL,
    opaque_key TEXT NOT NULL,
    storage_key TEXT,
    mime_type TEXT,
    content_sha256 TEXT,
    status TEXT NOT NULL DEFAULT 'remote' CHECK (status IN ('remote', 'ready', 'failed')),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(catalog_item_id, artwork_type),
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

-- 现有未人工锁定作品在升级后自动进入刮削队列。
INSERT INTO catalog_scrape_jobs(
    catalog_item_id, status, available_at_ms, created_at_ms, updated_at_ms
)
SELECT id, 'pending', updated_at_ms, updated_at_ms, updated_at_ms
FROM catalog_items
WHERE locked = 0;
