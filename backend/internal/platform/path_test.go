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

// TestPathPolicyReevaluatesAllowedRoot 验证白名单链接目标变化后不会继续使用旧最终路径。
func TestPathPolicyReevaluatesAllowedRoot(t *testing.T) {
	base := t.TempDir()
	first := filepath.Join(base, "first")
	second := filepath.Join(base, "second")
	for _, directory := range []string{first, second} {
		if err := os.Mkdir(directory, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	link := filepath.Join(base, "allowed")
	if err := os.Symlink(first, link); err != nil {
		t.Skipf("当前环境不支持符号链接: %v", err)
	}
	policy, err := NewPathPolicy([]string{link})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := policy.ValidateSourceRoot(first); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(link); err != nil {
		t.Skipf("无法重绑定测试链接: %v", err)
	}
	if err := os.Symlink(second, link); err != nil {
		t.Skipf("无法重建测试链接: %v", err)
	}
	if _, err := policy.ValidateSourceRoot(first); err == nil {
		t.Fatal("白名单重绑定后仍接受旧目标")
	}
	if _, err := policy.ValidateSourceRoot(second); err != nil {
		t.Fatalf("白名单重绑定后的新目标被拒绝: %v", err)
	}
}
