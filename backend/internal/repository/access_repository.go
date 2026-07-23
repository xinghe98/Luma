package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// AccessRepository 持久化成员身份、令牌摘要和媒体源授权。
type AccessRepository interface {
	FindPrincipalByTokenHash(context.Context, string, time.Time) (domain.Principal, error)
	ListUsers(context.Context) ([]domain.User, error)
	GetUser(context.Context, string) (domain.User, error)
	FindUserByRequestID(context.Context, string) (domain.User, error)
	CreateUser(context.Context, domain.User) error
	UpdateUser(context.Context, domain.User) error
	ListTokens(context.Context, string) ([]domain.APIToken, error)
	CreateToken(context.Context, domain.APIToken) error
	FindTokenByRequestID(context.Context, string) (domain.APIToken, error)
	RevokeToken(context.Context, string, time.Time) error
	ListGrants(context.Context, string) ([]string, error)
	GrantSource(context.Context, string, string, time.Time) error
	RevokeSource(context.Context, string, string) error
}
