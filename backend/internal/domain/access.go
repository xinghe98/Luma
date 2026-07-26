package domain

import "time"

const (
	RoleAdmin  = "admin"
	RoleMember = "member"
)

// Principal 是认证成功后贯穿请求链的身份，不接受客户端自行传入。
type Principal struct {
	CredentialID string
	UserID       string
	Name         string
	Role         string
}

func (p Principal) IsAdmin() bool { return p.Role == RoleAdmin }

// User 是可被管理员签发访问凭据的家庭成员。
type User struct {
	ID           string
	RequestID    string
	Name         string
	Username     string
	PasswordHash string
	Role         string
	Enabled      bool
	Online       bool
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// Session 保存登录设备会话元数据。密钥摘要与 device_key 永远不得出现在 API 响应或日志中。
type Session struct {
	ID           string
	RequestID    string
	UserID       string
	Name         string
	DeviceKey    string
	SecretHash   string
	SecretPrefix string
	ExpiresAt    *time.Time
	RevokedAt    *time.Time
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// IssuedSession 只在登录成功时携带一次会话明文。
type IssuedSession struct {
	Session Session
	Secret  string
	User    User
}
