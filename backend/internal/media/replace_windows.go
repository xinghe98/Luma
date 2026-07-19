//go:build windows

package media

import "golang.org/x/sys/windows"

// atomicReplace 使用 Windows 原生替换语义，目标存在时仍保持原子性。
func atomicReplace(source, destination string) error {
	from, err := windows.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	to, err := windows.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	return windows.MoveFileEx(from, to, windows.MOVEFILE_REPLACE_EXISTING|windows.MOVEFILE_WRITE_THROUGH)
}
