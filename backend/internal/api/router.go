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
	// Catalog 处理电影、剧集及其刮削资料。
	Catalog *handler.CatalogHandler
	// Access 处理管理员成员、登录设备和媒体源授权接口。
	Access *handler.AccessHandler
	// Auth 处理公开登录和受保护登出接口。
	Auth *handler.AuthHandler
	// Authenticator 验证 API Bearer 会话。
	Authenticator middleware.BearerAuthenticator
}

// NewRouter 使用注入的 Handler、中间件依赖和配置创建标准 HTTP Handler。
func NewRouter(params RouterParams) (http.Handler, error) {
	if params.Logger == nil {
		return nil, errors.New("logger is required")
	}
	if params.Health == nil || params.System == nil || params.Sources == nil || params.Scans == nil || params.Media == nil || params.Stream == nil || params.UserData == nil || params.Tags == nil || params.Catalog == nil || params.Access == nil || params.Auth == nil {
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
	v1.POST("/auth/login", params.Auth.Login)
	protected := v1.Group("")
	protected.Use(middleware.SessionAuth(params.Authenticator))
	protected.POST("/auth/logout", params.Auth.Logout)
	protected.GET("/system/info", params.System.Info)
	protected.GET("/sources", params.Sources.List)
	protected.GET("/media", params.Media.List)
	protected.GET("/media/count", params.Media.Count)
	protected.GET("/media/continue-watching", params.Media.ContinueWatching)
	protected.GET("/media/:id", params.Media.Get)
	protected.GET("/catalog", params.Catalog.List)
	protected.GET("/catalog/:id", params.Catalog.Get)
	protected.PATCH("/catalog/:id/user-data", params.Catalog.UpdateFavorite)
	protected.GET("/catalog/artwork/:id", params.Catalog.Artwork)
	protected.GET("/media/:id/thumbnail", params.Media.Thumbnail)
	protected.GET("/media/:id/stream", params.Stream.Stream)
	protected.HEAD("/media/:id/stream", params.Stream.Stream)
	protected.GET("/media/:id/original", params.Stream.Original)
	protected.HEAD("/media/:id/original", params.Stream.Original)
	protected.GET("/media/:id/user-data", params.UserData.Get)
	protected.PATCH("/media/:id/user-data", params.UserData.Update)
	protected.PUT("/media/:id/progress", params.UserData.UpdateProgress)
	protected.GET("/tags", params.Tags.List)
	protected.POST("/tags", params.Tags.Create)
	protected.PATCH("/tags/:id", params.Tags.Update)
	protected.DELETE("/tags/:id", params.Tags.Delete)

	admin := protected.Group("")
	admin.Use(middleware.RequireAdmin())
	admin.POST("/sources", params.Sources.Create)
	admin.GET("/admin/media-roots", params.Sources.ListAvailableRoots)
	admin.POST("/admin/media-sources", params.Sources.CreateManaged)
	admin.PATCH("/sources/:id", params.Sources.Update)
	admin.DELETE("/sources/:id", params.Sources.Delete)
	admin.POST("/sources/:id/scan", params.Scans.Start)
	admin.GET("/scan-jobs/latest", params.Scans.Latest)
	admin.GET("/scan-jobs/:id", params.Scans.Get)
	admin.GET("/admin/catalog/:id/candidates", params.Catalog.MetadataCandidates)
	admin.POST("/admin/catalog/:id/refresh", params.Catalog.RefreshMetadata)
	admin.POST("/admin/catalog/refresh", params.Catalog.RefreshAllMetadata)
	admin.PUT("/admin/catalog/:id/identity", params.Catalog.SelectMetadataIdentity)
	admin.GET("/admin/metadata/status", params.Catalog.MetadataProviders)
	admin.GET("/admin/users", params.Access.ListUsers)
	admin.POST("/admin/users", params.Access.CreateUser)
	admin.PATCH("/admin/users/:id", params.Access.UpdateUser)
	admin.PUT("/admin/users/:id/password", params.Access.ResetPassword)
	admin.GET("/admin/users/:id/sessions", params.Access.ListSessions)
	admin.DELETE("/admin/sessions/:id", params.Access.RevokeSession)
	admin.GET("/admin/users/:id/sources", params.Access.ListGrants)
	admin.PUT("/admin/users/:id/sources/:sourceId", params.Access.GrantSource)
	admin.DELETE("/admin/users/:id/sources/:sourceId", params.Access.RevokeSource)

	secureFallback := func(status int, code, message string) gin.HandlerFunc {
		return func(c *gin.Context) {
			_, authenticated := params.Authenticator.AuthenticateAuthorization(c.Request.Context(), c.GetHeader("Authorization"))
			if strings.HasPrefix(c.Request.URL.Path, "/api/") && !authenticated {
				c.Header("WWW-Authenticate", "Bearer")
				response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "valid bearer session required", nil)
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
