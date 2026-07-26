package service

import (
	"context"
	"errors"
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
	service, err := NewManagedMediaSourceService(sources, &provisioningAccess{}, provisioningScans{}, store)
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

// TestManagedSourceCreationCompensatesGrantFailure 验证授权失败不会留下可用来源或已授予权限。
func TestManagedSourceCreationCompensatesGrantFailure(t *testing.T) {
	store, err := config.NewAllowedRootsStore(filepath.Join(t.TempDir(), "missing-config.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	sources := &provisioningSources{}
	access := &provisioningAccess{grants: map[string]bool{}, failGrant: "user_b"}
	managed, err := NewManagedMediaSourceService(sources, access, provisioningScans{}, store)
	if err != nil {
		t.Fatal(err)
	}

	_, err = managed.Create(context.Background(), ManagedMediaSourceCommand{
		Name: "家庭影片", RootPath: "/media/family", LibraryKind: domain.LibraryKindPersonal,
		UserIDs: []string{"user_a", "user_b", "user_a"},
	})
	if !errors.Is(err, errProvisioningGrant) {
		t.Fatalf("creation error = %v", err)
	}
	if !sources.deleted || len(access.grants) != 0 {
		t.Fatalf("deleted=%v grants=%v", sources.deleted, access.grants)
	}
}

// TestManagedSourceCreationCompensatesScanFailure 验证首次扫描失败会清理全部初始授权和来源。
func TestManagedSourceCreationCompensatesScanFailure(t *testing.T) {
	store, err := config.NewAllowedRootsStore(filepath.Join(t.TempDir(), "missing-config.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	sources := &provisioningSources{}
	access := &provisioningAccess{grants: map[string]bool{}}
	managed, err := NewManagedMediaSourceService(sources, access, provisioningScans{err: errProvisioningScan}, store)
	if err != nil {
		t.Fatal(err)
	}

	_, err = managed.Create(context.Background(), ManagedMediaSourceCommand{
		Name: "电影", RootPath: "/media/movies", LibraryKind: domain.LibraryKindMovies,
		UserIDs: []string{"user_a", "user_b"},
	})
	if !errors.Is(err, errProvisioningScan) {
		t.Fatalf("creation error = %v", err)
	}
	if !sources.deleted || len(access.grants) != 0 {
		t.Fatalf("deleted=%v grants=%v", sources.deleted, access.grants)
	}
}

var (
	errProvisioningGrant = errors.New("grant failed")
	errProvisioningScan  = errors.New("scan failed")
)

type provisioningSources struct {
	command domain.CreateSourceCommand
	deleted bool
}

func (s *provisioningSources) Create(_ context.Context, command domain.CreateSourceCommand) (domain.Source, error) {
	s.command = command
	return domain.Source{ID: "source_test"}, nil
}

func (s *provisioningSources) Delete(context.Context, string) error {
	s.deleted = true
	return nil
}

type provisioningAccess struct {
	grants    map[string]bool
	failGrant string
}

func (a *provisioningAccess) GrantSource(_ context.Context, userID, _ string) error {
	if a.grants == nil {
		a.grants = map[string]bool{}
	}
	if userID == a.failGrant {
		return errProvisioningGrant
	}
	a.grants[userID] = true
	return nil
}

func (a *provisioningAccess) RevokeSource(_ context.Context, userID, _ string) error {
	delete(a.grants, userID)
	return nil
}

type provisioningScans struct{ err error }

func (s provisioningScans) Start(context.Context, string) (domain.ScanJob, error) {
	return domain.ScanJob{ID: "scan_test"}, s.err
}
