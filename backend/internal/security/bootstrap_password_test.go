// 本文件验证初始管理员密码文件的创建、复用与平台权限加固入口。
package security

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestLoadOrCreateBootstrapPasswordCreatesAndReusesSecret 验证密码只创建一次且后续读取保持一致。
func TestLoadOrCreateBootstrapPasswordCreatesAndReusesSecret(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secrets", "admin_password")
	first, created, err := LoadOrCreateBootstrapPassword(path)
	if err != nil {
		t.Fatal(err)
	}
	if !created || first == "" {
		t.Fatalf("created = %v, password empty = %v", created, first == "")
	}
	second, created, err := LoadOrCreateBootstrapPassword(path)
	if err != nil {
		t.Fatal(err)
	}
	if created || second != first {
		t.Fatalf("second create = %v, password changed = %v", created, second != first)
	}
}

// TestLoadBootstrapPasswordRejectsLink 验证密码文件不能通过符号链接或 Reparse Point 间接读取。
func TestLoadBootstrapPasswordRejectsLink(t *testing.T) {
	base := t.TempDir()
	target := filepath.Join(base, "target")
	link := filepath.Join(base, "admin_password")
	if err := os.WriteFile(target, []byte("1234567890\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("当前环境不支持符号链接: %v", err)
	}
	if _, _, err := LoadOrCreateBootstrapPassword(link); err == nil || !strings.Contains(err.Error(), "链接") {
		t.Fatalf("expected link rejection, got %v", err)
	}
}
