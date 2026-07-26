package sqlite

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestMemberGrantScopesListAndDirectMediaAccess(t *testing.T) {
	media, sources := newMediaRepositoryTest(t)
	access, err := NewAccessRepository(media.db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	now := time.UnixMilli(1000).UTC()
	if err := access.CreateUser(ctx, domain.User{
		ID: "user_member", Name: "成员", Role: domain.RoleMember, Enabled: true,
		CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	for _, source := range []domain.Source{
		{ID: "source_a", Name: "A", Type: domain.SourceTypeLocal, RootPath: "/a", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now},
		{ID: "source_b", Name: "B", Type: domain.SourceTypeLocal, RootPath: "/b", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now},
	} {
		if err := sources.Create(ctx, source); err != nil {
			t.Fatal(err)
		}
	}
	insertMedia(t, media, "media_a", "source_a", "a.jpg", domain.MediaTypeImage, domain.MediaStatusReady, 1000, nil)
	insertMedia(t, media, "media_b", "source_b", "b.jpg", domain.MediaTypeImage, domain.MediaStatusReady, 1000, nil)
	if err := access.GrantSource(ctx, "user_member", "source_a", now); err != nil {
		t.Fatal(err)
	}

	items, err := media.List(ctx, domain.MediaListQuery{
		UserID: "user_member", MediaType: domain.MediaTypeImage,
		Sort: domain.MediaSortCreatedAt, Order: domain.SortDescending, Limit: 20,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].ID != "media_a" {
		t.Fatalf("member list = %#v", items)
	}
	if _, err := media.Get(ctx, "media_b", "user_member"); !errors.Is(err, domain.ErrMediaNotFound) {
		t.Fatalf("direct access outside grant error = %v", err)
	}
	if _, err := media.GetStreamLocation(ctx, "media_b", "user_member"); !errors.Is(err, domain.ErrMediaNotFound) {
		t.Fatalf("stream outside grant error = %v", err)
	}
}

// TestAccessRepositorySecurityUpdatesRollbackWithSessionRevocation 验证会话撤销失败时敏感更新整体回滚。
func TestAccessRepositorySecurityUpdatesRollbackWithSessionRevocation(t *testing.T) {
	media, _ := newMediaRepositoryTest(t)
	access, err := NewAccessRepository(media.db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	now := time.UnixMilli(1000).UTC()
	user := domain.User{
		ID: "user_member", Name: "成员", Username: "member", PasswordHash: "old-hash",
		Role: domain.RoleMember, Enabled: true, CreatedAt: now, UpdatedAt: now,
	}
	if err := access.CreateUser(ctx, user); err != nil {
		t.Fatal(err)
	}
	if err := access.ReplaceSession(ctx, domain.Session{
		ID: "session", UserID: user.ID, Name: "设备", DeviceKey: "device",
		SecretHash: "secret-hash", SecretPrefix: "secret", CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := media.db.Exec(`CREATE TRIGGER reject_session_revoke BEFORE UPDATE OF revoked_at_ms ON sessions
		WHEN NEW.revoked_at_ms IS NOT NULL BEGIN SELECT RAISE(ABORT, 'blocked'); END`); err != nil {
		t.Fatal(err)
	}
	if err := access.ResetPassword(ctx, user.ID, "new-hash", now.Add(time.Second)); err == nil {
		t.Fatal("password reset should fail when session revocation fails")
	}
	var passwordHash string
	var revokedAt any
	if err := media.db.QueryRow(`SELECT password_hash FROM users WHERE id=?`, user.ID).Scan(&passwordHash); err != nil {
		t.Fatal(err)
	}
	if err := media.db.QueryRow(`SELECT revoked_at_ms FROM sessions WHERE id='session'`).Scan(&revokedAt); err != nil {
		t.Fatal(err)
	}
	if passwordHash != "old-hash" || revokedAt != nil {
		t.Fatalf("password=%q revoked_at=%v", passwordHash, revokedAt)
	}
	user.Enabled = false
	user.UpdatedAt = now.Add(2 * time.Second)
	if err := access.UpdateUser(ctx, user); err == nil {
		t.Fatal("user update should fail when session revocation fails")
	}
	var enabled int
	if err := media.db.QueryRow(`SELECT enabled FROM users WHERE id=?`, user.ID).Scan(&enabled); err != nil {
		t.Fatal(err)
	}
	if enabled != 1 {
		t.Fatalf("enabled=%d, want rollback to 1", enabled)
	}
}

// TestAccessRepositoryConcurrentDeviceReplacementKeepsOneActiveSession 验证并发同设备登录仅保留一个有效会话。
func TestAccessRepositoryConcurrentDeviceReplacementKeepsOneActiveSession(t *testing.T) {
	media, _ := newMediaRepositoryTest(t)
	access, err := NewAccessRepository(media.db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	now := time.UnixMilli(1000).UTC()
	user := domain.User{ID: "user_member", Name: "成员", Role: domain.RoleMember, Enabled: true, CreatedAt: now, UpdatedAt: now}
	if err := access.CreateUser(ctx, user); err != nil {
		t.Fatal(err)
	}
	const workers = 16
	start := make(chan struct{})
	errorsByWorker := make(chan error, workers)
	var group sync.WaitGroup
	for index := 0; index < workers; index++ {
		group.Add(1)
		go func(index int) {
			defer group.Done()
			<-start
			timestamp := now.Add(time.Duration(index) * time.Millisecond)
			errorsByWorker <- access.ReplaceSession(ctx, domain.Session{
				ID: fmt.Sprintf("session-%d", index), UserID: user.ID, Name: "设备", DeviceKey: "same-device",
				SecretHash: fmt.Sprintf("secret-%d", index), SecretPrefix: "secret", CreatedAt: timestamp, UpdatedAt: timestamp,
			})
		}(index)
	}
	close(start)
	group.Wait()
	close(errorsByWorker)
	for err := range errorsByWorker {
		if err != nil {
			t.Fatal(err)
		}
	}
	var active, total int
	if err := media.db.QueryRow(`SELECT COUNT(*) FROM sessions WHERE user_id=? AND device_key='same-device'
		AND revoked_at_ms IS NULL`, user.ID).Scan(&active); err != nil {
		t.Fatal(err)
	}
	if err := media.db.QueryRow(`SELECT COUNT(*) FROM sessions WHERE user_id=? AND device_key='same-device'`, user.ID).Scan(&total); err != nil {
		t.Fatal(err)
	}
	if active != 1 || total != workers {
		t.Fatalf("active=%d total=%d", active, total)
	}
}
