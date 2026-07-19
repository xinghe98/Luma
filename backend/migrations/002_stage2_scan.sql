-- 媒体源根目录唯一索引：同一路径只能对应一个未清除的媒体源。
CREATE UNIQUE INDEX idx_sources_active_root
ON sources(source_type, root_path)
WHERE deleted_at_ms IS NULL;

-- 文件身份索引：加速同一媒体源内的改名和移动识别。
CREATE INDEX idx_media_file_id
ON media_items(source_id, file_id)
WHERE file_id IS NOT NULL;

-- 快速指纹索引：在文件 ID 不可用时辅助识别改名和移动。
CREATE INDEX idx_media_quick_hash
ON media_items(source_id, file_size, quick_hash)
WHERE quick_hash IS NOT NULL;
