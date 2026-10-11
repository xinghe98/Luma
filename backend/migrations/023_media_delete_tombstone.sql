-- 图片永久删除墓碑：阻止删除发生前已启动的扫描用旧文件快照复活媒体索引。
-- 判定只看删除时刻与扫描任务创建水位：scan_jobs.created_at_ms 早于
-- deleted_at_ms 的扫描对该路径的 reconcile 一律拒绝；删除后启动的新扫描
-- 即使看到完全相同的 mtime/size 也正常入库并顺带清掉墓碑。
CREATE TABLE media_delete_tombstones (
    -- 媒体源标识。
    source_id TEXT NOT NULL,
    -- 被删文件相对路径（与 media_items.relative_path 同一规范化规则）。
    relative_path TEXT NOT NULL,
    -- 被删媒体条目标识，仅用于审计与排查。
    media_id TEXT NOT NULL,
    -- 删除完成时间戳（毫秒），作为判定过期扫描快照的水位。
    deleted_at_ms INTEGER NOT NULL,
    PRIMARY KEY(source_id, relative_path),
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE CASCADE
);
