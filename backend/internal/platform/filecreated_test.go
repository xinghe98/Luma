package platform

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFileCreatedAtReadsDiskBirthTime(t *testing.T) {
	path := filepath.Join(t.TempDir(), "clip.mp4")
	before := time.Now().UTC().Add(-2 * time.Second)
	if err := os.WriteFile(path, []byte("video"), 0o644); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	after := time.Now().UTC().Add(2 * time.Second)
	created := FileCreatedAt(path, info)
	if created == nil {
		t.Skip("当前文件系统未提供文件创建时间")
	}
	if created.Before(before) || created.After(after) {
		t.Fatalf("created=%s before=%s after=%s", created.UTC(), before, after)
	}
}
