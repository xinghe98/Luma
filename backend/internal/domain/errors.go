package domain

import "errors"

var (
	// ErrInvalidRequest 表示业务输入未通过显式校验。
	ErrInvalidRequest = errors.New("invalid request")
	// ErrSourceNotFound 表示指定媒体源不存在或已被软删除。
	ErrSourceNotFound = errors.New("source not found")
	// ErrSourceConflict 表示媒体源名称或根目录与现有记录冲突。
	ErrSourceConflict = errors.New("source conflicts with existing source")
	// ErrForbiddenPath 表示媒体源目录不在安全白名单中。
	ErrForbiddenPath = errors.New("source path is forbidden")
	// ErrSourceOffline 表示媒体源当前不可访问。
	ErrSourceOffline = errors.New("source is offline")
	// ErrScanNotFound 表示指定扫描任务不存在。
	ErrScanNotFound = errors.New("scan job not found")
	// ErrScanAlreadyRunning 表示媒体源已有待执行或运行中的扫描任务。
	ErrScanAlreadyRunning = errors.New("scan already running")
	// ErrNoPendingScan 表示当前没有可领取的扫描任务。
	ErrNoPendingScan = errors.New("no pending scan job")
	// ErrNoPendingJob 表示当前没有指定类型的媒体处理任务。
	ErrNoPendingJob = errors.New("no pending processing job")
	// ErrMediaNotFound 表示媒体索引不存在或来源已失效。
	ErrMediaNotFound = errors.New("media not found")
	// ErrContentNotFound 表示原始媒体文件不存在或未通过安全路径检查。
	ErrContentNotFound = errors.New("media content not found")
	// ErrThumbnailNotFound 表示媒体当前没有可读取的默认缩略图。
	ErrThumbnailNotFound = errors.New("thumbnail not found")
	// ErrThumbnailTooLarge 表示缩略图文件超过服务端允许的最大读取大小。
	ErrThumbnailTooLarge = errors.New("thumbnail too large")
	// ErrTagNotFound 表示标签不存在或不属于当前用户。
	ErrTagNotFound = errors.New("tag not found")
	// ErrTagConflict 表示规范化后的标签名称已存在。
	ErrTagConflict = errors.New("tag conflicts with existing tag")
	// ErrRevisionConflict 表示客户端基于过期版本写入。
	ErrRevisionConflict = errors.New("revision conflict")
	// ErrMediaDurationUnavailable 表示媒体尚无可靠播放时长。
	ErrMediaDurationUnavailable = errors.New("media duration unavailable")
	// ErrMediaNotPlayable 表示目标媒体不支持播放进度。
	ErrMediaNotPlayable = errors.New("media not playable")
	// ErrCatalogNotFound 表示作品或待整理文件不存在。
	ErrCatalogNotFound = errors.New("catalog item not found")
	// ErrUnauthorized 表示凭据无效、过期、撤销或所属用户被禁用。
	ErrUnauthorized = errors.New("unauthorized")
	// ErrForbidden 表示身份有效但没有执行管理操作的权限。
	ErrForbidden = errors.New("forbidden")
	// ErrUserNotFound 表示成员不存在。
	ErrUserNotFound = errors.New("user not found")
	// ErrTokenNotFound 表示成员令牌不存在。
	ErrTokenNotFound = errors.New("token not found")
	// ErrIdempotencySecretUnavailable 表示令牌已创建，但服务重启后无法安全重放一次性明文。
	ErrIdempotencySecretUnavailable = errors.New("idempotency secret unavailable")
)
