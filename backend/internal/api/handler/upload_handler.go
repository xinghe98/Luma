// 本文件职责：POST /api/v1/sources/{id}/images 的 HTTP 适配。
// 以 MultipartReader 流式读取单 file 部件，正文整体有界，
// 授权与来源状态检查由业务用例在任何大量正文读取之前完成。

package handler

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// UploadUseCase 定义图片上传 Handler 所需的业务能力。
type UploadUseCase interface {
	Upload(ctx context.Context, sourceID, userID string, input domain.UploadedImage) (domain.UploadResult, error)
}

// UploadHandler 将图片上传用例适配为 Gin API。
type UploadHandler struct {
	// service 是注入的上传业务用例。
	service UploadUseCase
}

// NewUploadHandler 创建图片上传 Handler。
func NewUploadHandler(service UploadUseCase) (*UploadHandler, error) {
	if service == nil {
		return nil, errors.New("上传业务用例不能为空")
	}
	return &UploadHandler{service: service}, nil
}

// uploadBodyOverhead 是 multipart 边界、头部与 file 部件之外的余量；
// 整请求体被限制在 64MiB 文件上限加该余量内，防止无界磁盘/内存消耗。
const uploadBodyOverhead int64 = 1 << 20

// uploadReadBudget 是单次上传请求读取正文的最长时间。
// 默认 server.read_timeout 对 64MiB 手机网络过短；只对本路由放宽到有界值。
const uploadReadBudget = 5 * time.Minute

// Create 处理 POST /api/v1/sources/:id/images。
// multipart/form-data 只接受单个 file 部件；任何多余部件都拒绝整次上传。
// 正文读取前已先经业务用例完成授权与来源状态检查。
func (h *UploadHandler) Create(c *gin.Context) {
	if !requireUploadContentType(c) {
		return
	}
	if c.Request.ContentLength > domain.MaxUploadImageBytes+uploadBodyOverhead {
		response.Error(c, http.StatusRequestEntityTooLarge, "UPLOAD_TOO_LARGE", "上传图片超过64MiB上限", nil)
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, domain.MaxUploadImageBytes+uploadBodyOverhead)
	// 本路由单独放宽正文读取期限；不调整全局 server 超时。
	controller := http.NewResponseController(c.Writer)
	_ = controller.SetReadDeadline(time.Now().Add(uploadReadBudget))
	reader, err := c.Request.MultipartReader()
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "multipart 请求体无效", nil)
		return
	}
	part, err := reader.NextPart()
	if err != nil {
		if errors.Is(err, io.EOF) {
			response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "缺少 file 上传部件", nil)
			return
		}
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "multipart 请求体无效", nil)
		return
	}
	if part.FormName() != "file" || part.FileName() == "" {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "缺少 file 上传部件", nil)
		return
	}
	// 业务用例先做授权/来源状态，再流式落盘；CommitCheck 在文件流写完后、
	// 正式发布前验证请求恰好结束（无多余部件或截断尾部），
	// 否则本次上传中止且不留已落盘文件。
	input := domain.UploadedImage{
		Reader: part, Filename: part.FileName(),
		CommitCheck: func() error {
			next, nextErr := reader.NextPart()
			if next != nil {
				_ = next.Close()
			}
			if !errors.Is(nextErr, io.EOF) {
				return fmt.Errorf("%w: multipart 只能包含一个 file 部件", domain.ErrInvalidRequest)
			}
			return nil
		},
	}
	result, err := h.service.Upload(c.Request.Context(), c.Param("id"), c.GetString("user_id"), input)
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"media_id": result.MediaID, "filename": result.Filename})
}

// requireUploadContentType 只接受 multipart/form-data 请求体。
func requireUploadContentType(c *gin.Context) bool {
	contentType := c.GetHeader("Content-Type")
	mediaType, params, err := mime.ParseMediaType(contentType)
	if err != nil || mediaType != "multipart/form-data" || params["boundary"] == "" {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "请求必须是 multipart/form-data", nil)
		return false
	}
	return true
}
