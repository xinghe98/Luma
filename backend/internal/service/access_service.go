// AccessService 管理账号、登录会话和媒体源授权，密码只在本服务的输入边界出现。
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

const sessionLifetime = 30 * 24 * time.Hour

// AccessService 管理成员、登录会话和媒体源授权。
type AccessService struct {
	repository repository.AccessRepository
	ids        IDGenerator
	clock      Clock
	presence   interface{ IsOnline(string) bool }
	mu         sync.Mutex
}

// NewAccessService 创建访问控制服务；依赖必须由 Composition Root 注入。
func NewAccessService(repo repository.AccessRepository, ids IDGenerator, clock Clock, presence ...interface{ IsOnline(string) bool }) (*AccessService, error) {
	if repo == nil || ids == nil || clock == nil {
		return nil, fmt.Errorf("访问控制依赖不能为空")
	}
	var tracker interface{ IsOnline(string) bool }
	if len(presence) > 0 {
		tracker = presence[0]
	}
	return &AccessService{repository: repo, ids: ids, clock: clock, presence: tracker}, nil
}

// EnsureBootstrapAdmin 在本地管理员尚无密码时初始化其账号，并返回是否首次初始化。
func (s *AccessService) EnsureBootstrapAdmin(ctx context.Context, username, password string) (bool, error) {
	username, err := normalizeUsername(username)
	if err != nil {
		return false, err
	}
	hash, err := security.HashPassword(password)
	if err != nil {
		return false, err
	}
	return s.repository.InitializeAdminCredentials(ctx, username, hash, s.clock.Now().UTC())
}

// ListUsers 返回管理员可管理的全部账号及在线状态。
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

// CreateUser 创建成员账号；密码会立即转换为不可逆摘要。
func (s *AccessService) CreateUser(ctx context.Context, name, username, password string) (domain.User, error) {
	return s.createUser(ctx, name, username, password, "")
}

// CreateUserIdempotent 使用请求标识安全重试成员创建，不重复创建账号。
func (s *AccessService) CreateUserIdempotent(ctx context.Context, name, username, password, requestID string) (domain.User, error) {
	requestID, err := normalizeAccessRequestID(requestID)
	if err != nil {
		return domain.User{}, err
	}
	if requestID == "" {
		return s.createUser(ctx, name, username, password, "")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if user, err := s.repository.FindUserByRequestID(ctx, requestID); err == nil {
		return user, nil
	} else if !errors.Is(err, domain.ErrUserNotFound) {
		return domain.User{}, err
	}
	return s.createUser(ctx, name, username, password, requestID)
}

func (s *AccessService) createUser(ctx context.Context, name, username, password, requestID string) (domain.User, error) {
	name = strings.TrimSpace(name)
	if name == "" || utf8.RuneCountInString(name) > 80 {
		return domain.User{}, fmt.Errorf("%w: 用户名称须为 1 至 80 个字符", domain.ErrInvalidRequest)
	}
	username, err := normalizeUsername(username)
	if err != nil {
		return domain.User{}, err
	}
	hash, err := security.HashPassword(password)
	if err != nil {
		return domain.User{}, fmt.Errorf("%w: %v", domain.ErrInvalidRequest, err)
	}
	id, err := s.ids.New("user")
	if err != nil {
		return domain.User{}, err
	}
	now := s.clock.Now().UTC()
	user := domain.User{ID: id, RequestID: requestID, Name: name, Username: username, PasswordHash: hash, Role: domain.RoleMember, Enabled: true, CreatedAt: now, UpdatedAt: now}
	if err := s.repository.CreateUser(ctx, user); err != nil {
		return domain.User{}, err
	}
	user.PasswordHash = ""
	return user, nil
}

// UpdateUser 更新显示名称或启用状态；停用账号会立即撤销其会话。
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
			return domain.User{}, fmt.Errorf("%w: 不能停用本地管理员", domain.ErrInvalidRequest)
		}
		user.Enabled = *enabled
	}
	user.UpdatedAt = s.clock.Now().UTC()
	if err := s.repository.UpdateUser(ctx, user); err != nil {
		return domain.User{}, err
	}
	if enabled != nil && !*enabled {
		if err := s.repository.RevokeUserSessions(ctx, user.ID, user.UpdatedAt); err != nil {
			return domain.User{}, err
		}
	}
	user.PasswordHash = ""
	return user, nil
}

// Login 验证账号密码并创建有效期固定的独立设备会话。
func (s *AccessService) Login(ctx context.Context, username, password, deviceName string) (domain.IssuedSession, error) {
	username, err := normalizeUsername(username)
	if err != nil {
		return domain.IssuedSession{}, domain.ErrUnauthorized
	}
	user, err := s.repository.FindUserByUsername(ctx, username)
	if err != nil || !user.Enabled || !security.VerifyPassword(user.PasswordHash, password) {
		return domain.IssuedSession{}, domain.ErrUnauthorized
	}
	deviceName = strings.TrimSpace(deviceName)
	if deviceName == "" {
		deviceName = "Luma 客户端"
	}
	if utf8.RuneCountInString(deviceName) > 80 {
		return domain.IssuedSession{}, fmt.Errorf("%w: 设备名称最多 80 个字符", domain.ErrInvalidRequest)
	}
	secret, err := security.GenerateToken()
	if err != nil {
		return domain.IssuedSession{}, err
	}
	id, err := s.ids.New("session")
	if err != nil {
		return domain.IssuedSession{}, err
	}
	now := s.clock.Now().UTC()
	expires := now.Add(sessionLifetime)
	prefix := secret[:min(8, len(secret))]
	session := domain.APIToken{ID: id, UserID: user.ID, Name: deviceName, Kind: "session", TokenHash: security.HashToken(secret), TokenPrefix: prefix, ExpiresAt: &expires, CreatedAt: now, UpdatedAt: now}
	if err := s.repository.CreateSession(ctx, session); err != nil {
		return domain.IssuedSession{}, err
	}
	user.PasswordHash = ""
	return domain.IssuedSession{Session: session, Secret: secret, User: user}, nil
}

// Logout 撤销当前会话；根凭据或旧令牌无法进入此路径。
func (s *AccessService) Logout(ctx context.Context, credentialID string) error {
	if strings.TrimSpace(credentialID) == "" {
		return domain.ErrUnauthorized
	}
	return s.repository.RevokeSession(ctx, credentialID, s.clock.Now().UTC())
}

// ResetPassword 设置新密码并撤销该账号所有已登录设备。
func (s *AccessService) ResetPassword(ctx context.Context, userID, password string) error {
	hash, err := security.HashPassword(password)
	if err != nil {
		return fmt.Errorf("%w: %v", domain.ErrInvalidRequest, err)
	}
	now := s.clock.Now().UTC()
	if err := s.repository.UpdatePassword(ctx, strings.TrimSpace(userID), hash, now); err != nil {
		return err
	}
	return s.repository.RevokeUserSessions(ctx, strings.TrimSpace(userID), now)
}

// ListSessions 返回成员所有登录设备，不返回会话明文。
func (s *AccessService) ListSessions(ctx context.Context, userID string) ([]domain.APIToken, error) {
	return s.repository.ListSessions(ctx, strings.TrimSpace(userID))
}

// RevokeSession 使指定登录设备立即失效。
func (s *AccessService) RevokeSession(ctx context.Context, id string) error {
	return s.repository.RevokeSession(ctx, strings.TrimSpace(id), s.clock.Now().UTC())
}

// ListGrants 返回账号拥有的媒体源授权。
func (s *AccessService) ListGrants(ctx context.Context, userID string) ([]string, error) {
	return s.repository.ListGrants(ctx, strings.TrimSpace(userID))
}

// GrantSource 授予账号访问一个媒体源的权限。
func (s *AccessService) GrantSource(ctx context.Context, userID, sourceID string) error {
	return s.repository.GrantSource(ctx, strings.TrimSpace(userID), strings.TrimSpace(sourceID), s.clock.Now().UTC())
}

// RevokeSource 撤销账号对一个媒体源的访问权限。
func (s *AccessService) RevokeSource(ctx context.Context, userID, sourceID string) error {
	return s.repository.RevokeSource(ctx, strings.TrimSpace(userID), strings.TrimSpace(sourceID))
}

func normalizeUsername(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	if len(value) < 3 || len(value) > 32 {
		return "", fmt.Errorf("%w: 用户名长度须为 3 至 32 个字符", domain.ErrInvalidRequest)
	}
	for _, char := range value {
		if !(char >= 'a' && char <= 'z') && !(char >= '0' && char <= '9') && char != '.' && char != '_' && char != '-' {
			return "", fmt.Errorf("%w: 用户名只能包含字母、数字、点、下划线和连字符", domain.ErrInvalidRequest)
		}
	}
	return value, nil
}

func normalizeAccessRequestID(value string) (string, error) {
	value = strings.TrimSpace(value)
	if len(value) > 128 {
		return "", fmt.Errorf("%w: request_id 最多 128 个字符", domain.ErrInvalidRequest)
	}
	return value, nil
}

func min(first, second int) int {
	if first < second {
		return first
	}
	return second
}
