package api

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/handler"
	"github.com/xinghe98/Luma/backend/internal/api/middleware"
	"github.com/xinghe98/Luma/backend/internal/api/response"
)

// RouterParams 汇总创建 HTTP Router 所需的已构造依赖。
type RouterParams struct {
	// Logger 用于记录请求和恢复异常。
	Logger *slog.Logger
	// AllowedOrigins 是允许跨域访问的浏览器来源。
	AllowedOrigins []string
	// Health 处理公开健康检查请求。
	Health *handler.HealthHandler
	// System 处理需要认证的系统信息请求。
	System *handler.SystemHandler
	// Sources 处理媒体源管理请求。
	Sources *handler.SourceHandler
	// Scans 处理扫描任务创建和查询请求。
	Scans *handler.ScanHandler
	// Media 处理媒体列表、详情和缩略图请求。
	Media *handler.MediaHandler
	// Stream 处理原始视频和图片的 GET、HEAD 和 Range 请求。
	Stream *handler.StreamHandler
	// UserData 处理用户媒体数据和播放进度请求。
	UserData *handler.UserDataHandler
	// Tags 处理用户私有标签请求。
	Tags *handler.TagHandler
	// Authenticator 验证 API Bearer Token。
	Authenticator middleware.BearerAuthenticator
}

// NewRouter 使用注入的 Handler、中间件依赖和配置创建标准 HTTP Handler。
func NewRouter(params RouterParams) (http.Handler, error) {
	if params.Logger == nil {
		return nil, errors.New("logger is required")
	}
	if params.Health == nil || params.System == nil || params.Sources == nil || params.Scans == nil || params.Media == nil || params.Stream == nil || params.UserData == nil || params.Tags == nil {
		return nil, errors.New("HTTP Handler 依赖不能为空")
	}
	if params.Authenticator == nil {
		return nil, errors.New("bearer authenticator is required")
	}
	gin.SetMode(gin.ReleaseMode)
	engine := gin.New()
	engine.HandleMethodNotAllowed = true
	if err := engine.SetTrustedProxies(nil); err != nil {
		return nil, err
	}
	engine.Use(
		middleware.RequestID(),
		middleware.Recovery(params.Logger),
		middleware.Logging(params.Logger),
	)
	if len(params.AllowedOrigins) > 0 {
		engine.Use(middleware.CORS(params.AllowedOrigins))
	}

	engine.GET("/health", params.Health.Get)

	v1 := engine.Group("/api/v1")
	v1.Use(middleware.TokenAuth(params.Authenticator))
	v1.GET("/system/info", params.System.Info)
	v1.GET("/sources", params.Sources.List)
	v1.POST("/sources", params.Sources.Create)
	v1.PATCH("/sources/:id", params.Sources.Update)
	v1.DELETE("/sources/:id", params.Sources.Delete)
	v1.POST("/sources/:id/scan", params.Scans.Start)
	v1.GET("/scan-jobs/latest", params.Scans.Latest)
	v1.GET("/scan-jobs/:id", params.Scans.Get)
	v1.GET("/media", params.Media.List)
	v1.GET("/media/continue-watching", params.Media.ContinueWatching)
	v1.GET("/media/:id", params.Media.Get)
	v1.GET("/media/:id/thumbnail", params.Media.Thumbnail)
	v1.GET("/media/:id/stream", params.Stream.Stream)
	v1.HEAD("/media/:id/stream", params.Stream.Stream)
	v1.GET("/media/:id/original", params.Stream.Original)
	v1.HEAD("/media/:id/original", params.Stream.Original)
	v1.GET("/media/:id/user-data", params.UserData.Get)
	v1.PATCH("/media/:id/user-data", params.UserData.Update)
	v1.PUT("/media/:id/progress", params.UserData.UpdateProgress)
	v1.GET("/tags", params.Tags.List)
	v1.POST("/tags", params.Tags.Create)
	v1.PATCH("/tags/:id", params.Tags.Update)
	v1.DELETE("/tags/:id", params.Tags.Delete)

	secureFallback := func(status int, code, message string) gin.HandlerFunc {
		return func(c *gin.Context) {
			if strings.HasPrefix(c.Request.URL.Path, "/api/") && !params.Authenticator.AuthenticateAuthorization(c.GetHeader("Authorization")) {
				c.Header("WWW-Authenticate", "Bearer")
				response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "valid bearer token required", nil)
				return
			}
			response.Error(c, status, code, message, nil)
		}
	}
	engine.NoRoute(secureFallback(http.StatusNotFound, "NOT_FOUND", "route not found"))
	engine.NoMethod(secureFallback(http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "method not allowed"))
	for _, route := range engine.Routes() {
		params.Logger.Info(route.Method + ":" + route.Path)
	}
	return engine, nil
}
