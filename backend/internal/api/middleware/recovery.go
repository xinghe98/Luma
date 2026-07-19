package middleware

import (
	"fmt"
	"log/slog"
	"net/http"
	"runtime/debug"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
)

// Recovery 创建捕获 Panic、记录堆栈并返回统一错误的恢复中间件。
func Recovery(logger *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if recovered := recover(); recovered != nil {
				logger.ErrorContext(c.Request.Context(), "HTTP panic recovered",
					"request_id", c.GetString(RequestIDKey),
					"panic", fmt.Sprint(recovered),
					"stack", string(debug.Stack()),
				)
				response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error", nil)
			}
		}()
		c.Next()
	}
}
