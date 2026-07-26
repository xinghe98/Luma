//go:build windows

// 本文件验证 Windows 上既有宽松密码文件会被收紧并通过 DACL 复核。
package security

import (
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/sys/windows"
)

// TestLoadBootstrapPasswordHardensWindowsACL 验证读取前会替换继承或 Everyone 授权。
func TestLoadBootstrapPasswordHardensWindowsACL(t *testing.T) {
	path := filepath.Join(t.TempDir(), "admin_password")
	if err := os.WriteFile(path, []byte("1234567890\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	descriptor, err := windows.SecurityDescriptorFromString("D:P(A;;FA;;;WD)")
	if err != nil {
		t.Fatal(err)
	}
	dacl, _, err := descriptor.DACL()
	if err != nil {
		t.Fatal(err)
	}
	securityInfo := windows.SECURITY_INFORMATION(
		windows.DACL_SECURITY_INFORMATION | windows.PROTECTED_DACL_SECURITY_INFORMATION,
	)
	if err := windows.SetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, securityInfo, nil, nil, dacl, nil); err != nil {
		t.Skipf("当前文件系统不支持设置测试 ACL: %v", err)
	}
	if _, _, err := LoadOrCreateBootstrapPassword(path); err != nil {
		t.Fatal(err)
	}
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		t.Fatal(err)
	}
	if err := verifyBootstrapPasswordACL(path, user.User.Sid.String()); err != nil {
		t.Fatal(err)
	}
}
