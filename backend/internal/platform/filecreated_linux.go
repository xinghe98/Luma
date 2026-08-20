//go:build linux

package platform

import (
	"os"
	"time"

	"golang.org/x/sys/unix"
)

// FileCreatedAt 通过 statx 读取文件出生时间；文件系统未提供时返回 nil。
func FileCreatedAt(path string, _ os.FileInfo) *time.Time {
	var stat unix.Statx_t
	if err := unix.Statx(unix.AT_FDCWD, path, 0, unix.STATX_BTIME, &stat); err != nil {
		return nil
	}
	if stat.Mask&unix.STATX_BTIME == 0 {
		return nil
	}
	return unixMilliPointer(time.Unix(stat.Btime.Sec, int64(stat.Btime.Nsec)).UTC())
}
