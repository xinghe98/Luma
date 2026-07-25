-- 作品详情补充版本、演职员头像与跨版本收藏；图片仍只缓存到 Luma 数据目录。
CREATE TABLE catalog_credit_artwork (
    id TEXT PRIMARY KEY,
    catalog_item_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_person_id TEXT NOT NULL,
    opaque_key TEXT NOT NULL,
    storage_key TEXT,
    mime_type TEXT,
    content_sha256 TEXT,
    status TEXT NOT NULL DEFAULT 'remote' CHECK (status IN ('remote', 'ready', 'failed')),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(catalog_item_id, provider, provider_person_id),
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

CREATE INDEX idx_catalog_credit_artwork_item
ON catalog_credit_artwork(catalog_item_id, provider_person_id);

-- 收藏属于作品而非某个编码版本，切换 4K/1080p 时保持一致。
CREATE TABLE catalog_user_data (
    user_id TEXT NOT NULL,
    catalog_item_id TEXT NOT NULL,
    favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1)),
    revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY(user_id, catalog_item_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

CREATE INDEX idx_catalog_user_data_favorite
ON catalog_user_data(user_id, favorite, updated_at_ms DESC);
