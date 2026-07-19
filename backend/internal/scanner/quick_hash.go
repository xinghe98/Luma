package scanner

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"

	"github.com/xinghe98/Luma/backend/internal/storage"
)

// quickHashBlockSize 是快速指纹读取文件头尾的单个分块大小。
const quickHashBlockSize int64 = 64 * 1024

// SHA256QuickHasher 使用文件大小、文件头和文件尾生成快速指纹。
type SHA256QuickHasher struct{}

// Hash 读取最多两个 64 KiB 分块并返回 SHA-256 十六进制摘要。
func (SHA256QuickHasher) Hash(ctx context.Context, source storage.MediaSource, relativePath string, size int64) (string, error) {
	if size < 0 {
		return "", fmt.Errorf("文件大小不能为负数")
	}
	reader, err := source.Open(ctx, relativePath)
	if err != nil {
		return "", fmt.Errorf("打开文件计算快速指纹: %w", err)
	}
	defer reader.Close()

	hash := sha256.New()
	var sizeBytes [8]byte
	binary.BigEndian.PutUint64(sizeBytes[:], uint64(size))
	_, _ = hash.Write(sizeBytes[:])
	firstSize := min(size, quickHashBlockSize)
	if err := writeBlock(ctx, hash, reader, firstSize); err != nil {
		return "", err
	}
	if size > quickHashBlockSize {
		if _, err := reader.Seek(max(0, size-quickHashBlockSize), io.SeekStart); err != nil {
			return "", fmt.Errorf("定位文件尾部: %w", err)
		}
		if err := writeBlock(ctx, hash, reader, min(size, quickHashBlockSize)); err != nil {
			return "", err
		}
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

// writeBlock 将固定长度文件分块写入哈希，并在读取前后检查取消信号。
func writeBlock(ctx context.Context, target io.Writer, reader io.Reader, size int64) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if size == 0 {
		return nil
	}
	if _, err := io.CopyN(target, reader, size); err != nil {
		return fmt.Errorf("读取快速指纹分块: %w", err)
	}
	return ctx.Err()
}
