package storage

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ErrContentNotFound 表示原始内容不存在或未通过安全路径检查。
var ErrContentNotFound = domain.ErrContentNotFound

// ReadSeekCloser 是 domain.StreamReader 的存储层别名。
type ReadSeekCloser = domain.StreamReader

// FileEntry 表示媒体源遍历得到的普通文件信息。
type FileEntry struct {
	// RelativePath 是相对于媒体源根目录的规范路径。
	RelativePath string
	// Filename 是保留原始大小写的文件名。
	Filename string
	// Size 是文件字节数。
	Size int64
	// ModifiedAt 是文件最后修改时间。
	ModifiedAt time.Time
	// CreatedAt 是文件创建时间；文件系统未提供时为 nil。
	CreatedAt *time.Time
	// FileID 是平台可选的稳定文件身份。
	FileID string
}

// SourceHealth 表示媒体源当前是否可读。
type SourceHealth struct {
	// Online 表示根目录当前可访问。
	Online bool
	// CheckedAt 是本次检查时间。
	CheckedAt time.Time
}

// MediaSource 定义 Scanner 访问媒体存储所需的只读能力。
type MediaSource interface {
	// Walk 遍历全部普通文件，任一目录错误都会终止整个扫描。
	Walk(context.Context, func(FileEntry) error) error
	// Open 以只读方式打开安全相对路径。
	Open(context.Context, string) (ReadSeekCloser, error)
	// Health 检查媒体源根目录是否可访问。
	Health(context.Context) (SourceHealth, error)
}

// FileIdentifier 定义本地媒体源获取平台文件身份所需的能力。
type FileIdentifier interface {
	// Identify 返回文件系统提供的稳定身份，无法提供时返回错误。
	Identify(string) (string, error)
}

// Clock 定义存储适配器记录健康检查时间所需的能力。
type Clock interface {
	// Now 返回当前 UTC 时间。
	Now() time.Time
}

// SourceFactory 根据领域媒体源创建具体存储适配器。
type SourceFactory interface {
	// Local 创建本地目录媒体源。
	Local(string) (MediaSource, error)
}
