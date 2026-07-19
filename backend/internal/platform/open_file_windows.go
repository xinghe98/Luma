//go:build windows

package platform

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows"
)

// ValidateOpenFileDescendant 根据 Windows 文件句柄确认已打开对象仍在根目录内。
// 根目录与文件都通过 GetFinalPathNameByHandle 规范化，避免映射盘符（Z:）与 UNC 路径无法比较。
func ValidateOpenFileDescendant(root string, file *os.File) error {
	filePath, err := finalPathFromHandle(windows.Handle(file.Fd()))
	if err != nil {
		return err
	}
	rootFile, err := os.Open(root)
	if err != nil {
		return fmt.Errorf("打开媒体源根目录以校验句柄路径: %w", err)
	}
	defer rootFile.Close()
	rootPath, err := finalPathFromHandle(windows.Handle(rootFile.Fd()))
	if err != nil {
		return err
	}
	inside, err := pathWithin(rootPath, filePath)
	if err != nil {
		return err
	}
	if !inside {
		return fmt.Errorf("已打开文件逃出受控根目录")
	}
	return nil
}

func finalPathFromHandle(handle windows.Handle) (string, error) {
	buffer := make([]uint16, 32768)
	n, err := windows.GetFinalPathNameByHandle(handle, &buffer[0], uint32(len(buffer)), 0)
	if err != nil {
		return "", err
	}
	if n == 0 || n >= uint32(len(buffer)) {
		return "", fmt.Errorf("已打开对象的最终路径无效")
	}
	resolved := windows.UTF16ToString(buffer[:n])
	switch {
	case strings.HasPrefix(resolved, `\\?\UNC\`):
		resolved = `\\` + strings.TrimPrefix(resolved, `\\?\UNC\`)
	default:
		resolved = strings.TrimPrefix(resolved, `\\?\`)
	}
	return filepath.Clean(resolved), nil
}
