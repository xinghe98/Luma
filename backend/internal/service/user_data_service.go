package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

// UserDataService 实现用户媒体数据、标签关系和播放进度业务。
type UserDataService struct {
	repository repository.UserDataRepository
	clock      Clock
}

// NewUserDataService 创建用户数据服务。
func NewUserDataService(userData repository.UserDataRepository, clock Clock) (*UserDataService, error) {
	if userData == nil || clock == nil {
		return nil, errors.New("用户数据服务依赖不能为空")
	}
	return &UserDataService{repository: userData, clock: clock}, nil
}

// Get 返回媒体的完整用户数据。
func (s *UserDataService) Get(ctx context.Context, userID, mediaID string) (domain.MediaUserData, error) {
	if strings.TrimSpace(userID) == "" || strings.TrimSpace(mediaID) == "" {
		return domain.MediaUserData{}, fmt.Errorf("%w: 用户或媒体 ID 无效", domain.ErrInvalidRequest)
	}
	return s.repository.Get(ctx, userID, mediaID)
}

// Update 校验并原子更新用户数据和标签关系。
func (s *UserDataService) Update(ctx context.Context, command domain.UpdateUserDataCommand) (domain.MediaUserData, error) {
	command.UserID = strings.TrimSpace(command.UserID)
	command.MediaID = strings.TrimSpace(command.MediaID)
	if command.UserID == "" || command.MediaID == "" || command.BaseRevision < 0 {
		return domain.MediaUserData{}, fmt.Errorf("%w: 用户、媒体 ID 或 base_revision 无效", domain.ErrInvalidRequest)
	}
	if !command.CustomTitle.Set && !command.Favorite.Set && !command.Notes.Set && !command.TagIDs.Set {
		return domain.MediaUserData{}, fmt.Errorf("%w: 至少提供一个可修改字段", domain.ErrInvalidRequest)
	}
	if command.CustomTitle.Set && command.CustomTitle.Value != nil {
		value := strings.TrimSpace(*command.CustomTitle.Value)
		if value == "" || len([]rune(value)) > 200 {
			return domain.MediaUserData{}, fmt.Errorf("%w: 自定义标题必须为 1 到 200 个字符", domain.ErrInvalidRequest)
		}
		command.CustomTitle.Value = &value
	}
	if command.Favorite.Set && command.Favorite.Value == nil {
		return domain.MediaUserData{}, fmt.Errorf("%w: favorite 不能为 null", domain.ErrInvalidRequest)
	}
	if command.Notes.Set && command.Notes.Value != nil {
		value := *command.Notes.Value
		if len([]rune(value)) > 20000 || len(value) > 64*1024 || !utf8.ValidString(value) {
			return domain.MediaUserData{}, fmt.Errorf("%w: 笔记不能超过 20000 个字符或 64 KiB", domain.ErrInvalidRequest)
		}
	}
	if command.TagIDs.Set {
		if command.TagIDs.Value == nil {
			return domain.MediaUserData{}, fmt.Errorf("%w: tag_ids 不能为 null", domain.ErrInvalidRequest)
		}
		if len(*command.TagIDs.Value) > 100 {
			return domain.MediaUserData{}, fmt.Errorf("%w: 单个媒体最多关联 100 个标签", domain.ErrInvalidRequest)
		}
		seen := make(map[string]struct{}, len(*command.TagIDs.Value))
		for index, id := range *command.TagIDs.Value {
			id = strings.TrimSpace(id)
			if id == "" || len(id) > 200 {
				return domain.MediaUserData{}, fmt.Errorf("%w: 标签 ID 无效", domain.ErrInvalidRequest)
			}
			if _, exists := seen[id]; exists {
				return domain.MediaUserData{}, fmt.Errorf("%w: tag_ids 不能重复", domain.ErrInvalidRequest)
			}
			seen[id] = struct{}{}
			(*command.TagIDs.Value)[index] = id
		}
	}
	return s.repository.Update(ctx, command, s.clock.Now())
}

// UpdateProgress 校验参数并保存播放进度；时长截断与完成判定在仓储事务内完成。
func (s *UserDataService) UpdateProgress(ctx context.Context, userID, mediaID string, positionMS, baseRevision int64) (domain.MediaUserData, error) {
	userID = strings.TrimSpace(userID)
	mediaID = strings.TrimSpace(mediaID)
	if userID == "" || mediaID == "" || positionMS < 0 || baseRevision < 0 {
		return domain.MediaUserData{}, fmt.Errorf("%w: 播放进度参数无效", domain.ErrInvalidRequest)
	}
	return s.repository.UpdateProgress(ctx, domain.UpdateProgressCommand{
		UserID: userID, MediaID: mediaID, PositionMS: positionMS,
		BaseRevision: baseRevision, Now: s.clock.Now(),
	})
}
