//go:build windows

package platform

import (
	"os"
	"syscall"
	"time"
)

// FileCreatedAt 读取 Windows 文件创建时间；无法识别时返回 nil。
func FileCreatedAt(_ string, info os.FileInfo) *time.Time {
	if info == nil {
		return nil
	}
	sys, ok := info.Sys().(*syscall.Win32FileAttributeData)
	if !ok {
		return nil
	}
	return unixMilliPointer(time.Unix(0, sys.CreationTime.Nanoseconds()).UTC())
}
