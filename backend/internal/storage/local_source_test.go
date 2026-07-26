package storage

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// fakeFileIdentifier 为本地媒体源测试返回固定文件身份。
type fakeFileIdentifier struct{}

// Identify 返回固定测试文件身份。
func (fakeFileIdentifier) Identify(string) (string, error) { return "file:test", nil }

// fakeStorageClock 返回固定健康检查时间。
type fakeStorageClock struct{}

// Now 返回 Unix Epoch。
func (fakeStorageClock) Now() time.Time { return time.Unix(0, 0).UTC() }

// TestLocalSourceWalkAndOpenRemainInsideRoot 验证遍历和打开操作不能逃出根目录。
func TestLocalSourceWalkAndOpenRemainInsideRoot(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "media")
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "video.mp4"), []byte("video"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(base, "secret.txt"), []byte("secret"), 0o644); err != nil {
		t.Fatal(err)
	}
	factory, err := NewLocalFactory(fakeFileIdentifier{}, fakeStorageClock{})
	if err != nil {
		t.Fatal(err)
	}
	source, err := factory.Local(root)
	if err != nil {
		t.Fatal(err)
	}
	var entries []FileEntry
	if err := source.Walk(context.Background(), func(entry FileEntry) error {
		entries = append(entries, entry)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].RelativePath != "video.mp4" || entries[0].FileID != "file:test" {
		t.Fatalf("遍历结果不符合预期: %#v", entries)
	}
	if _, err := source.Open(context.Background(), "../secret.txt"); err == nil {
		t.Fatal("媒体源不应允许路径穿越")
	}
}

// TestLocalSourceSkipsSymlinkEscape 验证遍历不会索引指向根目录外的符号链接。
func TestLocalSourceSkipsSymlinkEscape(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "media")
	outside := filepath.Join(base, "outside.mp4")
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("outside"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "escape.mp4")); err != nil {
		t.Skipf("当前环境不支持符号链接: %v", err)
	}
	factory, err := NewLocalFactory(fakeFileIdentifier{}, fakeStorageClock{})
	if err != nil {
		t.Fatal(err)
	}
	source, err := factory.Local(root)
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	if err := source.Walk(context.Background(), func(FileEntry) error {
		count++
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("符号链接逃逸文件被错误索引，数量 = %d", count)
	}
}

// TestLocalFactoryOpenContentReturnsActualMetadata 验证流读取使用打开后文件的实际元数据。
func TestLocalFactoryOpenContentReturnsActualMetadata(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "clip.mp4")
	modified := time.Unix(123, 0).UTC()
	if err := os.WriteFile(path, []byte("video"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, modified, modified); err != nil {
		t.Fatal(err)
	}
	factory, err := NewLocalFactory(fakeFileIdentifier{}, fakeStorageClock{})
	if err != nil {
		t.Fatal(err)
	}
	content, err := factory.OpenContent(context.Background(), root, "clip.mp4")
	if err != nil {
		t.Fatal(err)
	}
	defer content.Reader.Close()
	if content.Size != 5 || !content.ModifiedAt.Equal(modified) {
		t.Fatalf("content = %#v", content)
	}
	if _, err := factory.OpenContent(context.Background(), root, "../outside.mp4"); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("traversal error = %v", err)
	}
	if _, err := factory.OpenContent(context.Background(), root, "."); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("directory error = %v", err)
	}
}

// TestLocalFactoryOpenContentRejectsSymlinkEscape 验证打开阶段拒绝指向根外的符号链接。
func TestLocalFactoryOpenContentRejectsSymlinkEscape(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "media")
	outside := filepath.Join(base, "outside.mp4")
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("secret"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "escape.mp4")); err != nil {
		t.Skipf("当前环境不支持符号链接: %v", err)
	}
	factory, err := NewLocalFactory(fakeFileIdentifier{}, fakeStorageClock{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := factory.OpenContent(context.Background(), root, "escape.mp4"); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("symlink escape error = %v", err)
	}
}

// TestLocalFactoryRevalidatesResolvedRoot 验证每次重新解析来源根目录都会再次应用白名单。
func TestLocalFactoryRevalidatesResolvedRoot(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "clip.mp4"), []byte("video"), 0o644); err != nil {
		t.Fatal(err)
	}
	validator := &countingRootValidator{root: root}
	factory, err := NewLocalFactory(fakeFileIdentifier{}, fakeStorageClock{}, validator)
	if err != nil {
		t.Fatal(err)
	}
	_, err = factory.resolveRoot(root)
	if err != nil {
		t.Fatal(err)
	}
	_, err = factory.resolveRoot(root)
	if err != nil {
		t.Fatal(err)
	}
	if validator.calls != 2 {
		t.Fatalf("白名单校验次数 = %d，期望 2", validator.calls)
	}
	content, err := factory.OpenContent(context.Background(), root, "clip.mp4")
	if err != nil {
		t.Fatal(err)
	}
	_ = content.Reader.Close()
	if validator.calls != 3 {
		t.Fatalf("打开内容后的白名单校验次数 = %d，期望 3", validator.calls)
	}
}

// countingRootValidator 记录本地工厂重新校验根目录的次数。
type countingRootValidator struct {
	root  string
	calls int
}

// ValidateSourceRoot 返回测试根目录并累计调用次数。
func (v *countingRootValidator) ValidateSourceRoot(string) (string, error) {
	v.calls++
	return v.root, nil
}

// TestLocalFactoryOpenContentUnavailableRoot 验证根目录不可用时返回 SOURCE_OFFLINE。
func TestLocalFactoryOpenContentUnavailableRoot(t *testing.T) {
	factory, err := NewLocalFactory(fakeFileIdentifier{}, fakeStorageClock{})
	if err != nil {
		t.Fatal(err)
	}
	missing := filepath.Join(t.TempDir(), "missing-root")
	if _, err := factory.OpenContent(context.Background(), missing, "clip.mp4"); !errors.Is(err, domain.ErrSourceOffline) {
		t.Fatalf("error = %v", err)
	}
}
