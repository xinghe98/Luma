//go:build windows || linux

// 上传发布回归测试直接覆盖无硬链接分支，验证并发不覆盖与目录句柄边界。
package storage

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

func TestUploadRenamePreservesConcurrentFiles(t *testing.T) {
	directory := t.TempDir()
	root, err := os.OpenRoot(directory)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	if err := os.WriteFile(filepath.Join(directory, "photo.png"), []byte("original"), 0600); err != nil {
		t.Fatal(err)
	}
	var group sync.WaitGroup
	for i := range 8 {
		stage := fmt.Sprintf(".stage-%d", i)
		payload := fmt.Sprintf("image-%d", i)
		if err := os.WriteFile(filepath.Join(directory, stage), []byte(payload), 0600); err != nil {
			t.Fatal(err)
		}
		group.Add(1)
		go func() {
			defer group.Done()
			result, err := (&LocalFactory{}).publishByRename(root, stage, "photo.png", "photo", ".png", UploadWriteResult{})
			if err != nil {
				t.Error(err)
				return
			}
			got, err := os.ReadFile(filepath.Join(directory, result.Filename))
			if err != nil || string(got) != payload {
				t.Errorf("上传内容被覆盖: %q, %v", got, err)
			}
			if _, err := root.Stat(stage); !os.IsNotExist(err) {
				t.Errorf("暂存文件未消失: %v", err)
			}
		}()
	}
	group.Wait()
	got, err := os.ReadFile(filepath.Join(directory, "photo.png"))
	if err != nil || string(got) != "original" {
		t.Fatalf("覆盖了既有图片: %q, %v", got, err)
	}
}

func TestUploadRenameUsesOpenedDirectory(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows 不允许重命名持有打开句柄的目录")
	}
	parent := t.TempDir()
	original := filepath.Join(parent, "photos")
	moved := filepath.Join(parent, "moved")
	if err := os.Mkdir(original, 0700); err != nil {
		t.Fatal(err)
	}
	root, err := os.OpenRoot(original)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	if err := os.WriteFile(filepath.Join(original, ".stage"), []byte("selected"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(original, moved); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(original, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(original, ".stage"), []byte("replacement"), 0600); err != nil {
		t.Fatal(err)
	}
	result, err := (&LocalFactory{}).publishByRename(root, ".stage", "photo.png", "photo", ".png", UploadWriteResult{})
	if err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(moved, result.Filename))
	if err != nil || string(got) != "selected" {
		t.Fatalf("发布未留在原目录: %q, %v", got, err)
	}
	got, err = os.ReadFile(filepath.Join(original, ".stage"))
	if err != nil || string(got) != "replacement" {
		t.Fatalf("错误触碰替换目录: %q, %v", got, err)
	}
}
