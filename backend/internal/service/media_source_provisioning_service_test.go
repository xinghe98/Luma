package service

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestManagedSourceCreationDoesNotWriteConfiguredRoots(t *testing.T) {
	store, err := config.NewAllowedRootsStore(filepath.Join(t.TempDir(), "missing-config.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	sources := &provisioningSources{}
	service, err := NewManagedMediaSourceService(sources, provisioningAccess{}, provisioningScans{}, store)
	if err != nil {
		t.Fatal(err)
	}

	created, err := service.Create(context.Background(), ManagedMediaSourceCommand{
		Name: "家庭影片", RootPath: "/media/family", LibraryKind: domain.LibraryKindPersonal,
	})
	if err != nil {
		t.Fatal(err)
	}
	if sources.command.RootPath != "/media/family" || created.Source.ID != "source_test" {
		t.Fatalf("command=%#v created=%#v", sources.command, created)
	}
}

type provisioningSources struct {
	command domain.CreateSourceCommand
}

func (s *provisioningSources) Create(_ context.Context, command domain.CreateSourceCommand) (domain.Source, error) {
	s.command = command
	return domain.Source{ID: "source_test"}, nil
}

func (*provisioningSources) Delete(context.Context, string) error { return nil }

type provisioningAccess struct{}

func (provisioningAccess) GrantSource(context.Context, string, string) error { return nil }

type provisioningScans struct{}

func (provisioningScans) Start(context.Context, string) (domain.ScanJob, error) {
	return domain.ScanJob{ID: "scan_test"}, nil
}
