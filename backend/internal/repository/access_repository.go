package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// AccessRepository 持久化成员身份、令牌摘要和媒体源授权。
type AccessRepository interface {
	FindPrincipalByTokenHash(context.Context, string, time.Time) (domain.Principal, error)
	FindUserByUsername(context.Context, string) (domain.User, error)
	ListUsers(context.Context) ([]domain.User, error)
	GetUser(context.Context, string) (domain.User, error)
	FindUserByRequestID(context.Context, string) (domain.User, error)
	CreateUser(context.Context, domain.User) error
	UpdateUser(context.Context, domain.User) error
	InitializeAdminCredentials(context.Context, string, string, time.Time) (bool, error)
	UpdatePassword(context.Context, string, string, time.Time) error
	ListSessions(context.Context, string) ([]domain.APIToken, error)
	CreateSession(context.Context, domain.APIToken) error
	RevokeSession(context.Context, string, time.Time) error
	RevokeUserSessions(context.Context, string, time.Time) error
	ListGrants(context.Context, string) ([]string, error)
	GrantSource(context.Context, string, string, time.Time) error
	RevokeSource(context.Context, string, string) error
}
