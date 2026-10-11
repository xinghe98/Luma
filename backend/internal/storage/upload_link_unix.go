//go:build !windows

package storage

import (
	"errors"
	"syscall"
)

// errHardlinkUnsupported 在类 Unix 上表示底层文件系统不提供硬链接。
// EPERM/ENOSYS 是 linkat 在不支持文件系统上的典型返回；
// 权限拒绝另行处理，不归入此类。
var errHardlinkUnsupported = errors.Join(syscall.EPERM, syscall.ENOSYS, syscall.EOPNOTSUPP)
