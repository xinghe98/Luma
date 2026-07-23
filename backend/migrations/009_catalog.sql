-- 媒体源在创建时声明其面向的内容类型；旧来源保持个人媒体语义。
ALTER TABLE sources
ADD COLUMN library_kind TEXT NOT NULL DEFAULT 'personal'
CHECK (library_kind IN ('personal', 'photos', 'movies', 'tv'));

-- 作品层独立于文件层。作品删除时只删除索引关系，不影响原始媒体。
CREATE TABLE catalog_items (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('movie', 'series')),
    title TEXT NOT NULL,
    sort_title TEXT NOT NULL,
    year INTEGER CHECK (year IS NULL OR year BETWEEN 1800 AND 3000),
    metadata_origin TEXT NOT NULL DEFAULT 'filename'
        CHECK (metadata_origin IN ('filename', 'nfo', 'provider', 'user')),
    match_status TEXT NOT NULL DEFAULT 'matched'
        CHECK (match_status IN ('matched', 'needs_review')),
    locked INTEGER NOT NULL DEFAULT 0 CHECK (locked IN (0, 1)),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(source_id, kind, sort_title, year),
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE CASCADE
);

CREATE TABLE catalog_seasons (
    id TEXT PRIMARY KEY,
    catalog_item_id TEXT NOT NULL,
    season_number INTEGER NOT NULL CHECK (season_number >= 0),
    title TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(catalog_item_id, season_number),
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE
);

CREATE TABLE catalog_episodes (
    id TEXT PRIMARY KEY,
    season_id TEXT NOT NULL,
    episode_number INTEGER NOT NULL CHECK (episode_number > 0),
    title TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(season_id, episode_number),
    FOREIGN KEY(season_id) REFERENCES catalog_seasons(id) ON DELETE CASCADE
);

-- 一个文件在首版只关联一个电影或一集；复杂多集文件进入待整理队列。
CREATE TABLE catalog_media_links (
    media_id TEXT PRIMARY KEY,
    catalog_item_id TEXT,
    season_id TEXT,
    episode_id TEXT,
    match_status TEXT NOT NULL CHECK (match_status IN ('matched', 'needs_review', 'ignored')),
    confidence INTEGER NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 100),
    rule_version INTEGER NOT NULL DEFAULT 1 CHECK (rule_version > 0),
    locked INTEGER NOT NULL DEFAULT 0 CHECK (locked IN (0, 1)),
    media_updated_at_ms INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE,
    FOREIGN KEY(catalog_item_id) REFERENCES catalog_items(id) ON DELETE CASCADE,
    FOREIGN KEY(season_id) REFERENCES catalog_seasons(id) ON DELETE CASCADE,
    FOREIGN KEY(episode_id) REFERENCES catalog_episodes(id) ON DELETE CASCADE
);

CREATE INDEX idx_catalog_items_source_kind
ON catalog_items(source_id, kind, sort_title, id);

CREATE INDEX idx_catalog_links_item
ON catalog_media_links(catalog_item_id, match_status, media_id);

CREATE INDEX idx_catalog_episodes_season
ON catalog_episodes(season_id, episode_number, id);
