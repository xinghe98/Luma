//go:build !windows

// 本文件在 Unix 平台验证初始管理员密码文件权限，不改变既有宽松权限以免掩盖部署错误。
package security

import (
	"errors"
	"fmt"
	"os"

	"github.com/xinghe98/Luma/backend/internal/platform"
)

// secureBootstrapPasswordFile 确认密码文件仅对所有者开放；状态读取失败或权限过宽时拒绝启动。
func secureBootstrapPasswordFile(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("读取管理员密码文件状态: %w", err)
	}
	if platform.IsLinkLike(info) {
		return errors.New("管理员密码文件不能是符号链接")
	}
	if !info.Mode().IsRegular() {
		return errors.New("管理员密码文件必须是普通文件")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return errors.New("管理员密码文件不能向组或其他用户开放")
	}
	return nil
}
