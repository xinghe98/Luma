//go:build windows

// 验证 Windows 文件占用时保留原图，释放句柄后可通过同一存储入口重试删除。
package storage

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// TestRemoveSourceFileBusyCanRetry 验证占用失败不会改写文件，关闭占用后可正常删除。
func TestRemoveSourceFileBusyCanRetry(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "busy.png")
	if err := os.WriteFile(path, []byte("original"), 0o644); err != nil {
		t.Fatal(err)
	}
	reader, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = reader.Close() })
	factory := newDeleteFactory(t)
	if err := factory.RemoveSourceFile(context.Background(), root, "busy.png"); !errors.Is(err, domain.ErrMediaInUse) {
		t.Fatalf("occupied file error = %v", err)
	}
	if content, err := os.ReadFile(path); err != nil || string(content) != "original" {
		t.Fatalf("occupied original changed: %q, %v", content, err)
	}
	if err := reader.Close(); err != nil {
		t.Fatal(err)
	}
	if err := factory.RemoveSourceFile(context.Background(), root, "busy.png"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("released original still exists: %v", err)
	}
}
