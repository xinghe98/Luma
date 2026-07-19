//go:build !windows

package platform

import "os"

// IsLinkLike 判断文件是否为 Unix 符号链接。
func IsLinkLike(info os.FileInfo) bool {
	return info.Mode()&os.ModeSymlink != 0
}
