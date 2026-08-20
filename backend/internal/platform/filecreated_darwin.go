//go:build darwin

package platform

import (
	"os"
	"syscall"
	"time"
)

// FileCreatedAt 读取 Darwin Birthtimespec；不可用时返回 nil。
func FileCreatedAt(_ string, info os.FileInfo) *time.Time {
	if info == nil {
		return nil
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return nil
	}
	return unixMilliPointer(time.Unix(stat.Birthtimespec.Sec, stat.Birthtimespec.Nsec).UTC())
}
