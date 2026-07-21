package migrations

import _ "embed"

// Initial 保存嵌入服务端二进制的 001 初始数据库迁移。
//
//go:embed 001_initial.sql
var Initial string

// Stage2Scan 保存嵌入服务端二进制的 002 本地扫描索引迁移。
//
//go:embed 002_stage2_scan.sql
var Stage2Scan string

// JobsInterrupted 保存嵌入服务端二进制的 003 jobs 中断状态对齐迁移。
//
//go:embed 003_jobs_interrupted.sql
var JobsInterrupted string

// Stage3Processing 保存嵌入服务端二进制的 004 媒体处理任务迁移。
//
//go:embed 004_stage3_processing.sql
var Stage3Processing string

// Stage4MediaAPI 保存嵌入服务端二进制的 005 媒体 API 查询索引迁移。
//
//go:embed 005_stage4_media_api.sql
var Stage4MediaAPI string

// MediaAssetContentHash 保存嵌入服务端二进制的 006 缩略图内容哈希迁移。
//
//go:embed 006_media_asset_content_hash.sql
var MediaAssetContentHash string

// Stage6UserData 保存嵌入服务端二进制的 007 用户数据迁移。
//
//go:embed 007_stage6_user_data.sql
var Stage6UserData string

// CardThumbnailJobs 保存嵌入服务端二进制的 008 卡片缩略图任务迁移。
//
//go:embed 008_card_thumbnail_jobs.sql
var CardThumbnailJobs string
