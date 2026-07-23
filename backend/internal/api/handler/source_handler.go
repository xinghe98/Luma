package handler

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	apirequest "github.com/xinghe98/Luma/backend/internal/api/request"
	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/service"
)

// SourceUseCase 定义媒体源 Handler 所需的业务能力。
type SourceUseCase interface {
	// List 返回全部媒体源。
	ListVisible(context.Context, string) ([]domain.Source, error)
	// Create 创建本地媒体源。
	Create(context.Context, domain.CreateSourceCommand) (domain.Source, error)
	// Update 部分更新媒体源。
	Update(context.Context, domain.UpdateSourceCommand) (domain.Source, error)
	// Delete 软删除媒体源并释放根路径。
	Delete(context.Context, string) error
}

// SourceHandler 将媒体源业务用例适配为 HTTP API。
type SourceHandler struct {
	// service 是注入的媒体源业务用例。
	service SourceUseCase
	managed ManagedSourceUseCase
}

// ManagedSourceUseCase creates a source together with its configuration,
// grants and initial scan. It is deliberately separate from legacy sources.
type ManagedSourceUseCase interface {
	Create(context.Context, service.ManagedMediaSourceCommand) (service.ManagedMediaSourceResult, error)
}

// NewSourceHandler 使用媒体源业务用例创建 Handler。
func NewSourceHandler(service SourceUseCase, managed ...ManagedSourceUseCase) (*SourceHandler, error) {
	if service == nil {
		return nil, errors.New("媒体源业务用例不能为空")
	}
	result := &SourceHandler{service: service}
	if len(managed) > 0 {
		result.managed = managed[0]
	}
	return result, nil
}

type createManagedSourceRequest struct {
	Name        string   `json:"name"`
	RootPath    string   `json:"root_path"`
	LibraryKind string   `json:"library_kind"`
	UserIDs     []string `json:"user_ids"`
}

// CreateManaged provisions a source through the administrator-only route.
func (h *SourceHandler) CreateManaged(c *gin.Context) {
	if h.managed == nil {
		response.Error(c, http.StatusNotImplemented, "NOT_IMPLEMENTED", "媒体源管理不可用", nil)
		return
	}
	var request createManagedSourceRequest
	if err := apirequest.DecodeJSON(c, &request); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	created, err := h.managed.Create(c.Request.Context(), service.ManagedMediaSourceCommand{
		Name: request.Name, RootPath: request.RootPath, LibraryKind: request.LibraryKind, UserIDs: request.UserIDs,
	})
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"source": presentSource(created.Source), "scan_job": presentScanJob(created.Scan)})
}

// createSourceRequest 表示创建媒体源的 HTTP 请求体。
type createSourceRequest struct {
	// Name 是用户可见名称。
	Name string `json:"name"`
	// RootPath 是仅在请求中接收且永不返回的真实目录。
	RootPath    string `json:"root_path"`
	LibraryKind string `json:"library_kind"`
}

// updateSourceRequest 表示媒体源部分更新请求体。
type updateSourceRequest struct {
	// Name 非空时更新展示名称。
	Name *string `json:"name"`
	// RootPath 非空时重新校验并更新真实目录。
	RootPath *string `json:"root_path"`
	// Enabled 非空时启用或禁用媒体源。
	Enabled     *bool   `json:"enabled"`
	LibraryKind *string `json:"library_kind"`
}

// sourceResponse 是媒体源 API 响应，对应 sources 表公开字段（不含 root_path）。
type sourceResponse struct {
	// ID 对应 sources.id。
	ID string `json:"id"`
	// Name 对应 sources.name。
	Name string `json:"name"`
	// Type 对应 sources.source_type。
	Type        string `json:"type"`
	LibraryKind string `json:"library_kind"`
	// Enabled 对应 sources.enabled。
	Enabled bool `json:"enabled"`
	// Status 对应 sources.status。
	Status string `json:"status"`
	// LastScanID 对应 sources.last_scan_id。
	LastScanID string `json:"last_scan_id,omitempty"`
	// LastSeenAt 对应 sources.last_seen_at_ms 的 ISO 8601 UTC。
	LastSeenAt *string `json:"last_seen_at,omitempty"`
	// CreatedAt 对应 sources.created_at_ms 的 ISO 8601 UTC。
	CreatedAt string `json:"created_at"`
	// UpdatedAt 对应 sources.updated_at_ms 的 ISO 8601 UTC。
	UpdatedAt string `json:"updated_at"`
}

// List 处理 GET /api/v1/sources 请求。
func (h *SourceHandler) List(c *gin.Context) {
	sources, err := h.service.ListVisible(c.Request.Context(), c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	items := make([]sourceResponse, 0, len(sources))
	for _, source := range sources {
		items = append(items, presentSource(source))
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// Create 处理 POST /api/v1/sources 请求。
func (h *SourceHandler) Create(c *gin.Context) {
	var request createSourceRequest
	if err := apirequest.DecodeJSON(c, &request); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	source, err := h.service.Create(c.Request.Context(), domain.CreateSourceCommand{Name: request.Name, RootPath: request.RootPath, LibraryKind: request.LibraryKind})
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusCreated, presentSource(source))
}

// Update 处理 PATCH /api/v1/sources/:id 请求。
func (h *SourceHandler) Update(c *gin.Context) {
	var request updateSourceRequest
	if err := apirequest.DecodeJSON(c, &request); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	if request.Name == nil && request.RootPath == nil && request.Enabled == nil && request.LibraryKind == nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "至少提供一个可更新字段", nil)
		return
	}
	source, err := h.service.Update(c.Request.Context(), domain.UpdateSourceCommand{
		ID: c.Param("id"), Name: request.Name, RootPath: request.RootPath, Enabled: request.Enabled, LibraryKind: request.LibraryKind,
	})
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentSource(source))
}

// Delete 处理 DELETE /api/v1/sources/:id 请求。
func (h *SourceHandler) Delete(c *gin.Context) {
	if err := h.service.Delete(c.Request.Context(), c.Param("id")); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// presentSource 将领域媒体源转换为不含真实根路径的 API DTO。
func presentSource(source domain.Source) sourceResponse {
	result := sourceResponse{
		ID: source.ID, Name: source.Name, Type: source.Type, LibraryKind: source.LibraryKind, Enabled: source.Enabled,
		Status: source.Status, LastScanID: source.LastScanID,
		CreatedAt: source.CreatedAt.UTC().Format(time.RFC3339Nano),
		UpdatedAt: source.UpdatedAt.UTC().Format(time.RFC3339Nano),
	}
	if source.LastSeenAt != nil {
		value := source.LastSeenAt.UTC().Format(time.RFC3339Nano)
		result.LastSeenAt = &value
	}
	return result
}
