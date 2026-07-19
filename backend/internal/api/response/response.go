package response

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ErrorBody 表示所有 API 错误响应的统一外层结构。
type ErrorBody struct {
	// Error 保存具体错误信息。
	Error ErrorDetail `json:"error"`
}

// ErrorDetail 表示可供客户端稳定处理的错误详情。
type ErrorDetail struct {
	// Code 是稳定的机器可读错误码。
	Code string `json:"code"`
	// Message 是面向调用方的错误说明。
	Message string `json:"message"`
	// Details 保存可选的结构化补充信息。
	Details any `json:"details"`
}

// Error 写入统一格式的 JSON 错误并终止当前 Gin 处理链。
func Error(c *gin.Context, status int, code, message string, details any) {
	c.AbortWithStatusJSON(status, ErrorBody{Error: ErrorDetail{
		Code: code, Message: message, Details: details,
	}})
}

// FromError 将领域错误映射为稳定 HTTP 状态码和统一错误码。
func FromError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, domain.ErrInvalidRequest):
		Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
	case errors.Is(err, domain.ErrForbiddenPath):
		Error(c, http.StatusForbidden, "FORBIDDEN_PATH", "媒体源路径不在允许目录中", nil)
	case errors.Is(err, domain.ErrSourceNotFound):
		Error(c, http.StatusNotFound, "SOURCE_NOT_FOUND", "媒体源不存在", nil)
	case errors.Is(err, domain.ErrSourceConflict):
		Error(c, http.StatusConflict, "SOURCE_CONFLICT", "媒体源已存在", nil)
	case errors.Is(err, domain.ErrSourceOffline):
		Error(c, http.StatusServiceUnavailable, "SOURCE_OFFLINE", "媒体源当前不可访问", nil)
	case errors.Is(err, domain.ErrScanNotFound):
		Error(c, http.StatusNotFound, "SCAN_NOT_FOUND", "扫描任务不存在", nil)
	case errors.Is(err, domain.ErrScanAlreadyRunning):
		Error(c, http.StatusConflict, "SCAN_ALREADY_RUNNING", "媒体源已有扫描任务", nil)
	case errors.Is(err, domain.ErrMediaNotFound), errors.Is(err, domain.ErrContentNotFound):
		Error(c, http.StatusNotFound, "MEDIA_NOT_FOUND", "媒体不存在", nil)
	case errors.Is(err, domain.ErrThumbnailNotFound):
		Error(c, http.StatusNotFound, "THUMBNAIL_NOT_FOUND", "缩略图不存在", nil)
	case errors.Is(err, domain.ErrThumbnailTooLarge):
		Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error", nil)
	case errors.Is(err, domain.ErrTagNotFound):
		Error(c, http.StatusNotFound, "TAG_NOT_FOUND", "标签不存在", nil)
	case errors.Is(err, domain.ErrTagConflict):
		Error(c, http.StatusConflict, "TAG_ALREADY_EXISTS", "标签名称已存在", nil)
	case errors.Is(err, domain.ErrRevisionConflict):
		Error(c, http.StatusConflict, "REVISION_CONFLICT", "数据已被其他请求修改", nil)
	case errors.Is(err, domain.ErrMediaDurationUnavailable):
		Error(c, http.StatusConflict, "MEDIA_DURATION_UNAVAILABLE", "媒体时长暂不可用", nil)
	case errors.Is(err, domain.ErrMediaNotPlayable):
		Error(c, http.StatusUnprocessableEntity, "MEDIA_NOT_PLAYABLE", "媒体不支持播放进度", nil)
	default:
		Error(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error", nil)
	}
}
