package domain

import "time"

const (
	// JobTypeProbe 表示提取媒体元数据的持久化任务，对应 jobs.job_type = probe_media。
	JobTypeProbe = "probe_media"
	// JobTypeThumbnail 表示生成默认缩略图的持久化任务，对应 jobs.job_type = generate_thumbnail。
	JobTypeThumbnail = "generate_thumbnail"
	// JobTypeCardThumbnail 表示为已就绪媒体补齐卡片裁剪缩略图。
	JobTypeCardThumbnail = "generate_card_thumbnail"
)

// ProcessingJob 是可重试的持久化媒体处理任务，对应 jobs 表中的 probe/thumbnail 行。
type ProcessingJob struct {
	// ID 对应 jobs.id，任务主键。
	ID string
	// Type 对应 jobs.job_type，取值为 probe_media 或 generate_thumbnail。
	Type string
	// MediaID 对应 jobs.entity_id，指向 media_items.id。
	MediaID string
	// Attempt 对应本次领取后的 jobs.attempt_count（已含当前这次执行）。
	Attempt int
	// WorkerID 是领取该次 attempt 的 worker 标识，用作完成/失败时的租约围栏。
	WorkerID string
	// MaxAttempts 对应 jobs.max_attempts，默认 2（失败后最多再试 1 次）。
	MaxAttempts int
}

// MediaInput 是处理任务读取的媒体定位与版本快照，来自 media_items JOIN sources。
type MediaInput struct {
	// ID 对应 media_items.id。
	ID string
	// SourceID 对应 media_items.source_id。
	SourceID string
	// RootPath 对应 sources.root_path，仅服务端内部拼文件路径，不对外暴露。
	RootPath string
	// RelativePath 对应 media_items.relative_path，相对媒体源根的安全路径。
	RelativePath string
	// MediaType 对应 media_items.media_type，取值为 video 或 image。
	MediaType string
	// FileSize 对应 media_items.file_size，用于完成时的版本校验。
	FileSize int64
	// ModifiedAtMS 对应 media_items.file_modified_at_ms，用于完成时的版本校验。
	ModifiedAtMS int64
	// DurationMS 对应 media_items.duration_ms（COALESCE 为 0），供缩略图 seek；未知时为 0。
	DurationMS int64
}

// ProbeResult 是 ffprobe 提取并写入 media_items 探测列的元数据。
type ProbeResult struct {
	// Title 写入 media_items.detected_title，来自 format tags 的 title。
	Title string
	// MIMEType 写入 media_items.mime_type，优先由扩展名推断。
	MIMEType string
	// VideoCodec 写入 media_items.video_codec，主视频流 codec_name。
	VideoCodec string
	// AudioCodec 写入 media_items.audio_codec，首条音轨 codec_name。
	AudioCodec string
	// Container 写入 media_items.container，对应 format.format_name。
	Container string
	// DurationMS 写入 media_items.duration_ms，毫秒时长；未探测到时为 nil。
	DurationMS *int64
	// Bitrate 写入 media_items.bitrate，平均码率（bps）；未探测到时为 nil。
	Bitrate *int64
	// Width 写入 media_items.width，主视频流像素宽；未探测到时为 nil。
	Width *int
	// Height 写入 media_items.height，主视频流像素高；未探测到时为 nil。
	Height *int
	// FrameRateNum 写入 media_items.frame_rate_num，帧率分子。
	FrameRateNum *int
	// FrameRateDen 写入 media_items.frame_rate_den，帧率分母。
	FrameRateDen *int
	// Orientation 写入 media_items.orientation，旋转角度（度）；无则 nil。
	Orientation *int
	// AudioTrackCount 写入 media_items.audio_track_count，音频流数量。
	AudioTrackCount int
	// CapturedAt 写入 media_items.captured_at_ms，内嵌 creation_time；无则 nil。
	CapturedAt *time.Time
	// RawJSON 写入 media_items.probe_data，完整 ffprobe JSON 原文。
	RawJSON []byte
	// Version 写入 media_items.probe_version，解析规则版本，便于日后重处理。
	Version int
}

// ThumbnailResult 是已原子落盘的默认缩略图信息，对应 media_assets 默认封面行。
type ThumbnailResult struct {
	// StorageKey 对应 media_assets.storage_key，相对数据目录的键（如 thumbnails/{id}/cover-640-v1.jpg）。
	StorageKey string
	// MIMEType 对应 media_assets.mime_type，当前固定为 image/jpeg。
	MIMEType string
	// ContentSHA256 对应 media_assets.content_sha256，文件内容十六进制 SHA-256。
	ContentSHA256 string
	// Width 对应 media_assets.width，生成文件实际像素宽。
	Width int
	// Height 对应 media_assets.height，生成文件实际像素高。
	Height int
	// Card 是新媒体默认缩略图生成后直接派生的卡片变体；旧调用可为空。
	Card *ThumbnailResult
}
