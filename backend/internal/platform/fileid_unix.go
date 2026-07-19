//go:build !windows

package platform

import (
	"fmt"
	"os"
	"syscall"
)

// OSFileIdentifier 使用 Unix device 与 inode 获取文件身份。
type OSFileIdentifier struct{}

// Identify 返回指定文件的设备号和 inode。
func (OSFileIdentifier) Identify(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return "", fmt.Errorf("文件系统未提供稳定文件标识")
	}
	return fmt.Sprintf("%x:%x", uint64(stat.Dev), uint64(stat.Ino)), nil
}
