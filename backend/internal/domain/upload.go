// 本文件职责：图片上传的领域输入/结果与契约错误。
// 服务端只以流式方式消费上传正文，不整块载入内存。

package domain

import (
	"errors"
	"io"
)

// MaxUploadImageBytes 是 POST /api/v1/sources/{id}/images 接受的最大单文件字节数（64 MiB）。
const MaxUploadImageBytes int64 = 64 << 20

var (
	// ErrUploadTooLarge 表示上传图片超过 MaxUploadImageBytes。
	ErrUploadTooLarge = errors.New("upload image too large")
	// ErrUploadUnsupportedImage 表示上传内容不是受支持格式的图片字节。
	ErrUploadUnsupportedImage = errors.New("unsupported image content")
)

// UploadedImage 表示一次图片上传的输入流。
type UploadedImage struct {
	// Reader 是请求体中 file 部件的流；由调用方负责关闭。
	Reader io.Reader
	// Filename 是客户端声明的原始文件名（服务端只取 basename）。
	Filename string
	// CommitCheck 在文件流写完后、正式发布前调用；用于调用方验证请求边界。
	// 返回非 nil 会中止上传且不发布已写内容；为 nil 时直接发布。
	CommitCheck func() error
}
type UploadResult struct {
	// MediaID 是新建或复用的 media_items.id。
	MediaID string
	// Filename 是实际落盘使用的文件名（同名时带安全后缀）。
	Filename string
}
