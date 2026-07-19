//go:build windows

package platform

import (
	"os"
	"path/filepath"
	"testing"
)

// TestValidateOpenFileDescendantAcceptsLocalFile 验证本地盘符路径的句柄校验。
func TestValidateOpenFileDescendantAcceptsLocalFile(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "clip.mp4")
	if err := os.WriteFile(path, []byte("video"), 0o644); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if err := ValidateOpenFileDescendant(root, file); err != nil {
		t.Fatalf("local validate: %v", err)
	}
}

// TestValidateOpenFileDescendantAcceptsMappedDriveIfPresent 验证映射网络盘与 UNC 最终路径可比较。
func TestValidateOpenFileDescendantAcceptsMappedDriveIfPresent(t *testing.T) {
	root := `z:\video`
	rel := filepath.Join("新建文件夹", "新建文件夹", "20210606_192611.mp4")
	path := filepath.Join(root, rel)
	if _, err := os.Stat(path); err != nil {
		t.Skipf("mapped drive sample unavailable: %v", err)
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if err := ValidateOpenFileDescendant(root, file); err != nil {
		t.Fatalf("mapped drive validate: %v", err)
	}
}
