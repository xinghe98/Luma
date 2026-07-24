package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ManagedMediaSourceCommand is the complete administrator request for a new
// source. The directory is intentionally server-local, never a client path.
type ManagedMediaSourceCommand struct {
	Name        string
	RootPath    string
	LibraryKind string
	UserIDs     []string
}

// ManagedMediaSourceResult returns the public work created by provisioning.
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

type allowedRootsReloader interface {
	ReplaceAllowedRoots([]string) error
}

// ManagedMediaSourceService owns the cross-boundary operation of adding a
// directory. It keeps YAML persistence, the in-memory policy and database
// rows in a deliberately ordered, compensating workflow.
type ManagedMediaSourceService struct {
	sources provisionedSourceUseCase
	access  provisionedAccessUseCase
	scans   provisionedScanUseCase
	config  *config.AllowedRootsStore
	roots   allowedRootsReloader
	mu      sync.Mutex
}

func NewManagedMediaSourceService(
	sources provisionedSourceUseCase,
	access provisionedAccessUseCase,
	scans provisionedScanUseCase,
	store *config.AllowedRootsStore,
	roots allowedRootsReloader,
) (*ManagedMediaSourceService, error) {
	if sources == nil || access == nil || scans == nil || store == nil || roots == nil {
		return nil, errors.New("新增媒体源服务依赖不能为空")
	}
	return &ManagedMediaSourceService{sources: sources, access: access, scans: scans, config: store, roots: roots}, nil
}

// ListAvailableRoots returns the administrator-selectable media directories
// configured by security.allowed_roots. It never creates or changes a root.
func (s *ManagedMediaSourceService) ListAvailableRoots() ([]string, error) {
	return s.config.List()
}

// Create persists the directory whitelist, makes it live, creates the source,
// grants selected members and queues its first scan. A failed later step
// removes the just-created source and restores the original whitelist.
func (s *ManagedMediaSourceService) Create(ctx context.Context, command ManagedMediaSourceCommand) (ManagedMediaSourceResult, error) {
	if err := ctx.Err(); err != nil {
		return ManagedMediaSourceResult{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	update, err := s.config.Add(strings.TrimSpace(command.RootPath))
	if err != nil {
		return ManagedMediaSourceResult{}, fmt.Errorf("更新媒体目录白名单: %w", err)
	}
	if err := s.roots.ReplaceAllowedRoots(update.Current); err != nil {
		return ManagedMediaSourceResult{}, s.restore(update, err)
	}

	source, err := s.sources.Create(ctx, domain.CreateSourceCommand{
		Name: command.Name, RootPath: command.RootPath, LibraryKind: command.LibraryKind,
	})
	if err != nil {
		return ManagedMediaSourceResult{}, s.restore(update, err)
	}
	rollbackSource := func(cause error) error {
		deleteErr := s.sources.Delete(context.Background(), source.ID)
		return s.restore(update, errors.Join(cause, deleteErr))
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

func (s *ManagedMediaSourceService) restore(update config.AllowedRootsUpdate, cause error) error {
	configErr := s.config.Restore(update)
	policyErr := s.roots.ReplaceAllowedRoots(update.Previous)
	return errors.Join(cause, configErr, policyErr)
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
