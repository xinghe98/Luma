package middleware

import (
	"log/slog"
	"time"

	"github.com/gin-gonic/gin"
)

// Logging 创建记录请求结果、耗时和请求 ID 的结构化日志中间件。
func Logging(logger *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		started := time.Now()
		defer func() {
			logger.InfoContext(c.Request.Context(), "HTTP request",
				"request_id", c.GetString(RequestIDKey),
				"method", c.Request.Method,
				"path", c.Request.URL.Path,
				"status", c.Writer.Status(),
				"bytes", c.Writer.Size(),
				"duration_ms", time.Since(started).Milliseconds(),
				"client_ip", c.ClientIP(),
			)
		}()
		c.Next()
	}
}
