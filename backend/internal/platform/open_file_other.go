//go:build !linux && !windows

package platform

import (
	"fmt"
	"os"
	"path/filepath"
)

// ValidateOpenFileDescendant 为非正式支持平台提供保守的文件身份复核。
func ValidateOpenFileDescendant(root string, file *os.File) error {
	opened, err := file.Stat()
	if err != nil {
		return err
	}
	resolved, err := filepath.EvalSymlinks(file.Name())
	if err != nil {
		return err
	}
	current, err := os.Stat(resolved)
	if err != nil {
		return err
	}
	inside, err := pathWithin(filepath.Clean(root), filepath.Clean(resolved))
	if err != nil {
		return err
	}
	if !inside || !os.SameFile(opened, current) {
		return fmt.Errorf("已打开文件逃出受控根目录")
	}
	return nil
}
