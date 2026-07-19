package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type fakeUserDataRepository struct {
	updated  domain.UpdateUserDataCommand
	progress domain.UpdateProgressCommand
	result   domain.MediaUserData
	err      error
}

func (r *fakeUserDataRepository) Get(context.Context, string, string) (domain.MediaUserData, error) {
	return r.result, r.err
}
func (r *fakeUserDataRepository) Update(_ context.Context, command domain.UpdateUserDataCommand, _ time.Time) (domain.MediaUserData, error) {
	r.updated = command
	return r.result, r.err
}
func (r *fakeUserDataRepository) UpdateProgress(_ context.Context, command domain.UpdateProgressCommand) (domain.MediaUserData, error) {
	r.progress = command
	return r.result, r.err
}

func TestUserDataServiceValidatesPatchAndProgress(t *testing.T) {
	repository := &fakeUserDataRepository{result: domain.MediaUserData{Revision: 1, ProgressMS: 90000, Completed: true}}
	service, err := NewUserDataService(repository, fakeClock{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Update(context.Background(), domain.UpdateUserDataCommand{UserID: "user", MediaID: "media"}); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("empty patch error=%v", err)
	}
	duplicate := []string{"tag", " tag "}
	if _, err := service.Update(context.Background(), domain.UpdateUserDataCommand{
		UserID: "user", MediaID: "media", TagIDs: domain.PatchField[[]string]{Set: true, Value: &duplicate},
	}); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("duplicate tags error=%v", err)
	}
	emptyNote := ""
	if _, err := service.Update(context.Background(), domain.UpdateUserDataCommand{
		UserID: "user", MediaID: "media", Notes: domain.PatchField[string]{Set: true, Value: &emptyNote},
	}); err != nil {
		t.Fatal(err)
	}
	if repository.updated.Notes.Value == nil || *repository.updated.Notes.Value != "" {
		t.Fatalf("empty note patch=%#v", repository.updated.Notes)
	}
	if _, err := service.UpdateProgress(context.Background(), "user", "media", 90000, 0); err != nil {
		t.Fatal(err)
	}
	if repository.progress.PositionMS != 90000 || repository.progress.BaseRevision != 0 {
		t.Fatalf("progress=%#v", repository.progress)
	}
	if _, err := service.UpdateProgress(context.Background(), "user", "media", -1, 0); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("negative progress error=%v", err)
	}
}
