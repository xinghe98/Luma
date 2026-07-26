package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
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
	if version != 20 {
		t.Fatalf("migration version = %d, want 20", version)
	}
	var missingChecksums int
	if err := db.QueryRow(`SELECT COUNT(*) FROM schema_migrations WHERE checksum IS NULL OR checksum = ''`).Scan(&missingChecksums); err != nil {
		t.Fatal(err)
	}
	if missingChecksums != 0 {
		t.Fatalf("missing migration checksums = %d", missingChecksums)
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
	for _, index := range []string{"idx_media_tags_user_tag_media", "idx_user_data_continue_watching", "idx_sessions_active_user_device_key"} {
		var indexes int
		if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?`, index).Scan(&indexes); err != nil {
			t.Fatal(err)
		}
		if indexes != 1 {
			t.Fatalf("index %s missing", index)
		}
	}
}

// TestMigrationUpgradesLegacyTableAndExpiresPermanentSessions 验证旧迁移表可原位升级，且历史永久会话获得有限期限。
func TestMigrationUpgradesLegacyTableAndExpiresPermanentSessions(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "legacy-migrations.db")
	db, err := sql.Open("sqlite", "file:"+escapeSQLitePath(path)+"?_pragma=foreign_keys(1)")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at_ms INTEGER NOT NULL)`); err != nil {
		t.Fatal(err)
	}
	for _, item := range allMigrations[:19] {
		if _, err := db.Exec(item.sql); err != nil {
			t.Fatalf("apply %s: %v", item.name, err)
		}
		if _, err := db.Exec(`INSERT INTO schema_migrations(version, applied_at_ms) VALUES(?, 1)`, item.version); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`INSERT INTO users(id,name,role,enabled,created_at_ms,updated_at_ms)
		VALUES('legacy_user','旧用户','member',1,1,1)`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO sessions(
		id,user_id,name,secret_hash,secret_prefix,expires_at_ms,created_at_ms,updated_at_ms
	) VALUES('legacy_session','legacy_user','旧设备','hash','prefix',NULL,1,1)`); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	started := time.Now().UTC()
	upgraded, err := Open(ctx, config.DatabaseConfig{Path: path, BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer upgraded.Close()
	var checksummed, version int
	if err := upgraded.QueryRow(`SELECT COUNT(*), MAX(version) FROM schema_migrations
		WHERE checksum IS NOT NULL AND checksum <> ''`).Scan(&checksummed, &version); err != nil {
		t.Fatal(err)
	}
	if checksummed != len(allMigrations) || version != 20 {
		t.Fatalf("checksummed=%d version=%d", checksummed, version)
	}
	var expiresAt int64
	if err := upgraded.QueryRow(`SELECT expires_at_ms FROM sessions WHERE id='legacy_session'`).Scan(&expiresAt); err != nil {
		t.Fatal(err)
	}
	expires := time.UnixMilli(expiresAt).UTC()
	if expires.Before(started.Add(29*24*time.Hour)) || expires.After(time.Now().UTC().Add(31*24*time.Hour)) {
		t.Fatalf("legacy session expiry = %s", expires)
	}
}

// TestMigrationRejectsTamperedChecksum 验证启动会拒绝被改写或清空的历史迁移记录。
func TestMigrationRejectsTamperedChecksum(t *testing.T) {
	for _, test := range []struct {
		name     string
		checksum any
		message  string
	}{
		{name: "changed", checksum: "tampered", message: "checksum mismatch"},
		{name: "cleared", checksum: "", message: "checksum is missing"},
	} {
		t.Run(test.name, func(t *testing.T) {
			ctx := context.Background()
			path := filepath.Join(t.TempDir(), "tampered-migration.db")
			db, err := Open(ctx, config.DatabaseConfig{Path: path, BusyTimeoutMS: 1000})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := db.Exec(`UPDATE schema_migrations SET checksum=? WHERE version=1`, test.checksum); err != nil {
				t.Fatal(err)
			}
			if err := db.Close(); err != nil {
				t.Fatal(err)
			}

			if _, err := Open(ctx, config.DatabaseConfig{Path: path, BusyTimeoutMS: 1000}); err == nil || !strings.Contains(err.Error(), test.message) {
				t.Fatalf("tampered migration error = %v", err)
			}
		})
	}
}

// TestSourceDeletePurgesOnlyUninitializedSource 验证补偿可清除空来源授权，同时保留已有索引来源的软删除历史。
func TestSourceDeletePurgesOnlyUninitializedSource(t *testing.T) {
	ctx := context.Background()
	db, err := Open(ctx, config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "source-delete.db"), BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	repository, err := NewSourceRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	for _, id := range []string{"empty", "indexed"} {
		if err := repository.Create(ctx, domain.Source{
			ID: id, Name: id, Type: domain.SourceTypeLocal, LibraryKind: domain.LibraryKindPersonal,
			RootPath: "/" + id, Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`INSERT INTO media_items(
		id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,
		discovered_at_ms,created_at_ms,updated_at_ms
	) VALUES('media','indexed','movie.mkv','movie.mkv','video',1,1,'ready',1,1,1)`); err != nil {
		t.Fatal(err)
	}
	if err := repository.SoftDelete(ctx, "empty", now); err != nil {
		t.Fatal(err)
	}
	if err := repository.SoftDelete(ctx, "indexed", now); err != nil {
		t.Fatal(err)
	}
	var emptySources, emptyGrants, indexedSources int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sources WHERE id='empty'`).Scan(&emptySources); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM source_grants WHERE source_id='empty'`).Scan(&emptyGrants); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM sources WHERE id='indexed' AND deleted_at_ms IS NOT NULL`).Scan(&indexedSources); err != nil {
		t.Fatal(err)
	}
	if emptySources != 0 || emptyGrants != 0 || indexedSources != 1 {
		t.Fatalf("empty sources=%d grants=%d indexed soft-deleted=%d", emptySources, emptyGrants, indexedSources)
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
