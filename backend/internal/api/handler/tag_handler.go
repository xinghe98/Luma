package handler

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/request"
	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// TagUseCase 定义标签 Handler 所需能力。
type TagUseCase interface {
	List(context.Context, string) ([]domain.Tag, error)
	Create(context.Context, domain.CreateTagCommand) (domain.Tag, error)
	Update(context.Context, domain.UpdateTagCommand) (domain.Tag, error)
	Delete(context.Context, string, string) error
}

// TagHandler 处理标签 CRUD。
type TagHandler struct {
	service TagUseCase
}

// NewTagHandler 创建标签 Handler。
func NewTagHandler(service TagUseCase) (*TagHandler, error) {
	if service == nil {
		return nil, errors.New("标签业务用例不能为空")
	}
	return &TagHandler{service: service}, nil
}

type createTagRequest struct {
	Name string `json:"name"`
}

type updateTagRequest struct {
	Name         string `json:"name"`
	BaseRevision *int64 `json:"base_revision"`
}

type tagJSON struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	UsageCount int64  `json:"usage_count"`
	Revision   int64  `json:"revision"`
	CreatedAt  string `json:"created_at"`
	UpdatedAt  string `json:"updated_at"`
}

// List 处理 GET /api/v1/tags。
func (h *TagHandler) List(c *gin.Context) {
	tags, err := h.service.List(c.Request.Context(), c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	items := make([]tagJSON, 0, len(tags))
	for _, tag := range tags {
		items = append(items, presentTag(tag))
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// Create 处理 POST /api/v1/tags。
func (h *TagHandler) Create(c *gin.Context) {
	var body createTagRequest
	if err := request.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	tag, err := h.service.Create(c.Request.Context(), domain.CreateTagCommand{UserID: c.GetString("user_id"), Name: body.Name})
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusCreated, presentTag(tag))
}

// Update 处理 PATCH /api/v1/tags/:id。
func (h *TagHandler) Update(c *gin.Context) {
	var body updateTagRequest
	if err := request.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	if body.BaseRevision == nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "base_revision 必填且不能为 null", nil)
		return
	}
	tag, err := h.service.Update(c.Request.Context(), domain.UpdateTagCommand{
		UserID: c.GetString("user_id"), ID: c.Param("id"), Name: body.Name, BaseRevision: *body.BaseRevision,
	})
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentTag(tag))
}

// Delete 处理 DELETE /api/v1/tags/:id。
func (h *TagHandler) Delete(c *gin.Context) {
	if err := h.service.Delete(c.Request.Context(), c.GetString("user_id"), c.Param("id")); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func presentTag(tag domain.Tag) tagJSON {
	return tagJSON{
		ID: tag.ID, Name: tag.Name, UsageCount: tag.UsageCount, Revision: tag.Revision,
		CreatedAt: tag.CreatedAt.UTC().Format(time.RFC3339Nano), UpdatedAt: tag.UpdatedAt.UTC().Format(time.RFC3339Nano),
	}
}
