package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

// SourceRootValidator 定义媒体源服务所需的安全路径校验能力。
type SourceRootValidator interface {
	// ValidateSourceRoot 校验候选媒体源并返回规范路径。
	ValidateSourceRoot(string) (string, error)
}

// ActiveScanChecker 定义媒体源变更前检查活跃扫描的能力。
type ActiveScanChecker interface {
	// HasActiveJob 判断媒体源是否存在 pending/running 扫描。
	HasActiveJob(context.Context, string) (bool, error)
}

// SourceIndexedMediaChecker 定义根目录变更前检查既有媒体索引的能力。
type SourceIndexedMediaChecker interface {
	// HasIndexedMedia 判断来源是否已有媒体记录；检查失败时调用方必须禁止变更。
	HasIndexedMedia(context.Context, string) (bool, error)
}

// SourceService 是媒体源管理的业务边界。
type SourceService struct {
	// repository 是注入的媒体源持久化接口。
	repository repository.SourceRepository
	// roots 是注入的媒体源路径安全校验器。
	roots SourceRootValidator
	// scans 用于在变更根目录前检查活跃扫描。
	scans ActiveScanChecker
	// indexedMedia 防止已有媒体 ID 在换根后立即指向另一批文件。
	indexedMedia SourceIndexedMediaChecker
	// ids 是注入的业务标识生成器。
	ids IDGenerator
	// clock 是注入的 UTC 时钟。
	clock Clock
}

// NewSourceService 使用持久化、路径、扫描与索引检查、标识和时钟依赖创建媒体源服务。
func NewSourceService(
	repository repository.SourceRepository,
	roots SourceRootValidator,
	scans ActiveScanChecker,
	indexedMedia SourceIndexedMediaChecker,
	ids IDGenerator,
	clock Clock,
) (*SourceService, error) {
	if repository == nil || roots == nil || scans == nil || indexedMedia == nil || ids == nil || clock == nil {
		return nil, errors.New("媒体源服务依赖不能为空")
	}
	return &SourceService{
		repository: repository, roots: roots, scans: scans, indexedMedia: indexedMedia, ids: ids, clock: clock,
	}, nil
}

// ValidateRoot 在上下文有效时校验候选媒体源根目录。
func (s *SourceService) ValidateRoot(ctx context.Context, candidate string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return s.roots.ValidateSourceRoot(candidate)
}

// List 返回全部媒体源，真实根目录仅供业务内部使用。
func (s *SourceService) List(ctx context.Context) ([]domain.Source, error) {
	return s.repository.List(ctx)
}

// ListVisible 是面向 API 身份的来源列表，后台任务继续使用 List。
func (s *SourceService) ListVisible(ctx context.Context, userID string) ([]domain.Source, error) {
	if strings.TrimSpace(userID) == "" {
		return nil, domain.ErrUnauthorized
	}
	visible, ok := s.repository.(interface {
		ListVisible(context.Context, string) ([]domain.Source, error)
	})
	if !ok {
		// 测试替身和旧的仓储实现保持兼容；生产 SQLite 实现始终走授权查询。
		return s.repository.List(ctx)
	}
	return visible.ListVisible(ctx, userID)
}

// Get 返回指定媒体源，供 Handler 和后台 Worker 使用。
func (s *SourceService) Get(ctx context.Context, id string) (domain.Source, error) {
	return s.repository.Get(ctx, id)
}

// Create 校验本地目录并创建新的媒体源。
func (s *SourceService) Create(ctx context.Context, command domain.CreateSourceCommand) (domain.Source, error) {
	name, err := validateSourceName(command.Name)
	if err != nil {
		return domain.Source{}, err
	}
	root, err := s.ValidateRoot(ctx, command.RootPath)
	if err != nil {
		return domain.Source{}, fmt.Errorf("%w: %v", domain.ErrForbiddenPath, err)
	}
	libraryKind := domain.LibraryKindPersonal
	if strings.TrimSpace(command.LibraryKind) != "" {
		libraryKind, err = validateLibraryKind(command.LibraryKind)
		if err != nil {
			return domain.Source{}, err
		}
	}
	id, err := s.ids.New("source")
	if err != nil {
		return domain.Source{}, err
	}
	now := s.clock.Now()
	source := domain.Source{
		ID: id, Name: name, Type: domain.SourceTypeLocal, LibraryKind: libraryKind, RootPath: root,
		Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
	}
	if err := s.repository.Create(ctx, source); err != nil {
		return domain.Source{}, err
	}
	return source, nil
}

// Update 重新校验变更字段并保存媒体源。
func (s *SourceService) Update(ctx context.Context, command domain.UpdateSourceCommand) (domain.Source, error) {
	source, err := s.repository.Get(ctx, command.ID)
	if err != nil {
		return domain.Source{}, err
	}
	if command.Name != nil {
		source.Name, err = validateSourceName(*command.Name)
		if err != nil {
			return domain.Source{}, err
		}
	}
	if command.RootPath != nil {
		root, err := s.ValidateRoot(ctx, *command.RootPath)
		if err != nil {
			return domain.Source{}, fmt.Errorf("%w: %v", domain.ErrForbiddenPath, err)
		}
		if root != source.RootPath {
			active, err := s.scans.HasActiveJob(ctx, source.ID)
			if err != nil {
				return domain.Source{}, err
			}
			if active {
				return domain.Source{}, fmt.Errorf("%w: 扫描进行中不能修改根目录", domain.ErrScanAlreadyRunning)
			}
			hasMedia, err := s.indexedMedia.HasIndexedMedia(ctx, source.ID)
			if err != nil {
				return domain.Source{}, err
			}
			if hasMedia {
				return domain.Source{}, fmt.Errorf("%w: 媒体源已有索引，不能直接修改根目录", domain.ErrSourceConflict)
			}
			source.RootPath = root
		}
	}
	if command.Enabled != nil {
		source.Enabled = *command.Enabled
		if source.Enabled {
			source.Status = domain.SourceStatusOnline
		} else {
			source.Status = domain.SourceStatusDisabled
		}
	}
	if command.LibraryKind != nil {
		kind, validationErr := validateLibraryKind(*command.LibraryKind)
		if validationErr != nil {
			return domain.Source{}, validationErr
		}
		source.LibraryKind = kind
	}
	source.UpdatedAt = s.clock.Now()
	if err := s.repository.Update(ctx, source); err != nil {
		return domain.Source{}, err
	}
	return source, nil
}

func validateLibraryKind(value string) (string, error) {
	kind := strings.TrimSpace(value)
	switch kind {
	case domain.LibraryKindPersonal, domain.LibraryKindMovies, domain.LibraryKindTV:
		return kind, nil
	default:
		return "", fmt.Errorf("%w: library_kind 必须是 personal、movies 或 tv", domain.ErrInvalidRequest)
	}
}

// Delete 软删除媒体源，释放根路径占用，并保留媒体索引及用户数据。
func (s *SourceService) Delete(ctx context.Context, id string) error {
	return s.repository.SoftDelete(ctx, id, s.clock.Now())
}

// validateSourceName 清理并校验媒体源展示名称。
func validateSourceName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", fmt.Errorf("%w: 媒体源名称不能为空", domain.ErrInvalidRequest)
	}
	if len([]rune(name)) > 200 {
		return "", fmt.Errorf("%w: 媒体源名称不能超过 200 个字符", domain.ErrInvalidRequest)
	}
	return name, nil
}
