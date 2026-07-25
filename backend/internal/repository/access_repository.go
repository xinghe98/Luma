package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// AccessRepository 持久化成员身份、会话摘要和媒体源授权。
type AccessRepository interface {
	// FindPrincipalBySessionSecretHash 查询有效会话对应的身份。
	FindPrincipalBySessionSecretHash(context.Context, string, time.Time) (domain.Principal, error)
	FindUserByUsername(context.Context, string) (domain.User, error)
	ListUsers(context.Context) ([]domain.User, error)
	GetUser(context.Context, string) (domain.User, error)
	FindUserByRequestID(context.Context, string) (domain.User, error)
	CreateUser(context.Context, domain.User) error
	UpdateUser(context.Context, domain.User) error
	InitializeAdminCredentials(context.Context, string, string, time.Time) (bool, error)
	UpdatePassword(context.Context, string, string, time.Time) error
	// ListSessions 返回账号的设备会话元数据，不包含密钥明文。
	ListSessions(context.Context, string) ([]domain.Session, error)
	// CreateSession 保存新登录的设备会话摘要。
	CreateSession(context.Context, domain.Session) error
	RevokeSession(context.Context, string, time.Time) error
	RevokeUserSessions(context.Context, string, time.Time) error
	ListGrants(context.Context, string) ([]string, error)
	GrantSource(context.Context, string, string, time.Time) error
	RevokeSource(context.Context, string, string) error
}
