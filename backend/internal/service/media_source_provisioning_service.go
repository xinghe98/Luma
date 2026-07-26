package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ManagedMediaSourceCommand 描述媒体源、初始授权和首次扫描的一次管理操作。
type ManagedMediaSourceCommand struct {
	Name        string
	RootPath    string
	LibraryKind string
	UserIDs     []string
}

// ManagedMediaSourceResult 返回已创建的来源与首次扫描任务。
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
	RevokeSource(context.Context, string, string) error
}

type provisionedScanUseCase interface {
	Start(context.Context, string) (domain.ScanJob, error)
}

// ManagedMediaSourceService 协调来源创建、授权和首次扫描，并串行执行补偿流程。
type ManagedMediaSourceService struct {
	sources provisionedSourceUseCase
	access  provisionedAccessUseCase
	scans   provisionedScanUseCase
	config  *config.AllowedRootsStore
	mu      sync.Mutex
}

// NewManagedMediaSourceService 创建托管媒体源服务；所有依赖都必须可用。
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

// ListAvailableRoots 返回配置允许客户端选择的媒体根目录。
func (s *ManagedMediaSourceService) ListAvailableRoots() ([]string, error) {
	return s.config.List()
}

// Create 依次创建来源、授权并启动扫描；后续步骤失败时会撤销授权并删除未初始化来源。
// 补偿使用独立短超时上下文，原请求取消不会跳过清理，清理错误会与原始错误一起返回。
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
	userIDs := uniqueIDs(command.UserIDs)
	rollbackSource := func(cause error) error {
		rollbackContext, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
		defer cancel()
		errorsToReturn := []error{cause}
		// 对全部目标用户执行撤销，以覆盖授权已提交但调用返回错误的模糊结果。
		for _, userID := range userIDs {
			if revokeErr := s.access.RevokeSource(rollbackContext, userID, source.ID); revokeErr != nil {
				errorsToReturn = append(errorsToReturn, fmt.Errorf("撤销用户 %s 的来源授权: %w", userID, revokeErr))
			}
		}
		if deleteErr := s.sources.Delete(rollbackContext, source.ID); deleteErr != nil {
			errorsToReturn = append(errorsToReturn, fmt.Errorf("清理媒体源: %w", deleteErr))
		}
		return errors.Join(errorsToReturn...)
	}
	for _, userID := range userIDs {
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
