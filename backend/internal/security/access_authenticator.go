package security

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// PrincipalLookup 只暴露认证所需的摘要查询，避免安全层依赖具体数据库。
type PrincipalLookup interface {
	FindPrincipalBySessionSecretHash(context.Context, string, time.Time) (domain.Principal, error)
}

type ActivityRecorder interface {
	Observe(userID string)
}

// AccessAuthenticator 只接受数据库中有效的登录会话。
type AccessAuthenticator struct {
	lookup   PrincipalLookup
	activity ActivityRecorder
}

func NewAccessAuthenticator(lookup PrincipalLookup, activity ...ActivityRecorder) (*AccessAuthenticator, error) {
	if lookup == nil {
		return nil, errors.New("会话查询依赖不能为空")
	}
	var recorder ActivityRecorder
	if len(activity) > 0 {
		recorder = activity[0]
	}
	return &AccessAuthenticator{lookup: lookup, activity: recorder}, nil
}

func (a *AccessAuthenticator) AuthenticateAuthorization(ctx context.Context, authorization string) (domain.Principal, bool) {
	parts := strings.Fields(authorization)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || a.lookup == nil {
		return domain.Principal{}, false
	}
	principal, err := a.lookup.FindPrincipalBySessionSecretHash(ctx, HashSessionSecret(parts[1]), time.Now().UTC())
	if err != nil {
		return domain.Principal{}, false
	}
	a.observe(principal)
	return principal, true
}

func (a *AccessAuthenticator) observe(principal domain.Principal) {
	if a.activity != nil {
		a.activity.Observe(principal.UserID)
	}
}
