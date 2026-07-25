package middleware

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// BearerAuthenticator 定义认证中间件所需的请求头验证能力。
type BearerAuthenticator interface {
	// AuthenticateAuthorization 验证完整的 Authorization 请求头。
	AuthenticateAuthorization(context.Context, string) (domain.Principal, bool)
}

// SessionAuth 创建要求有效 Bearer 会话的 Gin 中间件。
func SessionAuth(authenticator BearerAuthenticator) gin.HandlerFunc {
	return func(c *gin.Context) {
		if authenticator == nil {
			c.Header("WWW-Authenticate", "Bearer")
			response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "valid bearer session required", nil)
			return
		}
		principal, ok := authenticator.AuthenticateAuthorization(c.Request.Context(), c.GetHeader("Authorization"))
		if !ok {
			c.Header("WWW-Authenticate", "Bearer")
			response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "valid bearer session required", nil)
			return
		}
		c.Set("principal", principal)
		c.Set("user_id", principal.UserID)
		c.Set("role", principal.Role)
		c.Next()
	}
}

// Principal 返回认证中间件写入的可信身份。
func Principal(c *gin.Context) domain.Principal {
	value, _ := c.Get("principal")
	principal, _ := value.(domain.Principal)
	return principal
}

// RequireAdmin 将管理能力集中在路由层，普通成员统一得到 403。
func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !Principal(c).IsAdmin() {
			response.FromError(c, domain.ErrForbidden)
			return
		}
		c.Next()
	}
}
