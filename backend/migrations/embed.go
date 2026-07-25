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

// Catalog 保存作品、季、单集与文件映射结构。
//
//go:embed 009_catalog.sql
var Catalog string

// AccessControl 保存多用户 Token 与媒体源授权结构。
//
//go:embed 010_access_control.sql
var AccessControl string

// ImageLibrary 将旧版仅图片媒体源迁移为个人视频来源。
//
//go:embed 011_image_library.sql
var ImageLibrary string

//go:embed 012_access_idempotency.sql
var AccessIdempotency string

// AccountSessions 将旧令牌认证迁移为用户名密码登录后的会话。
//
//go:embed 015_account_sessions.sql
var AccountSessions string

// ScanMetadataRuns 保存扫描后影视资料任务的运行记录。
//
//go:embed 016_scan_metadata_runs.sql
var ScanMetadataRuns string

// CatalogMetadata 保存可扩展 Provider 刮削、候选与丰富作品资料结构。
//
//go:embed 013_catalog_metadata.sql
var CatalogMetadata string

// CatalogDetail 保存作品版本、演职员头像与作品级收藏结构。
//
//go:embed 014_catalog_detail.sql
var CatalogDetail string
