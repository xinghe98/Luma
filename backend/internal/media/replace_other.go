//go:build !windows

package media

import "os"

// atomicReplace 在 POSIX 文件系统中使用 rename 原子替换目标。
func atomicReplace(source, destination string) error { return os.Rename(source, destination) }
