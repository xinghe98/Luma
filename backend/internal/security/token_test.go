package security

import (
	"os"
	"path/filepath"
	"testing"
)

// TestLoadOrCreateTokenPersistsToken 验证 Token 首次生成后会被安全复用。
func TestLoadOrCreateTokenPersistsToken(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secrets", "api_token")
	first, created, err := LoadOrCreateToken(path)
	if err != nil {
		t.Fatal(err)
	}
	if !created || len(first) < 32 {
		t.Fatalf("expected a newly generated strong token")
	}
	second, created, err := LoadOrCreateToken(path)
	if err != nil {
		t.Fatal(err)
	}
	if created || !MatchesToken(first, second) {
		t.Fatal("expected the persisted token to be reused")
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
}
