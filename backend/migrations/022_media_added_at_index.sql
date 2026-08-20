-- 日期排序改用磁盘创建时间，未知时回退首次进库时间。
CREATE INDEX idx_media_added_at
ON media_items(COALESCE(file_created_at_ms, discovered_at_ms) DESC, id DESC);

CREATE INDEX idx_media_type_added_at
ON media_items(media_type, COALESCE(file_created_at_ms, discovered_at_ms) DESC, id DESC);
