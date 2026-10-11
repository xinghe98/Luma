//go:build !windows && !unix

// 本文件为既非 Windows 也非类 Unix 的罕见平台提供保守实现：
// 没有可靠的原子“只删普通文件”原语，明确报错而不是放宽安全语义。
package storage

import (
	"fmt"
	"os"
)

// removeRegularFile 在当前平台没有目录句柄级 unlinkat/非目录删除原语；
// 保守拒绝而不是退化到可能误删空目录的路径删除。
func removeRegularFile(parent *os.Root, name string) error {
	return fmt.Errorf("当前平台不支持安全的媒体文件删除")
}
