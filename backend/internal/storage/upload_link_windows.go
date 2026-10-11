//go:build windows

package storage

import (
	"errors"

	"golang.org/x/sys/windows"
)

// errHardlinkUnsupported 在 Windows 上表示底层文件系统不提供硬链接。
// ERROR_INVALID_FUNCTION 是 FAT/exFAT/SMB 对 CreateHardLink 的典型返回；
// 权限错误不归入此类，避免把只读/无权误判成“需要换发布路径”。
var errHardlinkUnsupported = errors.Join(windows.ERROR_INVALID_FUNCTION, windows.ERROR_NOT_SUPPORTED)
