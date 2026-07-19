package handler

import (
	"context"
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// HealthUseCase 定义健康检查 Handler 所需的业务能力。
type HealthUseCase interface {
	// Health 返回不访问外部资源的进程存活信息。
	Health(context.Context) domain.Health
}

// HealthHandler 将健康检查业务结果适配为 HTTP 响应。
type HealthHandler struct {
	// service 是注入的健康检查业务用例。
	service HealthUseCase
}

// NewHealthHandler 使用健康检查用例创建 Handler。
func NewHealthHandler(service HealthUseCase) (*HealthHandler, error) {
	if service == nil {
		return nil, errors.New("health use case is required")
	}
	return &HealthHandler{service: service}, nil
}

// Get 处理 GET /health 请求。
func (h *HealthHandler) Get(c *gin.Context) {
	health := h.service.Health(c.Request.Context())
	c.JSON(http.StatusOK, gin.H{"status": health.Status, "version": health.Version})
}
