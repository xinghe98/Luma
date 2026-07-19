-- 阶段 4 修复：缩略图内容哈希，支持 304 短路径而不读盘。
ALTER TABLE media_assets ADD COLUMN content_sha256 TEXT;
