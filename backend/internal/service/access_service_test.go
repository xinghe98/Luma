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

	firstUser, err := service.CreateUserIdempotent(ctx, "Alice", "create-1")
	if err != nil {
		t.Fatal(err)
	}
	secondUser, err := service.CreateUserIdempotent(ctx, "Alice", "create-1")
	if err != nil || secondUser.ID != firstUser.ID {
		t.Fatalf("replayed user=%#v error=%v", secondUser, err)
	}
	users, err := service.ListUsers(ctx)
	if err != nil || len(users) != 2 { // local administrator + Alice
		t.Fatalf("users=%#v error=%v", users, err)
	}

	firstToken, err := service.IssueTokenIdempotent(ctx, firstUser.ID, "Alice phone", nil, "token-1")
	if err != nil {
		t.Fatal(err)
	}
	secondToken, err := service.IssueTokenIdempotent(ctx, firstUser.ID, "Alice phone", nil, "token-1")
	if err != nil || secondToken.Token.ID != firstToken.Token.ID || secondToken.Secret != firstToken.Secret {
		t.Fatalf("replayed token=%#v error=%v", secondToken, err)
	}
	tokens, err := service.ListTokens(ctx, firstUser.ID)
	if err != nil || len(tokens) != 1 {
		t.Fatalf("tokens=%#v error=%v", tokens, err)
	}

	// A new process can still locate the original token, but must never invent a
	// second one because the one-time plaintext is intentionally not persisted.
	afterRestart, err := NewAccessService(repository, ids, clock)
	if err != nil {
		t.Fatal(err)
	}
	replayed, err := afterRestart.IssueTokenIdempotent(ctx, firstUser.ID, "Alice phone", nil, "token-1")
	if !errors.Is(err, domain.ErrIdempotencySecretUnavailable) || replayed.Token.ID != firstToken.Token.ID || replayed.Secret != "" {
		t.Fatalf("restart replay=%#v error=%v", replayed, err)
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
	user, err := service.CreateUser(ctx, "Alice")
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
