-- 媒体源表：保存受白名单约束的本地目录及其扫描状态。
CREATE TABLE sources (
    -- 媒体源唯一标识。
    id TEXT PRIMARY KEY,
    -- 媒体源显示名称。
    name TEXT NOT NULL,
    -- 媒体源类型。
    source_type TEXT NOT NULL,
    -- 本地媒体源根目录路径。
    root_path TEXT,
    -- 媒体源配置版本号。
    config_version INTEGER NOT NULL DEFAULT 1,
    -- 媒体源配置 JSON。
    config_json TEXT NOT NULL DEFAULT '{}',
    -- 媒体源凭据引用。
    credential_ref TEXT,
    -- 媒体源是否启用。
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    -- 媒体源当前状态。
    status TEXT NOT NULL DEFAULT 'online' CHECK (status IN ('online', 'offline', 'degraded', 'disabled')),
    -- 最近一次扫描任务标识。
    last_scan_id TEXT,
    -- 最近一次发现媒体源的时间戳（毫秒）。
    last_seen_at_ms INTEGER,
    -- 媒体源软删除时间戳（毫秒）。
    deleted_at_ms INTEGER,
    -- 媒体源创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 媒体源更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    CHECK ((source_type = 'local' AND root_path IS NOT NULL) OR source_type <> 'local')
);

-- 用户表：V1 使用固定本地用户，同时为后续多用户预留主键。
CREATE TABLE users (
    -- 用户唯一标识。
    id TEXT PRIMARY KEY,
    -- 用户显示名称。
    name TEXT NOT NULL,
    -- 用户创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 用户更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL
);

-- 媒体索引表：只保存文件索引和探测结果，不修改原始媒体。
CREATE TABLE media_items (
    -- 媒体条目唯一标识。
    id TEXT PRIMARY KEY,
    -- 所属媒体源标识。
    source_id TEXT NOT NULL,
    -- 媒体文件相对路径。
    relative_path TEXT NOT NULL,
    -- 媒体文件名。
    filename TEXT NOT NULL,
    -- 自动识别的媒体标题。
    detected_title TEXT,
    -- 媒体类型。
    media_type TEXT NOT NULL CHECK (media_type IN ('video', 'image')),
    -- 媒体 MIME 类型。
    mime_type TEXT,
    -- 文件大小（字节）。
    file_size INTEGER NOT NULL CHECK (file_size >= 0),
    -- 文件修改时间戳（毫秒）。
    file_modified_at_ms INTEGER NOT NULL,
    -- 文件系统文件标识。
    file_id TEXT,
    -- 文件快速哈希值。
    quick_hash TEXT,
    -- 媒体时长（毫秒）。
    duration_ms INTEGER,
    -- 媒体宽度（像素）。
    width INTEGER,
    -- 媒体高度（像素）。
    height INTEGER,
    -- 视频编码格式。
    video_codec TEXT,
    -- 音频编码格式。
    audio_codec TEXT,
    -- 媒体容器格式。
    container TEXT,
    -- 媒体码率。
    bitrate INTEGER,
    -- 帧率分子。
    frame_rate_num INTEGER,
    -- 帧率分母。
    frame_rate_den INTEGER,
    -- 音轨数量。
    audio_track_count INTEGER,
    -- 媒体方向信息。
    orientation INTEGER,
    -- 媒体拍摄时间戳（毫秒）。
    captured_at_ms INTEGER,
    -- 媒体探测原始数据。
    probe_data TEXT,
    -- 媒体探测数据版本号。
    probe_version INTEGER NOT NULL DEFAULT 1,
    -- 媒体处理状态。
    status TEXT NOT NULL CHECK (status IN ('discovered', 'probing', 'thumbnailing', 'ready', 'failed', 'missing')),
    -- 媒体处理错误码。
    error_code TEXT,
    -- 媒体处理错误信息。
    error_message TEXT,
    -- 最近发现该媒体的扫描标识。
    last_seen_scan_id TEXT,
    -- 媒体缺失时间戳（毫秒）。
    missing_at_ms INTEGER,
    -- 媒体发现时间戳（毫秒）。
    discovered_at_ms INTEGER NOT NULL,
    -- 媒体完成索引时间戳（毫秒）。
    indexed_at_ms INTEGER,
    -- 媒体条目创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 媒体条目更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(source_id, relative_path),
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE RESTRICT,
    CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CHECK (width IS NULL OR width > 0),
    CHECK (height IS NULL OR height > 0),
    CHECK (frame_rate_den IS NULL OR frame_rate_den > 0)
);

-- 媒体资产表：保存缩略图等衍生文件的相对存储键。
CREATE TABLE media_assets (
    -- 媒体资产唯一标识。
    id TEXT PRIMARY KEY,
    -- 所属媒体条目标识。
    media_id TEXT NOT NULL,
    -- 媒体资产类型。
    asset_type TEXT NOT NULL CHECK (asset_type IN ('thumbnail', 'custom_cover', 'sprite', 'preview')),
    -- 媒体资产变体名称。
    variant TEXT NOT NULL DEFAULT 'default',
    -- 媒体资产存储键。
    storage_key TEXT NOT NULL,
    -- 媒体资产 MIME 类型。
    mime_type TEXT,
    -- 媒体资产宽度（像素）。
    width INTEGER,
    -- 媒体资产高度（像素）。
    height INTEGER,
    -- 媒体资产生成状态。
    status TEXT NOT NULL CHECK (status IN ('pending', 'ready', 'failed')),
    -- 媒体资产生成器版本号。
    generator_version INTEGER NOT NULL DEFAULT 1,
    -- 媒体资产生成错误信息。
    error_message TEXT,
    -- 媒体资产创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 媒体资产更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(media_id, asset_type, variant, generator_version),
    UNIQUE(storage_key),
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE
);

-- 用户媒体数据表：保存标题、收藏、笔记、评分和播放进度。
CREATE TABLE media_user_data (
    -- 用户唯一标识。
    user_id TEXT NOT NULL,
    -- 媒体条目唯一标识。
    media_id TEXT NOT NULL,
    -- 用户自定义媒体标题。
    custom_title TEXT,
    -- 用户是否收藏该媒体。
    favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1)),
    -- 用户媒体笔记。
    notes TEXT,
    -- 用户媒体评分。
    rating INTEGER CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
    -- 用户播放进度（毫秒）。
    progress_ms INTEGER NOT NULL DEFAULT 0 CHECK (progress_ms >= 0),
    -- 用户是否已播放完成。
    completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
    -- 用户最近播放时间戳（毫秒）。
    last_played_at_ms INTEGER,
    -- 用户媒体数据创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 用户媒体数据更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY(user_id, media_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE
);

-- 标签表：使用规范化名称保证同一用户下的唯一性。
CREATE TABLE tags (
    -- 标签唯一标识。
    id TEXT PRIMARY KEY,
    -- 所属用户标识。
    user_id TEXT NOT NULL,
    -- 标签显示名称。
    name TEXT NOT NULL,
    -- 标签规范化名称。
    normalized_name TEXT NOT NULL,
    -- 标签创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 标签更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(user_id, normalized_name),
    UNIQUE(id, user_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- 媒体标签关系表：通过复合外键保证标签属于当前用户。
CREATE TABLE media_tags (
    -- 用户唯一标识。
    user_id TEXT NOT NULL,
    -- 媒体条目唯一标识。
    media_id TEXT NOT NULL,
    -- 标签唯一标识。
    tag_id TEXT NOT NULL,
    -- 媒体标签关系创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    PRIMARY KEY(user_id, media_id, tag_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE,
    FOREIGN KEY(tag_id, user_id) REFERENCES tags(id, user_id) ON DELETE CASCADE
);

-- 通用任务表：作为后台任务调度状态的事实来源。
CREATE TABLE jobs (
    -- 任务唯一标识。
    id TEXT PRIMARY KEY,
    -- 任务类型。
    job_type TEXT NOT NULL CHECK (job_type IN ('scan_source', 'probe_media', 'generate_thumbnail', 'cleanup_assets')),
    -- 任务关联实体标识。
    entity_id TEXT NOT NULL,
    -- 任务载荷 JSON。
    payload_json TEXT NOT NULL DEFAULT '{}',
    -- 任务执行状态。
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    -- 任务已尝试次数。
    attempt_count INTEGER NOT NULL DEFAULT 0,
    -- 任务最大尝试次数。
    max_attempts INTEGER NOT NULL DEFAULT 2,
    -- 任务可执行时间戳（毫秒）。
    available_at_ms INTEGER NOT NULL,
    -- 任务锁定时间戳（毫秒）。
    locked_at_ms INTEGER,
    -- 任务锁定者标识。
    locked_by TEXT,
    -- 任务错误码。
    error_code TEXT,
    -- 任务错误信息。
    error_message TEXT,
    -- 任务创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 任务更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    -- 任务完成时间戳（毫秒）。
    finished_at_ms INTEGER,
    CHECK (attempt_count >= 0),
    CHECK (max_attempts > 0)
);

-- 扫描任务扩展表：记录媒体源扫描阶段和统计信息。
CREATE TABLE scan_jobs (
    -- 扫描任务唯一标识。
    id TEXT PRIMARY KEY,
    -- 扫描媒体源标识。
    source_id TEXT NOT NULL,
    -- 扫描任务状态。
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'interrupted')),
    -- 扫描任务当前阶段。
    phase TEXT,
    -- 扫描发现的媒体数量。
    discovered_count INTEGER NOT NULL DEFAULT 0,
    -- 扫描已处理的媒体数量。
    processed_count INTEGER NOT NULL DEFAULT 0,
    -- 扫描处理失败的媒体数量。
    failed_count INTEGER NOT NULL DEFAULT 0,
    -- 扫描开始时间戳（毫秒）。
    started_at_ms INTEGER,
    -- 扫描结束时间戳（毫秒）。
    finished_at_ms INTEGER,
    -- 扫描任务错误码。
    error_code TEXT,
    -- 扫描任务错误信息。
    error_message TEXT,
    -- 扫描任务创建时间戳（毫秒）。
    created_at_ms INTEGER NOT NULL,
    -- 扫描任务更新时间戳（毫秒）。
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY(id) REFERENCES jobs(id) ON DELETE CASCADE,
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE RESTRICT
);

-- 活跃任务唯一索引：同一实体的同类任务不得重复执行。
CREATE UNIQUE INDEX idx_jobs_active_entity ON jobs(job_type, entity_id) WHERE status IN ('pending', 'running');

-- 查询索引：覆盖媒体列表、资产、用户数据、扫描历史和任务领取场景。
CREATE INDEX idx_media_source_status ON media_items(source_id, status);
CREATE INDEX idx_media_type_discovered ON media_items(media_type, discovered_at_ms DESC, id DESC);
CREATE INDEX idx_media_last_seen_scan ON media_items(source_id, last_seen_scan_id);
CREATE INDEX idx_media_filename ON media_items(filename);
CREATE INDEX idx_media_assets_media_type ON media_assets(media_id, asset_type, status);
CREATE INDEX idx_user_data_favorite ON media_user_data(user_id, favorite, updated_at_ms DESC);
CREATE INDEX idx_user_data_last_played ON media_user_data(user_id, last_played_at_ms DESC);
CREATE INDEX idx_scan_jobs_source_created ON scan_jobs(source_id, created_at_ms DESC);
CREATE INDEX idx_jobs_runnable ON jobs(status, available_at_ms, created_at_ms);
