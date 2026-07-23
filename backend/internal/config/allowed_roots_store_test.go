package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAllowedRootsStoreAddsAndRestoresOneDirectory(t *testing.T) {
	base := t.TempDir()
	first := filepath.Join(base, "first")
	second := filepath.Join(base, "second")
	if err := os.Mkdir(first, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(second, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(base, "config.yaml")
	content := "# Keep this comment while updating only allowed_roots.\nsecurity:\n  api_token_file: data/token\n  allowed_roots:\n    - " + first + "\ndatabase:\n  path: data/media.db\nstorage:\n  thumbnail_dir: data/thumbnails\n  cache_dir: data/cache\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	store, err := NewAllowedRootsStore(path)
	if err != nil {
		t.Fatal(err)
	}
	update, err := store.Add(second)
	if err != nil {
		t.Fatal(err)
	}
	if len(update.Previous) != 1 || len(update.Current) != 2 {
		t.Fatalf("unexpected update: %#v", update)
	}
	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg.Security.AllowedRoots) != 2 {
		t.Fatalf("allowed roots = %#v", cfg.Security.AllowedRoots)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "Keep this comment") {
		t.Fatal("unrelated YAML comment was removed")
	}
	if err := store.Restore(update); err != nil {
		t.Fatal(err)
	}
	cfg, err = Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg.Security.AllowedRoots) != 1 || cfg.Security.AllowedRoots[0] != first {
		t.Fatalf("restored roots = %#v", cfg.Security.AllowedRoots)
	}
}
