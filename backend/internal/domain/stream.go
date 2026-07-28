package domain

import (
	"io"
	"time"
)

// StreamLocation 保存仅供服务端定位原始媒体使用的内部字段。
type StreamLocation struct {
	// ID 是媒体唯一标识。
	ID string
	// Filename 是媒体文件名。
	Filename string
	// MediaType 是媒体类型。
	MediaType string
	// MIMEType 是媒体 MIME 类型。
	MIMEType string
	// AudioCodec 是音频编码格式名称。
	AudioCodec string
	// SourceType 是媒体来源类型。
	SourceType string
	// RootPath 是媒体来源根路径。
	RootPath string
	// RelativePath 是媒体相对来源根的路径。
	RelativePath string
}

// StreamReader 是 http.ServeContent 所需的可定位只读内容。
type StreamReader interface {
	io.Reader
	io.Seeker
	io.Closer
}

// OpenedContent 表示已通过安全检查打开的原始文件快照。
type OpenedContent struct {
	// Reader 是已打开的可定位只读内容。
	Reader StreamReader
	// Size 是打开瞬间的文件字节数快照。
	Size int64
	// ModifiedAt 是打开瞬间的修改时间快照。
	ModifiedAt time.Time
}

// StreamContent 表示已经安全打开并可交给 HTTP 层的原始媒体。
type StreamContent struct {
	// Name 是提供给 HTTP 层的内容名称。
	Name string
	// MIMEType 是内容 MIME 类型。
	MIMEType string
	// ETag 是由打开瞬间 size 与 mtime 生成的弱校验标识。
	ETag string
	// Size 是打开瞬间的内容字节数快照，与 Reader/ETag 一致。
	Size int64
	// ModifiedAt 是打开瞬间的修改时间快照。
	ModifiedAt time.Time
	// Reader 是已打开的可定位只读内容，Seek/Read 受 Size 快照约束。
	Reader StreamReader
}
