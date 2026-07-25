package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/config"
)

// TestOpenMigratesAndCreatesDefaultUser 验证数据库初始化、迁移和默认用户创建。
func TestOpenMigratesAndCreatesDefaultUser(t *testing.T) {
	db, err := Open(context.Background(), config.DatabaseConfig{
		Path: filepath.Join(t.TempDir(), "media.db"), BusyTimeoutMS: 1000, WAL: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var name string
	if err := db.QueryRow("SELECT name FROM users WHERE id = 'user_local'").Scan(&name); err != nil {
		t.Fatal(err)
	}
	if name != "Local User" {
		t.Fatalf("unexpected default user %q", name)
	}
	var foreignKeys int
	if err := db.QueryRow("PRAGMA foreign_keys").Scan(&foreignKeys); err != nil {
		t.Fatal(err)
	}
	if foreignKeys != 1 {
		t.Fatal("foreign keys are disabled")
	}
	var version int
	if err := db.QueryRow("SELECT MAX(version) FROM schema_migrations").Scan(&version); err != nil {
		t.Fatal(err)
	}
	if version != 14 {
		t.Fatalf("migration version = %d, want 14", version)
	}
	for _, table := range []string{"media_user_data", "tags"} {
		var columns int
		if err := db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = 'revision'`, table).Scan(&columns); err != nil {
			t.Fatal(err)
		}
		if columns != 1 {
			t.Fatalf("%s.revision column count = %d", table, columns)
		}
	}
	for _, index := range []string{"idx_media_tags_user_tag_media", "idx_user_data_continue_watching"} {
		var indexes int
		if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?`, index).Scan(&indexes); err != nil {
			t.Fatal(err)
		}
		if indexes != 1 {
			t.Fatalf("index %s missing", index)
		}
	}
}

func TestImageLibraryMigrationConvertsLegacyPhotoSources(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "image-library-upgrade.db")
	db, err := sql.Open("sqlite", "file:"+escapeSQLitePath(path)+"?_pragma=foreign_keys(1)")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at_ms INTEGER NOT NULL)`); err != nil {
		t.Fatal(err)
	}
	for _, migration := range allMigrations[:10] {
		if _, err := db.Exec(migration.sql); err != nil {
			t.Fatalf("apply %s: %v", migration.name, err)
		}
		if _, err := db.Exec(`INSERT INTO schema_migrations(version, applied_at_ms) VALUES(?, 1)`, migration.version); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`INSERT INTO sources(id,name,source_type,library_kind,root_path,enabled,status,created_at_ms,updated_at_ms)
        VALUES('photos','图片','local','photos','/photos',1,'online',1,1)`); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	upgraded, err := Open(ctx, config.DatabaseConfig{Path: path, BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer upgraded.Close()
	var kind string
	if err := upgraded.QueryRow(`SELECT library_kind FROM sources WHERE id='photos'`).Scan(&kind); err != nil {
		t.Fatal(err)
	}
	if kind != "personal" {
		t.Fatalf("legacy source kind = %q, want personal", kind)
	}
}

func TestStage6MigrationUpgradesExistingUserData(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "upgrade.db")
	db, err := sql.Open("sqlite", "file:"+escapeSQLitePath(path)+"?_pragma=foreign_keys(1)")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at_ms INTEGER NOT NULL)`); err != nil {
		t.Fatal(err)
	}
	for _, migration := range allMigrations[:6] {
		if _, err := db.Exec(migration.sql); err != nil {
			t.Fatalf("apply %s: %v", migration.name, err)
		}
		if _, err := db.Exec(`INSERT INTO schema_migrations(version, applied_at_ms) VALUES(?, 1)`, migration.version); err != nil {
			t.Fatal(err)
		}
	}
	statements := []string{
		`INSERT INTO users(id,name,created_at_ms,updated_at_ms) VALUES('user_local','Local User',1,1)`,
		`INSERT INTO sources(id,name,source_type,root_path,enabled,status,created_at_ms,updated_at_ms)
         VALUES('source','源','local','/media',1,'online',1,1)`,
		`INSERT INTO media_items(id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,discovered_at_ms,created_at_ms,updated_at_ms)
         VALUES('media','source','clip.mp4','clip.mp4','video',1,1,'ready',1,1,1)`,
		`INSERT INTO media_items(id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,discovered_at_ms,created_at_ms,updated_at_ms)
         VALUES('tag_only_media','source','tag-only.mp4','tag-only.mp4','video',1,1,'ready',1,1,1)`,
		`INSERT INTO media_user_data(user_id,media_id,favorite,created_at_ms,updated_at_ms)
         VALUES('user_local','media',1,1,1)`,
		`INSERT INTO tags(id,user_id,name,normalized_name,created_at_ms,updated_at_ms)
         VALUES('tag','user_local','旅行','旅行',1,1)`,
		`INSERT INTO media_tags(user_id,media_id,tag_id,created_at_ms)
         VALUES('user_local','media','tag',1)`,
		`INSERT INTO media_tags(user_id,media_id,tag_id,created_at_ms)
         VALUES('user_local','tag_only_media','tag',2)`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			t.Fatal(err)
		}
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	upgraded, err := Open(ctx, config.DatabaseConfig{Path: path, BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer upgraded.Close()
	var userRevision, tagOnlyRevision, tagRevision, relations int
	if err := upgraded.QueryRow(`SELECT revision FROM media_user_data WHERE user_id='user_local' AND media_id='media'`).Scan(&userRevision); err != nil {
		t.Fatal(err)
	}
	if err := upgraded.QueryRow(`SELECT revision FROM tags WHERE id='tag'`).Scan(&tagRevision); err != nil {
		t.Fatal(err)
	}
	if err := upgraded.QueryRow(`SELECT revision FROM media_user_data
        WHERE user_id='user_local' AND media_id='tag_only_media'`).Scan(&tagOnlyRevision); err != nil {
		t.Fatal(err)
	}
	if err := upgraded.QueryRow(`SELECT COUNT(*) FROM media_tags WHERE tag_id='tag'`).Scan(&relations); err != nil {
		t.Fatal(err)
	}
	if userRevision != 1 || tagOnlyRevision != 1 || tagRevision != 1 || relations != 2 {
		t.Fatalf("user revision=%d tag-only revision=%d tag revision=%d relations=%d", userRevision, tagOnlyRevision, tagRevision, relations)
	}
}
