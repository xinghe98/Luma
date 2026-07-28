package handler

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/service"
)

// StreamUseCase 定义原始媒体 Handler 所需的业务能力。
type StreamUseCase interface {
	Open(context.Context, string, string) (domain.StreamContent, error)
	OpenOriginal(context.Context, string, string) (domain.StreamContent, error)
	GetLocation(context.Context, string, string) (domain.StreamLocation, error)
	OpenTranscodeStream(context.Context, string, string) (io.ReadCloser, string, error)
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
func (h *StreamHandler) Stream(c *gin.Context) {
	transcode := strings.TrimSpace(c.Query("transcode"))
	id := c.Param("id")
	userID := c.GetString("user_id")
	if transcode == "audio" || transcode == "1" || transcode == "true" {
		h.serveTranscode(c, id, userID)
		return
	}
	location, err := h.service.GetLocation(c.Request.Context(), id, userID)
	if err == nil && service.IsAudioTranscodeRequired(location.AudioCodec) {
		h.serveTranscode(c, id, userID)
		return
	}
	content, err := h.service.Open(c.Request.Context(), id, userID)
	h.serve(c, content, err)
}

// Original 处理 GET 和 HEAD /api/v1/media/:id/original。
func (h *StreamHandler) Original(c *gin.Context) {
	content, err := h.service.OpenOriginal(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	h.serve(c, content, err)
}

func (h *StreamHandler) serveTranscode(c *gin.Context, id, userID string) {
	reader, mimeType, err := h.service.OpenTranscodeStream(c.Request.Context(), id, userID)
	if err != nil {
		response.FromError(c, err)
		return
	}
	defer reader.Close()
	c.Header("Content-Type", mimeType)
	c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Status(http.StatusOK)
	_, _ = io.Copy(c.Writer, reader)
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
