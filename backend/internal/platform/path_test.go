package platform

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// TestPathPolicyAllowsOnlyDescendants 验证白名单只允许根目录及其后代目录。
func TestPathPolicyAllowsOnlyDescendants(t *testing.T) {
	base := t.TempDir()
	allowed := filepath.Join(base, "allowed")
	inside := filepath.Join(allowed, "library")
	outside := filepath.Join(base, "outside")
	for _, dir := range []string{inside, outside} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	policy, err := NewPathPolicy([]string{allowed})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := policy.ValidateSourceRoot(inside); err != nil {
		t.Fatalf("inside root rejected: %v", err)
	}
	if _, err := policy.ValidateSourceRoot(outside); err == nil {
		t.Fatal("outside root accepted")
	}
}

// TestNormalizeRelativePathRejectsEscapeAndNormalizesWindowsCase 验证相对路径安全及 Windows 大小写规则。
func TestNormalizeRelativePathRejectsEscapeAndNormalizesWindowsCase(t *testing.T) {
	if _, err := NormalizeRelativePath(filepath.Join("..", "secret.mp4")); err == nil {
		t.Fatal("应拒绝逃出媒体源的相对路径")
	}
	path, err := NormalizeRelativePath(filepath.Join("Folder", "Video.MP4"))
	if err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS == "windows" && path != "folder/video.mp4" {
		t.Fatalf("Windows 规范路径 = %q", path)
	}
}

// TestPathPolicyRejectsSymlinkEscape 验证符号链接不能逃出目录白名单。
func TestPathPolicyRejectsSymlinkEscape(t *testing.T) {
	base := t.TempDir()
	allowed := filepath.Join(base, "allowed")
	outside := filepath.Join(base, "outside")
	if err := os.MkdirAll(allowed, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(allowed, "escape")
	if err := os.Symlink(outside, link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	policy, err := NewPathPolicy([]string{allowed})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := policy.ValidateSourceRoot(link); err == nil {
		t.Fatal("symlink escape accepted")
	}
}
