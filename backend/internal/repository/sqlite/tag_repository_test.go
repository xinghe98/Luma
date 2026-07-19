package sqlite

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestTagRepositoryConflictRevisionAndCascade(t *testing.T) {
	mediaRepository, sources := newMediaRepositoryTest(t)
	ctx := context.Background()
	now := time.UnixMilli(1000).UTC()
	if err := sources.Create(ctx, domain.Source{ID: "source", Name: "源", Type: domain.SourceTypeLocal, RootPath: "/media", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now}); err != nil {
		t.Fatal(err)
	}
	insertMedia(t, mediaRepository, "media", "source", "clip.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1000, nil)
	tags, err := NewTagRepository(mediaRepository.db)
	if err != nil {
		t.Fatal(err)
	}
	tag := domain.Tag{ID: "tag", UserID: "user_local", Name: "旅行", NormalizedName: "旅行", Revision: 1, CreatedAt: now, UpdatedAt: now}
	if err := tags.Create(ctx, tag); err != nil {
		t.Fatal(err)
	}
	duplicate := tag
	duplicate.ID = "tag_2"
	if err := tags.Create(ctx, duplicate); !errors.Is(err, domain.ErrTagConflict) {
		t.Fatalf("duplicate error=%v", err)
	}
	if _, err := mediaRepository.db.Exec(`INSERT INTO media_user_data(
        user_id,media_id,created_at_ms,updated_at_ms,revision
    ) VALUES('user_local','media',1,1,1)`); err != nil {
		t.Fatal(err)
	}
	if _, err := mediaRepository.db.Exec(`INSERT INTO media_tags(user_id, media_id, tag_id, created_at_ms) VALUES('user_local','media','tag',1)`); err != nil {
		t.Fatal(err)
	}
	tag.Name, tag.NormalizedName, tag.UpdatedAt = "出游", "出游", time.UnixMilli(2000)
	updated, err := tags.Update(ctx, tag, 1)
	if err != nil || updated.Revision != 2 || updated.UsageCount != 1 || updated.CreatedAt.UnixMilli() != 1000 {
		t.Fatalf("updated=%#v err=%v", updated, err)
	}
	if _, err := tags.Update(ctx, tag, 1); !errors.Is(err, domain.ErrRevisionConflict) {
		t.Fatalf("stale error=%v", err)
	}
	if err := tags.Delete(ctx, "user_local", "tag", time.UnixMilli(3000)); err != nil {
		t.Fatal(err)
	}
	var mediaCount, relationCount int
	var userDataRevision, updatedMS int64
	if err := mediaRepository.db.QueryRow(`SELECT COUNT(*) FROM media_items WHERE id='media'`).Scan(&mediaCount); err != nil {
		t.Fatal(err)
	}
	if err := mediaRepository.db.QueryRow(`SELECT COUNT(*) FROM media_tags WHERE tag_id='tag'`).Scan(&relationCount); err != nil {
		t.Fatal(err)
	}
	if err := mediaRepository.db.QueryRow(`SELECT revision, updated_at_ms FROM media_user_data
        WHERE user_id='user_local' AND media_id='media'`).Scan(&userDataRevision, &updatedMS); err != nil {
		t.Fatal(err)
	}
	if mediaCount != 1 || relationCount != 0 || userDataRevision != 2 || updatedMS != 3000 {
		t.Fatalf("media=%d relations=%d revision=%d updated=%d", mediaCount, relationCount, userDataRevision, updatedMS)
	}
}
