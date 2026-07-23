package security

import (
	"context"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// PrincipalLookup 只暴露认证所需的摘要查询，避免安全层依赖具体数据库。
type PrincipalLookup interface {
	FindPrincipalByTokenHash(context.Context, string, time.Time) (domain.Principal, error)
}

// AccessAuthenticator 同时接受本地管理员根令牌和数据库中的成员令牌。
type AccessAuthenticator struct {
	bootstrap *TokenAuthenticator
	lookup    PrincipalLookup
}

func NewAccessAuthenticator(bootstrapToken string, lookup PrincipalLookup) (*AccessAuthenticator, error) {
	root, err := NewTokenAuthenticator(bootstrapToken)
	if err != nil {
		return nil, err
	}
	return &AccessAuthenticator{bootstrap: root, lookup: lookup}, nil
}

func (a *AccessAuthenticator) AuthenticateAuthorization(ctx context.Context, authorization string) (domain.Principal, bool) {
	if principal, ok := a.bootstrap.AuthenticateAuthorization(ctx, authorization); ok {
		return principal, true
	}
	parts := strings.Fields(authorization)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || a.lookup == nil {
		return domain.Principal{}, false
	}
	principal, err := a.lookup.FindPrincipalByTokenHash(ctx, HashToken(parts[1]), time.Now().UTC())
	return principal, err == nil
}
