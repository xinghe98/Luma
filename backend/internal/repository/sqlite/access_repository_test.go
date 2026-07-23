package sqlite

import (
	"context"
	"errors"
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
