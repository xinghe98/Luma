package service

import (
	"context"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type fakeTagRepository struct {
	created domain.Tag
	updated domain.Tag
}

func (*fakeTagRepository) List(context.Context, string) ([]domain.Tag, error) { return nil, nil }
func (r *fakeTagRepository) Create(_ context.Context, tag domain.Tag) error {
	r.created = tag
	return nil
}
func (r *fakeTagRepository) Update(_ context.Context, tag domain.Tag, _ int64) (domain.Tag, error) {
	r.updated = tag
	return tag, nil
}
func (*fakeTagRepository) Delete(context.Context, string, string, time.Time) error { return nil }

func TestTagServiceNormalizesUnicodeAndUsesRevision(t *testing.T) {
	repository := &fakeTagRepository{}
	service, err := NewTagService(repository, fakeIDGenerator{}, fakeClock{})
	if err != nil {
		t.Fatal(err)
	}
	tag, err := service.Create(context.Background(), domain.CreateTagCommand{UserID: "user", Name: " Ｓｔｒａße "})
	if err != nil {
		t.Fatal(err)
	}
	if tag.ID != "tag_test" || repository.created.NormalizedName != "strasse" || repository.created.Name != "Straße" {
		t.Fatalf("tag=%#v created=%#v", tag, repository.created)
	}
	updated, err := service.Update(context.Background(), domain.UpdateTagCommand{UserID: "user", ID: "tag", Name: "旅行", BaseRevision: 2})
	if err != nil {
		t.Fatal(err)
	}
	if updated.Revision != 3 || repository.updated.NormalizedName != "旅行" {
		t.Fatalf("updated=%#v", updated)
	}
}
