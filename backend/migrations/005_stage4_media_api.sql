-- 阶段 4 媒体 API 的稳定 keyset 排序索引。
CREATE INDEX idx_media_discovered ON media_items(discovered_at_ms DESC, id DESC);

DROP INDEX IF EXISTS idx_media_filename;
CREATE INDEX idx_media_filename ON media_items(filename COLLATE NOCASE, id);

CREATE INDEX idx_media_duration ON media_items((duration_ms IS NULL), duration_ms, id);
CREATE INDEX idx_media_file_size ON media_items(file_size, id);
