package service

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	dbrepo "github.com/xinghe98/Luma/backend/internal/repository/sqlite"
)

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
	service, err := NewAccessService(repository, ids, clock)
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

	firstSession, err := service.Login(ctx, "alice", "correct horse battery", "Alice phone")
	if err != nil {
		t.Fatal(err)
	}
	if err != nil || firstSession.Session.UserID != firstUser.ID || firstSession.Secret == "" {
		t.Fatalf("session=%#v error=%v", firstSession, err)
	}
	sessions, err := service.ListSessions(ctx, firstUser.ID)
	if err != nil || len(sessions) != 1 {
		t.Fatalf("sessions=%#v error=%v", sessions, err)
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
	service, err := NewAccessService(repository, ids, clock, presence)
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
