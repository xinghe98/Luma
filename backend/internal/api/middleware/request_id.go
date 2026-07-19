package middleware

import (
	"crypto/rand"
	"encoding/hex"

	"github.com/gin-gonic/gin"
)

// RequestIDKey 是 Gin 上下文中保存请求 ID 的键。
const RequestIDKey = "request_id"

// RequestID 创建读取或生成请求 ID 的中间件。
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" || len(requestID) > 128 {
			requestID = newRequestID()
		}
		c.Set(RequestIDKey, requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	}
}

// newRequestID 生成不可预测的十六进制请求 ID。
func newRequestID() string {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "unavailable"
	}
	return hex.EncodeToString(value)
}
