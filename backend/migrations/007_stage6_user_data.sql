-- 阶段 6 乐观并发版本与用户数据查询索引。
ALTER TABLE media_user_data
ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0);

ALTER TABLE tags
ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0);

-- 旧库允许只建立标签关系；为这些关系补齐 revision 基线。
INSERT INTO media_user_data(
    user_id, media_id, created_at_ms, updated_at_ms, revision
)
SELECT mt.user_id, mt.media_id, MIN(mt.created_at_ms), MAX(mt.created_at_ms), 1
FROM media_tags mt
LEFT JOIN media_user_data u ON u.user_id = mt.user_id AND u.media_id = mt.media_id
WHERE u.media_id IS NULL
GROUP BY mt.user_id, mt.media_id;

CREATE INDEX idx_media_tags_user_tag_media
ON media_tags(user_id, tag_id, media_id);

CREATE INDEX idx_user_data_continue_watching
ON media_user_data(user_id, last_played_at_ms DESC, media_id DESC)
WHERE completed = 0 AND progress_ms > 0 AND last_played_at_ms IS NOT NULL;
