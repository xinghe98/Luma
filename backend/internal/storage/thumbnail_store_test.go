package storage

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestThumbnailStoreReadsNamespacedKeyAndRejectsTraversal(t *testing.T) {
	root := t.TempDir()
	directory := filepath.Join(root, "media_1")
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "cover.jpg"), []byte("jpeg"), 0o644); err != nil {
		t.Fatal(err)
	}
	store, err := NewThumbnailStore(root)
	if err != nil {
		t.Fatal(err)
	}
	data, err := store.Read("thumbnails/media_1/cover.jpg")
	if err != nil || string(data) != "jpeg" {
		t.Fatalf("data=%q error=%v", data, err)
	}
	for _, key := range []string{"../outside.jpg", "thumbnails/../outside.jpg", "thumbnails\\media_1\\cover.jpg", "C:/outside.jpg"} {
		if _, err := store.Read(key); err == nil {
			t.Fatalf("key %q should fail", key)
		}
	}
	if _, err := store.Read("thumbnails/media_1/missing.jpg"); !errors.Is(err, domain.ErrThumbnailNotFound) {
		t.Fatalf("missing error = %v", err)
	}
}

func TestThumbnailStoreRejectsOversizedFile(t *testing.T) {
	root := t.TempDir()
	directory := filepath.Join(root, "media_1")
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "huge.jpg")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := file.Truncate(MaxThumbnailBytes + 1); err != nil {
		t.Fatal(err)
	}
	_ = file.Close()
	store, err := NewThumbnailStore(root)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Read("thumbnails/media_1/huge.jpg"); !errors.Is(err, domain.ErrThumbnailTooLarge) {
		t.Fatalf("error = %v", err)
	}
}
