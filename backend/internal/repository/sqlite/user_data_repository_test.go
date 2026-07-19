package sqlite

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestUserDataRepositoryUpdatesAtomicallyAndPreservesMetadataOnProgress(t *testing.T) {
	mediaRepository, sources := newMediaRepositoryTest(t)
	ctx := context.Background()
	now := time.UnixMilli(1000).UTC()
	if err := sources.Create(ctx, domain.Source{
		ID: "source", Name: "源", Type: domain.SourceTypeLocal, RootPath: "/media",
		Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	duration := int64(100000)
	insertMedia(t, mediaRepository, "media", "source", "clip.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1000, &duration)
	userData, err := NewUserDataRepository(mediaRepository.db)
	if err != nil {
		t.Fatal(err)
	}
	tags, err := NewTagRepository(mediaRepository.db)
	if err != nil {
		t.Fatal(err)
	}
	for _, tag := range []domain.Tag{
		{ID: "tag_a", UserID: "user_local", Name: "A", NormalizedName: "a", Revision: 1, CreatedAt: now, UpdatedAt: now},
		{ID: "tag_b", UserID: "user_local", Name: "B", NormalizedName: "b", Revision: 1, CreatedAt: now, UpdatedAt: now},
	} {
		if err := tags.Create(ctx, tag); err != nil {
			t.Fatal(err)
		}
	}
	initial, err := userData.Get(ctx, "user_local", "media")
	if err != nil || initial.Revision != 0 || len(initial.Tags) != 0 {
		t.Fatalf("initial=%#v err=%v", initial, err)
	}
	title, note, favorite := "自定义标题", "笔记", true
	tagIDs := []string{"tag_a", "tag_b"}
	updated, err := userData.Update(ctx, domain.UpdateUserDataCommand{
		UserID: "user_local", MediaID: "media", BaseRevision: 0,
		CustomTitle: domain.PatchField[string]{Set: true, Value: &title},
		Favorite:    domain.PatchField[bool]{Set: true, Value: &favorite},
		Notes:       domain.PatchField[string]{Set: true, Value: &note},
		TagIDs:      domain.PatchField[[]string]{Set: true, Value: &tagIDs},
	}, time.UnixMilli(2000))
	if err != nil {
		t.Fatal(err)
	}
	if updated.Revision != 1 || !updated.Favorite || len(updated.Tags) != 2 || updated.Tags[0].UsageCount != 1 || updated.CustomTitle == nil || *updated.CustomTitle != title {
		t.Fatalf("updated=%#v", updated)
	}

	badTitle := "不应保存"
	missingTags := []string{"tag_missing"}
	_, err = userData.Update(ctx, domain.UpdateUserDataCommand{
		UserID: "user_local", MediaID: "media", BaseRevision: 1,
		CustomTitle: domain.PatchField[string]{Set: true, Value: &badTitle},
		TagIDs:      domain.PatchField[[]string]{Set: true, Value: &missingTags},
	}, time.UnixMilli(3000))
	if !errors.Is(err, domain.ErrTagNotFound) {
		t.Fatalf("error=%v", err)
	}
	afterRollback, err := userData.Get(ctx, "user_local", "media")
	if err != nil || afterRollback.Revision != 1 || *afterRollback.CustomTitle != title || len(afterRollback.Tags) != 2 {
		t.Fatalf("after rollback=%#v err=%v", afterRollback, err)
	}

	progress, err := userData.UpdateProgress(ctx, domain.UpdateProgressCommand{
		UserID: "user_local", MediaID: "media", PositionMS: 90000,
		BaseRevision: 1, Now: time.UnixMilli(4000),
	})
	if err != nil {
		t.Fatal(err)
	}
	if progress.Revision != 2 || progress.ProgressMS != 90000 || !progress.Completed || !progress.Favorite ||
		progress.CustomTitle == nil || *progress.CustomTitle != title || len(progress.Tags) != 2 {
		t.Fatalf("progress=%#v", progress)
	}
	if _, err := userData.UpdateProgress(ctx, domain.UpdateProgressCommand{
		UserID: "user_local", MediaID: "media", PositionMS: 1, BaseRevision: 1, Now: time.UnixMilli(5000),
	}); !errors.Is(err, domain.ErrRevisionConflict) {
		t.Fatalf("stale progress error=%v", err)
	}

	clamped, err := userData.UpdateProgress(ctx, domain.UpdateProgressCommand{
		UserID: "user_local", MediaID: "media", PositionMS: 200000,
		BaseRevision: 2, Now: time.UnixMilli(6000),
	})
	if err != nil {
		t.Fatal(err)
	}
	if clamped.ProgressMS != duration || !clamped.Completed {
		t.Fatalf("clamped=%#v", clamped)
	}

	insertMedia(t, mediaRepository, "image", "source", "photo.jpg", domain.MediaTypeImage, domain.MediaStatusReady, 1000, nil)
	if _, err := userData.UpdateProgress(ctx, domain.UpdateProgressCommand{
		UserID: "user_local", MediaID: "image", PositionMS: 1, BaseRevision: 0, Now: time.UnixMilli(7000),
	}); !errors.Is(err, domain.ErrMediaNotPlayable) {
		t.Fatalf("image progress error=%v", err)
	}

	insertMedia(t, mediaRepository, "no_duration", "source", "pending.mp4", domain.MediaTypeVideo, domain.MediaStatusDiscovered, 1000, nil)
	if _, err := userData.UpdateProgress(ctx, domain.UpdateProgressCommand{
		UserID: "user_local", MediaID: "no_duration", PositionMS: 1, BaseRevision: 0, Now: time.UnixMilli(8000),
	}); !errors.Is(err, domain.ErrMediaDurationUnavailable) {
		t.Fatalf("missing duration error=%v", err)
	}
}
