package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode"

	"golang.org/x/text/cases"
	"golang.org/x/text/unicode/norm"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

// TagService 实现用户私有标签业务。
type TagService struct {
	repository repository.TagRepository
	ids        IDGenerator
	clock      Clock
}

// NewTagService 创建标签服务。
func NewTagService(tags repository.TagRepository, ids IDGenerator, clock Clock) (*TagService, error) {
	if tags == nil || ids == nil || clock == nil {
		return nil, errors.New("标签服务依赖不能为空")
	}
	return &TagService{repository: tags, ids: ids, clock: clock}, nil
}

// List 返回当前用户的标签。
func (s *TagService) List(ctx context.Context, userID string) ([]domain.Tag, error) {
	if strings.TrimSpace(userID) == "" {
		return nil, fmt.Errorf("%w: 用户身份无效", domain.ErrInvalidRequest)
	}
	return s.repository.List(ctx, userID)
}

// Create 规范化并创建标签。
func (s *TagService) Create(ctx context.Context, command domain.CreateTagCommand) (domain.Tag, error) {
	display, normalized, err := normalizeTagName(command.Name)
	if err != nil {
		return domain.Tag{}, err
	}
	command.UserID = strings.TrimSpace(command.UserID)
	if command.UserID == "" {
		return domain.Tag{}, fmt.Errorf("%w: 用户身份无效", domain.ErrInvalidRequest)
	}
	id, err := s.ids.New("tag")
	if err != nil {
		return domain.Tag{}, err
	}
	now := s.clock.Now().UTC()
	tag := domain.Tag{ID: id, UserID: command.UserID, Name: display, NormalizedName: normalized, Revision: 1, CreatedAt: now, UpdatedAt: now}
	if err := s.repository.Create(ctx, tag); err != nil {
		return domain.Tag{}, err
	}
	return tag, nil
}

// Update 使用乐观锁重命名标签。
func (s *TagService) Update(ctx context.Context, command domain.UpdateTagCommand) (domain.Tag, error) {
	command.UserID = strings.TrimSpace(command.UserID)
	command.ID = strings.TrimSpace(command.ID)
	if command.UserID == "" || command.ID == "" || command.BaseRevision < 1 {
		return domain.Tag{}, fmt.Errorf("%w: 标签 ID 或 base_revision 无效", domain.ErrInvalidRequest)
	}
	display, normalized, err := normalizeTagName(command.Name)
	if err != nil {
		return domain.Tag{}, err
	}
	tag := domain.Tag{
		ID: command.ID, UserID: command.UserID, Name: display, NormalizedName: normalized,
		Revision: command.BaseRevision + 1, UpdatedAt: s.clock.Now().UTC(),
	}
	updated, err := s.repository.Update(ctx, tag, command.BaseRevision)
	if err != nil {
		return domain.Tag{}, err
	}
	return updated, nil
}

// Delete 删除当前用户标签。
func (s *TagService) Delete(ctx context.Context, userID, id string) error {
	userID = strings.TrimSpace(userID)
	id = strings.TrimSpace(id)
	if userID == "" || id == "" {
		return fmt.Errorf("%w: 标签 ID 无效", domain.ErrInvalidRequest)
	}
	return s.repository.Delete(ctx, userID, id, s.clock.Now())
}

func normalizeTagName(name string) (string, string, error) {
	display := strings.TrimSpace(norm.NFKC.String(name))
	if display == "" || len([]rune(display)) > 100 {
		return "", "", fmt.Errorf("%w: 标签名称必须为 1 到 100 个字符", domain.ErrInvalidRequest)
	}
	for _, value := range display {
		if unicode.IsControl(value) {
			return "", "", fmt.Errorf("%w: 标签名称不能包含控制字符", domain.ErrInvalidRequest)
		}
	}
	// cases.Caser 不可跨 goroutine 复用，每次折叠时新建。
	normalized := norm.NFKC.String(cases.Fold().String(display))
	return display, normalized, nil
}
