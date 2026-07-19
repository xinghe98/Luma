package scanner

import (
	"context"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// Scanner 定义扫描媒体源并逐个返回受支持文件的能力。
type Scanner interface {
	// Scan 完整遍历媒体源；任何遍历错误都会返回并阻止 missing 提交。
	Scan(context.Context, storage.MediaSource, func(domain.DiscoveredFile) error) error
}

// QuickHasher 定义按需计算媒体文件快速指纹的能力。
type QuickHasher interface {
	// Hash 计算指定相对路径媒体文件的头尾快速指纹。
	Hash(context.Context, storage.MediaSource, string, int64) (string, error)
}
