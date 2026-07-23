package handler

import (
	"context"
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/middleware"
	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// SystemUseCase 定义系统信息 Handler 所需的业务能力。
type SystemUseCase interface {
	// Info 返回服务端运行信息，并检查关键依赖状态。
	Info(context.Context) (domain.SystemInfo, error)
}

// SystemHandler 将系统信息业务结果适配为 HTTP 响应。
type SystemHandler struct {
	// service 是注入的系统信息业务用例。
	service SystemUseCase
}

// NewSystemHandler 使用系统信息用例创建 Handler。
func NewSystemHandler(service SystemUseCase) (*SystemHandler, error) {
	if service == nil {
		return nil, errors.New("system use case is required")
	}
	return &SystemHandler{service: service}, nil
}

// Info 处理 GET /api/v1/system/info 请求。
func (h *SystemHandler) Info(c *gin.Context) {
	info, err := h.service.Info(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error", nil)
		return
	}
	principal := middleware.Principal(c)
	capabilities := []string{"media.read", "user_data.write"}
	if principal.IsAdmin() {
		capabilities = append(capabilities, "sources.manage", "scans.manage", "catalog.manage", "users.manage")
	}
	c.JSON(http.StatusOK, gin.H{
		"version":      info.Version,
		"platform":     info.Platform,
		"architecture": info.Architecture,
		"database":     info.Database,
		"user":         gin.H{"id": principal.UserID, "name": principal.Name, "role": principal.Role},
		"capabilities": capabilities,
	})
}
