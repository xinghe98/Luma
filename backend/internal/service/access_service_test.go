package service

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
	dbrepo "github.com/xinghe98/Luma/backend/internal/repository/sqlite"
)

// TestAccessServiceIdempotentWritesReplayWithoutDuplicating 验证账号、会话和安全状态变更的完整流程。
func TestAccessServiceIdempotentWritesReplayWithoutDuplicating(t *testing.T) {
	ctx := context.Background()
	db, err := dbrepo.Open(ctx, config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "access.db"), BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	repository, err := dbrepo.NewAccessRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	ids := &accessServiceIDs{}
	clock := accessServiceClock{now: time.Date(2026, 7, 22, 0, 0, 0, 0, time.UTC)}
	service, err := NewAccessService(repository, ids, clock, 30*24*time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	firstUser, err := service.CreateUserIdempotent(ctx, "Alice", "alice", "correct horse battery", "create-1")
	if err != nil {
		t.Fatal(err)
	}
	secondUser, err := service.CreateUserIdempotent(ctx, "Alice", "alice", "ignored-password", "create-1")
	if err != nil || secondUser.ID != firstUser.ID {
		t.Fatalf("replayed user=%#v error=%v", secondUser, err)
	}
	users, err := service.ListUsers(ctx)
	if err != nil || len(users) != 2 { // local administrator + Alice
		t.Fatalf("users=%#v error=%v", users, err)
	}

	firstSession, err := service.Login(ctx, "alice", "correct horse battery", "Alice phone", "install-key-1")
	if err != nil {
		t.Fatal(err)
	}
	if firstSession.Session.UserID != firstUser.ID || firstSession.Secret == "" {
		t.Fatalf("session=%#v", firstSession)
	}
	if firstSession.Session.ExpiresAt == nil || !firstSession.Session.ExpiresAt.Equal(clock.now.Add(30*24*time.Hour)) {
		t.Fatalf("session expires at %v", firstSession.Session.ExpiresAt)
	}
	sessions, err := service.ListSessions(ctx, firstUser.ID)
	if err != nil || len(sessions) != 1 {
		t.Fatalf("sessions=%#v error=%v", sessions, err)
	}

	// 同 device_key 重登应顶替旧会话，列表只保留一条活跃设备。
	secondSession, err := service.Login(ctx, "alice", "correct horse battery", "Alice phone · user", "install-key-1")
	if err != nil {
		t.Fatal(err)
	}
	if secondSession.Session.ID == firstSession.Session.ID {
		t.Fatal("expected a new session id after re-login")
	}
	sessions, err = service.ListSessions(ctx, firstUser.ID)
	if err != nil || len(sessions) != 1 {
		t.Fatalf("after re-login sessions=%#v error=%v", sessions, err)
	}
	if sessions[0].ID != secondSession.Session.ID || sessions[0].Name != "Alice phone · user" {
		t.Fatalf("active session=%#v", sessions[0])
	}
	if err := service.RevokeSession(ctx, secondSession.Session.ID); err != nil {
		t.Fatal(err)
	}
	sessions, err = service.ListSessions(ctx, firstUser.ID)
	if err != nil || len(sessions) != 0 {
		t.Fatalf("revoked sessions should be hidden: %#v error=%v", sessions, err)
	}
	if _, err := service.Login(ctx, "alice", "correct horse battery", "Alice phone", "install-key-1"); err != nil {
		t.Fatal(err)
	}
	if err := service.ResetPassword(ctx, firstUser.ID, "new correct password"); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Login(ctx, "alice", "correct horse battery", "Alice phone", "install-key-1"); !errors.Is(err, domain.ErrUnauthorized) {
		t.Fatalf("old password login error=%v", err)
	}
	if _, err := service.Login(ctx, "alice", "new correct password", "Alice phone", "install-key-1"); err != nil {
		t.Fatal(err)
	}
	disabled := false
	if _, err := service.UpdateUser(ctx, firstUser.ID, nil, &disabled); err != nil {
		t.Fatal(err)
	}
	sessions, err = service.ListSessions(ctx, firstUser.ID)
	if err != nil || len(sessions) != 0 {
		t.Fatalf("disabled user sessions=%#v error=%v", sessions, err)
	}
}

func TestAccessServiceIncludesObservedOnlineState(t *testing.T) {
	ctx := context.Background()
	db, err := dbrepo.Open(ctx, config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "presence.db"), BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	repository, err := dbrepo.NewAccessRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	ids := &accessServiceIDs{}
	clock := accessServiceClock{now: time.Date(2026, 7, 23, 8, 0, 0, 0, time.UTC)}
	presence := accessServicePresence{online: map[string]bool{"user-1": true}}
	service, err := NewAccessService(repository, ids, clock, 30*24*time.Hour, presence)
	if err != nil {
		t.Fatal(err)
	}
	user, err := service.CreateUser(ctx, "Alice", "alice", "correct horse battery")
	if err != nil {
		t.Fatal(err)
	}
	presence.online[user.ID] = true

	users, err := service.ListUsers(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, listed := range users {
		if listed.ID == user.ID && listed.Online {
			return
		}
	}
	t.Fatalf("online user %q was not returned as online: %#v", user.ID, users)
}

type accessServiceIDs struct{ next int }

func (g *accessServiceIDs) New(prefix string) (string, error) {
	g.next++
	return fmt.Sprintf("%s-%d", prefix, g.next), nil
}

type accessServiceClock struct{ now time.Time }

func (c accessServiceClock) Now() time.Time { return c.now }

type accessServicePresence struct{ online map[string]bool }

func (p accessServicePresence) IsOnline(userID string) bool {
	return p.online[userID]
}
