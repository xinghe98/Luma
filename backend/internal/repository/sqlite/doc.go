// Package sqlite 提供 SQLite 连接、迁移与各业务 Repository 实现。
// 扫描相关实现按职责拆分：scan_jobs、scan_reconcile、scan_identity、scan_processing；
// 媒体处理实现按 processing、processing_complete、processing_recovery 拆分。
package sqlite
