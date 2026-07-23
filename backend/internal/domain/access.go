package domain

import "time"

const (
	RoleAdmin  = "admin"
	RoleMember = "member"
)

// Principal 是认证成功后贯穿请求链的身份，不接受客户端自行传入。
type Principal struct {
	UserID string
	Name   string
	Role   string
}

func (p Principal) IsAdmin() bool { return p.Role == RoleAdmin }

// User 是可被管理员签发访问凭据的家庭成员。
type User struct {
	ID        string
	RequestID string
	Name      string
	Role      string
	Enabled   bool
	Online    bool
	CreatedAt time.Time
	UpdatedAt time.Time
}

// APIToken 保存令牌元数据。TokenHash 永远不得出现在 API 响应或日志中。
type APIToken struct {
	ID          string
	RequestID   string
	UserID      string
	Name        string
	TokenHash   string
	TokenPrefix string
	ExpiresAt   *time.Time
	RevokedAt   *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

// IssuedToken 只在创建响应中携带一次明文令牌。
type IssuedToken struct {
	Token  APIToken
	Secret string
}
