// 本文件职责：图片原始文件删除的存储层回归测试。
// 使用真实临时目录与工厂，覆盖普通删除、嵌套路径、目录/链接拒绝、
// 目标缺失幂等与符号链接逃逸防护。
package storage

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func newDeleteFactory(t *testing.T) *LocalFactory {
	t.Helper()
	factory, err := NewLocalFactory(fakeFileIdentifier{}, fakeStorageClock{})
	if err != nil {
		t.Fatal(err)
	}
	return factory
}

// TestRemoveSourceFileDeletesRegularFile 验证删除普通文件成功且不触碰同目录其他内容。
func TestRemoveSourceFileDeletesRegularFile(t *testing.T) {
	root := t.TempDir()
	keep := filepath.Join(root, "keep.png")
	if err := os.WriteFile(keep, []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "photo.png")
	if err := os.WriteFile(target, []byte("photo"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "photo.png"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("文件未被删除: %v", err)
	}
	if _, err := os.Stat(keep); err != nil {
		t.Fatalf("误删同目录文件: %v", err)
	}
}

// TestRemoveSourceFileDeletesNestedImage 验证子目录内的图片可被删除。
func TestRemoveSourceFileDeletesNestedImage(t *testing.T) {
	root := t.TempDir()
	sub := filepath.Join(root, "2024", "01")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(sub, "a.jpg")
	if err := os.WriteFile(target, []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "2024/01/a.jpg"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("嵌套文件未被删除: %v", err)
	}
}

// TestRemoveSourceFileRejectsDirectory 验证目标是目录时拒绝删除且目录保留。
func TestRemoveSourceFileRejectsDirectory(t *testing.T) {
	root := t.TempDir()
	sub := filepath.Join(root, "folder.png")
	if err := os.Mkdir(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "folder.png")
	if !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("应拒绝目录删除: %v", err)
	}
	if info, err := os.Stat(sub); err != nil || !info.IsDir() {
		t.Fatalf("目录被删除: %v", err)
	}
}

// TestRemoveSourceFileRejectsTraversal 验证越界相对路径被拒绝。
func TestRemoveSourceFileRejectsTraversal(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "media")
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(base, "secret.png")
	if err := os.WriteFile(outside, []byte("secret"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "../secret.png")
	if !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("应拒绝越界路径: %v", err)
	}
	if _, err := os.Stat(outside); err != nil {
		t.Fatalf("越界文件被删除: %v", err)
	}
}

// TestRemoveSourceFileSkipsSymlink 验证符号链接目标被拒绝且链接本身保留。
func TestRemoveSourceFileSkipsSymlink(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "media")
	outside := filepath.Join(base, "secret.png")
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("secret"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "linked.png")
	if err := os.Symlink(outside, link); err != nil {
		t.Skipf("当前平台不允许创建符号链接: %v", err)
	}
	err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "linked.png")
	if !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("应拒绝符号链接: %v", err)
	}
	if _, err := os.Lstat(link); err != nil {
		t.Fatalf("符号链接本身被删除: %v", err)
	}
	if _, err := os.Stat(outside); err != nil {
		t.Fatalf("链接目标被删除: %v", err)
	}
}

// TestRemoveSourceFileAlreadyMissingIsIdempotent 验证目标不存在时返回成功（幂等）。
func TestRemoveSourceFileAlreadyMissingIsIdempotent(t *testing.T) {
	root := t.TempDir()
	if err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "gone.png"); err != nil {
		t.Fatalf("已缺失文件应返回成功: %v", err)
	}
}

// TestRemoveSourceFileRejectsDirectoryTarget 验证以目录为删除目标被确定性拒绝：
// 目录本身保留，目录内的文件也不受影响。
func TestRemoveSourceFileRejectsDirectoryTarget(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "photos")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	inner := filepath.Join(dir, "a.png")
	if err := os.WriteFile(inner, []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "photos")
	if !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("应拒绝目录目标: %v", err)
	}
	if _, err := os.Stat(dir); err != nil {
		t.Fatalf("目录被误删: %v", err)
	}
	if _, err := os.Stat(inner); err != nil {
		t.Fatalf("目录内文件被误删: %v", err)
	}
}

// TestRemoveSourceFileRejectsSymlinkedParentDir 验证根目录内指向根内的
// 符号链接父目录同样被拒绝：os.Root 允许跟随根内链接，但删除与扫描/打开
// 的既有安全规则一致，任何一级链接类组件都不放行。
func TestRemoveSourceFileRejectsSymlinkedParentDir(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "media")
	realDir := filepath.Join(root, "real")
	if err := os.MkdirAll(realDir, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(realDir, "a.png")
	if err := os.WriteFile(target, []byte("a"), 0o644); err != nil {
		t.Fatal(err)
	}
	linkDir := filepath.Join(root, "linked")
	if err := os.Symlink(realDir, linkDir); err != nil {
		t.Skipf("当前平台不允许创建目录符号链接: %v", err)
	}
	err := newDeleteFactory(t).RemoveSourceFile(context.Background(), root, "linked/a.png")
	if !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("应拒绝符号链接父目录: %v", err)
	}
	if _, err := os.Stat(target); err != nil {
		t.Fatalf("经链接路径误删真实文件: %v", err)
	}
}

// TestRemoveSourceFileOfflineRoot 验证根目录不可用时返回来源离线错误。
func TestRemoveSourceFileOfflineRoot(t *testing.T) {
	err := newDeleteFactory(t).RemoveSourceFile(context.Background(), filepath.Join(t.TempDir(), "nonexistent"), "a.png")
	if !errors.Is(err, domain.ErrSourceOffline) {
		t.Fatalf("应映射为来源离线: %v", err)
	}
}
