//go:build windows

// 本文件在 Windows 上将初始密码文件 DACL 收紧到当前服务身份、SYSTEM 和管理员，并立即复核结果。
package security

import (
	"fmt"
	"os"
	"unsafe"

	"github.com/xinghe98/Luma/backend/internal/platform"
	"golang.org/x/sys/windows"
)

// secureBootstrapPasswordFile 用受保护 DACL 替换继承权限；ACL 写入或复核失败时拒绝启动。
func secureBootstrapPasswordFile(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("读取管理员密码文件状态: %w", err)
	}
	if platform.IsLinkLike(info) {
		return fmt.Errorf("管理员密码文件不能是符号链接或 Reparse Point")
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("管理员密码文件必须是普通文件")
	}
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return fmt.Errorf("读取服务身份 SID: %w", err)
	}
	currentSID := user.User.Sid.String()
	descriptor, err := windows.SecurityDescriptorFromString(fmt.Sprintf(
		"D:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FA;;;%s)", currentSID,
	))
	if err != nil {
		return fmt.Errorf("构造管理员密码文件 ACL: %w", err)
	}
	dacl, _, err := descriptor.DACL()
	if err != nil {
		return fmt.Errorf("读取目标管理员密码文件 ACL: %w", err)
	}
	securityInfo := windows.SECURITY_INFORMATION(
		windows.DACL_SECURITY_INFORMATION | windows.PROTECTED_DACL_SECURITY_INFORMATION,
	)
	if err := windows.SetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, securityInfo, nil, nil, dacl, nil); err != nil {
		return fmt.Errorf("加固管理员密码文件 ACL: %w", err)
	}
	return verifyBootstrapPasswordACL(path, currentSID)
}

// verifyBootstrapPasswordACL 确认 DACL 不向服务身份、SYSTEM 和管理员之外的主体授予访问权。
func verifyBootstrapPasswordACL(path, currentSID string) error {
	descriptor, err := windows.GetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION)
	if err != nil {
		return fmt.Errorf("复核管理员密码文件 ACL: %w", err)
	}
	dacl, _, err := descriptor.DACL()
	if err != nil || dacl == nil {
		return fmt.Errorf("管理员密码文件缺少有效 DACL: %w", err)
	}
	allowed := map[string]bool{
		"S-1-5-18":     false,
		"S-1-5-32-544": false,
		currentSID:     false,
	}
	for index := uint32(0); index < uint32(dacl.AceCount); index++ {
		var ace *windows.ACCESS_ALLOWED_ACE
		if err := windows.GetAce(dacl, index, &ace); err != nil {
			return fmt.Errorf("读取管理员密码文件 ACL 条目: %w", err)
		}
		if ace.Header.AceType != windows.ACCESS_ALLOWED_ACE_TYPE {
			return fmt.Errorf("管理员密码文件包含非预期 ACL 条目")
		}
		sid := (*windows.SID)(unsafe.Pointer(&ace.SidStart)).String()
		if _, ok := allowed[sid]; !ok {
			return fmt.Errorf("管理员密码文件向非预期主体 %s 授权", sid)
		}
		const fileAllAccess windows.ACCESS_MASK = 0x001f01ff
		if ace.Mask&fileAllAccess != fileAllAccess {
			return fmt.Errorf("管理员密码文件主体 %s 权限不完整", sid)
		}
		allowed[sid] = true
	}
	for sid, present := range allowed {
		if !present {
			return fmt.Errorf("管理员密码文件 ACL 缺少主体 %s", sid)
		}
	}
	return nil
}
