-- 图片按文件类型归入图片库；来源用途仅用于视频分类。
UPDATE sources
SET library_kind = 'personal'
WHERE library_kind = 'photos';
