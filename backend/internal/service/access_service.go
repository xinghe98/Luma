package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
	"github.com/xinghe98/Luma/backend/internal/security"
)

// AccessService 管理成员、成员令牌和媒体源授权。
type AccessService struct {
	repository      repository.AccessRepository
	ids             IDGenerator
	clock           Clock
	presence        interface{ IsOnline(string) bool }
	idempotencyMu   sync.Mutex
	issuedByRequest map[string]domain.IssuedToken
	issuedOrder     []string
}

func NewAccessService(repo repository.AccessRepository, ids IDGenerator, clock Clock, presence ...interface{ IsOnline(string) bool }) (*AccessService, error) {
	if repo == nil || ids == nil || clock == nil {
		return nil, fmt.Errorf("访问控制依赖不能为空")
	}
	var tracker interface{ IsOnline(string) bool }
	if len(presence) > 0 {
		tracker = presence[0]
	}
	return &AccessService{repository: repo, ids: ids, clock: clock, presence: tracker, issuedByRequest: map[string]domain.IssuedToken{}}, nil
}

func (s *AccessService) ListUsers(ctx context.Context) ([]domain.User, error) {
	users, err := s.repository.ListUsers(ctx)
	if err != nil || s.presence == nil {
		return users, err
	}
	for index := range users {
		users[index].Online = users[index].Enabled && s.presence.IsOnline(users[index].ID)
	}
	return users, nil
}

func (s *AccessService) CreateUser(ctx context.Context, name string) (domain.User, error) {
	return s.createUser(ctx, name, "")
}

func (s *AccessService) CreateUserIdempotent(ctx context.Context, name, requestID string) (domain.User, error) {
	requestID, err := normalizeAccessRequestID(requestID)
	if err != nil {
		return domain.User{}, err
	}
	if requestID == "" {
		return s.createUser(ctx, name, "")
	}
	s.idempotencyMu.Lock()
	defer s.idempotencyMu.Unlock()
	if user, err := s.repository.FindUserByRequestID(ctx, requestID); err == nil {
		return user, nil
	} else if !errors.Is(err, domain.ErrUserNotFound) {
		return domain.User{}, err
	}
	user, err := s.createUser(ctx, name, requestID)
	if err == nil {
		return user, nil
	}
	if existing, findErr := s.repository.FindUserByRequestID(ctx, requestID); findErr == nil {
		return existing, nil
	}
	return domain.User{}, err
}

func (s *AccessService) createUser(ctx context.Context, name, requestID string) (domain.User, error) {
	name = strings.TrimSpace(name)
	if name == "" || utf8.RuneCountInString(name) > 80 {
		return domain.User{}, fmt.Errorf("%w: 用户名称须为 1 至 80 个字符", domain.ErrInvalidRequest)
	}
	id, err := s.ids.New("user")
	if err != nil {
		return domain.User{}, err
	}
	now := s.clock.Now().UTC()
	user := domain.User{ID: id, RequestID: requestID, Name: name, Role: domain.RoleMember, Enabled: true, CreatedAt: now, UpdatedAt: now}
	if err := s.repository.CreateUser(ctx, user); err != nil {
		return domain.User{}, err
	}
	return user, nil
}

func (s *AccessService) UpdateUser(ctx context.Context, id string, name *string, enabled *bool) (domain.User, error) {
	user, err := s.repository.GetUser(ctx, strings.TrimSpace(id))
	if err != nil {
		return domain.User{}, err
	}
	if name != nil {
		value := strings.TrimSpace(*name)
		if value == "" || utf8.RuneCountInString(value) > 80 {
			return domain.User{}, fmt.Errorf("%w: 用户名称须为 1 至 80 个字符", domain.ErrInvalidRequest)
		}
		user.Name = value
	}
	if enabled != nil {
		if user.Role == domain.RoleAdmin && !*enabled {
			return domain.User{}, fmt.Errorf("%w: 不能禁用本地管理员", domain.ErrInvalidRequest)
		}
		user.Enabled = *enabled
	}
	user.UpdatedAt = s.clock.Now().UTC()
	if err := s.repository.UpdateUser(ctx, user); err != nil {
		return domain.User{}, err
	}
	return user, nil
}

func (s *AccessService) ListTokens(ctx context.Context, userID string) ([]domain.APIToken, error) {
	return s.repository.ListTokens(ctx, strings.TrimSpace(userID))
}

func (s *AccessService) IssueToken(ctx context.Context, userID, name string, expiresAt *time.Time) (domain.IssuedToken, error) {
	return s.issueToken(ctx, userID, name, expiresAt, "")
}

func (s *AccessService) IssueTokenIdempotent(ctx context.Context, userID, name string, expiresAt *time.Time, requestID string) (domain.IssuedToken, error) {
	requestID, err := normalizeAccessRequestID(requestID)
	if err != nil {
		return domain.IssuedToken{}, err
	}
	if requestID == "" {
		return s.issueToken(ctx, userID, name, expiresAt, "")
	}
	s.idempotencyMu.Lock()
	defer s.idempotencyMu.Unlock()
	if token, err := s.repository.FindTokenByRequestID(ctx, requestID); err == nil {
		if issued, ok := s.issuedByRequest[requestID]; ok {
			return issued, nil
		}
		return domain.IssuedToken{Token: token}, domain.ErrIdempotencySecretUnavailable
	} else if !errors.Is(err, domain.ErrTokenNotFound) {
		return domain.IssuedToken{}, err
	}
	issued, err := s.issueToken(ctx, userID, name, expiresAt, requestID)
	if err == nil {
		s.rememberIssued(requestID, issued)
		return issued, nil
	}
	if token, findErr := s.repository.FindTokenByRequestID(ctx, requestID); findErr == nil {
		if replay, ok := s.issuedByRequest[requestID]; ok {
			return replay, nil
		}
		return domain.IssuedToken{Token: token}, domain.ErrIdempotencySecretUnavailable
	}
	return domain.IssuedToken{}, err
}

func (s *AccessService) issueToken(ctx context.Context, userID, name string, expiresAt *time.Time, requestID string) (domain.IssuedToken, error) {
	user, err := s.repository.GetUser(ctx, strings.TrimSpace(userID))
	if err != nil {
		return domain.IssuedToken{}, err
	}
	if !user.Enabled {
		return domain.IssuedToken{}, fmt.Errorf("%w: 用户已禁用", domain.ErrInvalidRequest)
	}
	name = strings.TrimSpace(name)
	if name == "" || utf8.RuneCountInString(name) > 80 {
		return domain.IssuedToken{}, fmt.Errorf("%w: 令牌名称须为 1 至 80 个字符", domain.ErrInvalidRequest)
	}
	now := s.clock.Now().UTC()
	if expiresAt != nil {
		value := expiresAt.UTC()
		if !value.After(now) {
			return domain.IssuedToken{}, fmt.Errorf("%w: expires_at 必须晚于当前时间", domain.ErrInvalidRequest)
		}
		expiresAt = &value
	}
	secret, err := security.GenerateToken()
	if err != nil {
		return domain.IssuedToken{}, err
	}
	id, err := s.ids.New("token")
	if err != nil {
		return domain.IssuedToken{}, err
	}
	prefix := secret
	if len(prefix) > 8 {
		prefix = prefix[:8]
	}
	token := domain.APIToken{ID: id, RequestID: requestID, UserID: user.ID, Name: name, TokenHash: security.HashToken(secret), TokenPrefix: prefix, ExpiresAt: expiresAt, CreatedAt: now, UpdatedAt: now}
	if err := s.repository.CreateToken(ctx, token); err != nil {
		return domain.IssuedToken{}, err
	}
	return domain.IssuedToken{Token: token, Secret: secret}, nil
}

func normalizeAccessRequestID(value string) (string, error) {
	value = strings.TrimSpace(value)
	if len(value) > 128 {
		return "", fmt.Errorf("%w: request_id 最多 128 个字符", domain.ErrInvalidRequest)
	}
	return value, nil
}

func (s *AccessService) rememberIssued(requestID string, issued domain.IssuedToken) {
	const maxReplaySecrets = 256
	if _, exists := s.issuedByRequest[requestID]; !exists {
		s.issuedOrder = append(s.issuedOrder, requestID)
	}
	s.issuedByRequest[requestID] = issued
	for len(s.issuedOrder) > maxReplaySecrets {
		oldest := s.issuedOrder[0]
		s.issuedOrder = s.issuedOrder[1:]
		delete(s.issuedByRequest, oldest)
	}
}

func (s *AccessService) RevokeToken(ctx context.Context, id string) error {
	return s.repository.RevokeToken(ctx, strings.TrimSpace(id), s.clock.Now().UTC())
}

func (s *AccessService) ListGrants(ctx context.Context, userID string) ([]string, error) {
	return s.repository.ListGrants(ctx, strings.TrimSpace(userID))
}

func (s *AccessService) GrantSource(ctx context.Context, userID, sourceID string) error {
	return s.repository.GrantSource(ctx, strings.TrimSpace(userID), strings.TrimSpace(sourceID), s.clock.Now().UTC())
}

func (s *AccessService) RevokeSource(ctx context.Context, userID, sourceID string) error {
	return s.repository.RevokeSource(ctx, strings.TrimSpace(userID), strings.TrimSpace(sourceID))
}
