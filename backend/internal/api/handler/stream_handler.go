package handler

import (
	"context"
	"errors"
	"net/http"
	"path"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// StreamUseCase 定义原始媒体 Handler 所需的业务能力。
type StreamUseCase interface {
	Plan(context.Context, string, string) (domain.StreamTarget, error)
	OpenSource(context.Context, string, string) (domain.StreamContent, error)
	OpenFaststart(context.Context, string, string, string) (domain.StreamContent, error)
	OpenOriginal(context.Context, string, string) (domain.StreamContent, error)
}

// StreamHandler 将原始媒体内容适配为支持 Range 的 HTTP 响应。
type StreamHandler struct {
	// service 提供原始媒体业务能力。
	service StreamUseCase
}

// NewStreamHandler 创建原始媒体 Handler。
func NewStreamHandler(service StreamUseCase) (*StreamHandler, error) {
	if service == nil {
		return nil, errors.New("原始媒体业务用例不能为空")
	}
	return &StreamHandler{service: service}, nil
}

// Stream 处理 GET 和 HEAD /api/v1/media/:id/stream。
// 入口只决定本次播放的固定表示并跳转到该表示的地址，不再直接返回字节。
func (h *StreamHandler) Stream(c *gin.Context) {
	target, err := h.service.Plan(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	// 同一媒体在预热前后会跳转到不同表示，因此这次跳转不能被任何中间层缓存。
	c.Header("Cache-Control", "no-store")
	c.Header("Location", streamTargetPath(c.Request.URL.Path, target))
	c.Status(http.StatusFound)
}

// Source 处理 GET 和 HEAD /api/v1/media/:id/stream/source。
// 该表示始终读取原始媒体文件，与预热进度无关。
func (h *StreamHandler) Source(c *gin.Context) {
	content, err := h.service.OpenSource(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	h.serve(c, content, err)
}

// Faststart 处理 GET 和 HEAD /api/v1/media/:id/stream/faststart/:fingerprint。
// 该表示始终读取入口固定的 faststart 副本，副本失效时明确失败。
func (h *StreamHandler) Faststart(c *gin.Context) {
	content, err := h.service.OpenFaststart(
		c.Request.Context(), c.Param("id"), c.GetString("user_id"), c.Param("fingerprint"))
	h.serve(c, content, err)
}

// Original 处理 GET 和 HEAD /api/v1/media/:id/original。
func (h *StreamHandler) Original(c *gin.Context) {
	content, err := h.service.OpenOriginal(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	h.serve(c, content, err)
}

// streamTargetPath 保留相对引用，让剥离路径前缀的反向代理也能正确定位内容地址。
func streamTargetPath(entryPath string, target domain.StreamTarget) string {
	entryPath = path.Base(entryPath)
	if target.Representation == domain.StreamRepresentationFaststart {
		return path.Join(entryPath, string(domain.StreamRepresentationFaststart), target.Fingerprint)
	}
	return path.Join(entryPath, string(domain.StreamRepresentationSource))
}

func (h *StreamHandler) serve(c *gin.Context, content domain.StreamContent, err error) {
	if err != nil {
		response.FromError(c, err)
		return
	}
	defer content.Reader.Close()
	c.Header("Content-Type", content.MIMEType)
	c.Header("ETag", content.ETag)
	c.Header("Cache-Control", "private, max-age=0, must-revalidate")
	c.Header("X-Content-Type-Options", "nosniff")
	http.ServeContent(c.Writer, c.Request, content.Name, content.ModifiedAt, content.Reader)
}
