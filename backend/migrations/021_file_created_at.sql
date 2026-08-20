-- 记录本地磁盘文件创建时间，供媒体卡片日期展示。
ALTER TABLE media_items ADD COLUMN file_created_at_ms INTEGER;
