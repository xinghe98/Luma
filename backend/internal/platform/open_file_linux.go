//go:build linux

package platform

import (
	"fmt"
	"os"
	"path/filepath"
)

// ValidateOpenFileDescendant 根据 Linux 文件描述符确认已打开对象仍在根目录内。
func ValidateOpenFileDescendant(root string, file *os.File) error {
	resolved, err := os.Readlink(fmt.Sprintf("/proc/self/fd/%d", file.Fd()))
	if err != nil {
		return err
	}
	inside, err := pathWithin(filepath.Clean(root), filepath.Clean(resolved))
	if err != nil {
		return err
	}
	if !inside {
		return fmt.Errorf("已打开文件逃出受控根目录")
	}
	return nil
}
