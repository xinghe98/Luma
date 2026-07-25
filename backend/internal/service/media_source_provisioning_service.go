package service

import (
	"context"
	"errors"
	"strings"
	"sync"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

type ManagedMediaSourceCommand struct {
	Name        string
	RootPath    string
	LibraryKind string
	UserIDs     []string
}

type ManagedMediaSourceResult struct {
	Source domain.Source
	Scan   domain.ScanJob
}

type provisionedSourceUseCase interface {
	Create(context.Context, domain.CreateSourceCommand) (domain.Source, error)
	Delete(context.Context, string) error
}

type provisionedAccessUseCase interface {
	GrantSource(context.Context, string, string) error
}

type provisionedScanUseCase interface {
	Start(context.Context, string) (domain.ScanJob, error)
}

type ManagedMediaSourceService struct {
	sources provisionedSourceUseCase
	access  provisionedAccessUseCase
	scans   provisionedScanUseCase
	config  *config.AllowedRootsStore
	mu      sync.Mutex
}

func NewManagedMediaSourceService(
	sources provisionedSourceUseCase,
	access provisionedAccessUseCase,
	scans provisionedScanUseCase,
	store *config.AllowedRootsStore,
) (*ManagedMediaSourceService, error) {
	if sources == nil || access == nil || scans == nil || store == nil {
		return nil, errors.New("新增媒体源服务依赖不能为空")
	}
	return &ManagedMediaSourceService{sources: sources, access: access, scans: scans, config: store}, nil
}

func (s *ManagedMediaSourceService) ListAvailableRoots() ([]string, error) {
	return s.config.List()
}

func (s *ManagedMediaSourceService) Create(ctx context.Context, command ManagedMediaSourceCommand) (ManagedMediaSourceResult, error) {
	if err := ctx.Err(); err != nil {
		return ManagedMediaSourceResult{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	source, err := s.sources.Create(ctx, domain.CreateSourceCommand{
		Name: command.Name, RootPath: command.RootPath, LibraryKind: command.LibraryKind,
	})
	if err != nil {
		return ManagedMediaSourceResult{}, err
	}
	rollbackSource := func(cause error) error {
		deleteErr := s.sources.Delete(context.Background(), source.ID)
		return errors.Join(cause, deleteErr)
	}
	for _, userID := range uniqueIDs(command.UserIDs) {
		if err := s.access.GrantSource(ctx, userID, source.ID); err != nil {
			return ManagedMediaSourceResult{}, rollbackSource(err)
		}
	}
	job, err := s.scans.Start(ctx, source.ID)
	if err != nil {
		return ManagedMediaSourceResult{}, rollbackSource(err)
	}
	return ManagedMediaSourceResult{Source: source, Scan: job}, nil
}

func uniqueIDs(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}
