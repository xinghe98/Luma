package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
)

// BearerAuthenticator 定义认证中间件所需的请求头验证能力。
type BearerAuthenticator interface {
	// AuthenticateAuthorization 验证完整的 Authorization 请求头。
	AuthenticateAuthorization(string) bool
}

// TokenAuth 创建要求有效 Bearer Token 的 Gin 中间件。
func TokenAuth(authenticator BearerAuthenticator) gin.HandlerFunc {
	return func(c *gin.Context) {
		if authenticator == nil || !authenticator.AuthenticateAuthorization(c.GetHeader("Authorization")) {
			c.Header("WWW-Authenticate", "Bearer")
			response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "valid bearer token required", nil)
			return
		}
		c.Set("user_id", "user_local")
		c.Next()
	}
}
