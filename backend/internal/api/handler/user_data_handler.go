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

// UserDataUseCase 定义用户媒体数据 Handler 所需能力。
type UserDataUseCase interface {
	Get(context.Context, string, string) (domain.MediaUserData, error)
	Update(context.Context, domain.UpdateUserDataCommand) (domain.MediaUserData, error)
	UpdateProgress(context.Context, string, string, int64, int64) (domain.MediaUserData, error)
}

// UserDataHandler 处理用户媒体数据和播放进度请求。
type UserDataHandler struct {
	service UserDataUseCase
}

// NewUserDataHandler 创建用户数据 Handler。
func NewUserDataHandler(service UserDataUseCase) (*UserDataHandler, error) {
	if service == nil {
		return nil, errors.New("用户数据业务用例不能为空")
	}
	return &UserDataHandler{service: service}, nil
}

type updateUserDataRequest struct {
	BaseRevision *int64                 `json:"base_revision"`
	CustomTitle  optionalJSON[string]   `json:"custom_title"`
	Favorite     optionalJSON[bool]     `json:"favorite"`
	Notes        optionalJSON[string]   `json:"notes"`
	TagIDs       optionalJSON[[]string] `json:"tag_ids"`
}

type updateProgressRequest struct {
	PositionMS   *int64 `json:"position_ms"`
	BaseRevision *int64 `json:"base_revision"`
}

type mediaUserDataJSON struct {
	MediaID      string    `json:"media_id"`
	CustomTitle  *string   `json:"custom_title"`
	Favorite     bool      `json:"favorite"`
	Notes        *string   `json:"notes"`
	ProgressMS   int64     `json:"progress_ms"`
	Completed    bool      `json:"completed"`
	LastPlayedAt *string   `json:"last_played_at"`
	Tags         []tagJSON `json:"tags"`
	Revision     int64     `json:"revision"`
	CreatedAt    *string   `json:"created_at"`
	UpdatedAt    *string   `json:"updated_at"`
}

// Get 处理 GET /api/v1/media/:id/user-data。
func (h *UserDataHandler) Get(c *gin.Context) {
	data, err := h.service.Get(c.Request.Context(), c.GetString("user_id"), c.Param("id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentMediaUserData(data))
}

// Update 处理 PATCH /api/v1/media/:id/user-data。
func (h *UserDataHandler) Update(c *gin.Context) {
	var body updateUserDataRequest
	if err := request.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	if body.BaseRevision == nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "base_revision 必填且不能为 null", nil)
		return
	}
	data, err := h.service.Update(c.Request.Context(), domain.UpdateUserDataCommand{
		UserID: c.GetString("user_id"), MediaID: c.Param("id"), BaseRevision: *body.BaseRevision,
		CustomTitle: body.CustomTitle.patchField(), Favorite: body.Favorite.patchField(),
		Notes: body.Notes.patchField(), TagIDs: body.TagIDs.patchField(),
	})
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentMediaUserData(data))
}

// UpdateProgress 处理 PUT /api/v1/media/:id/progress。
func (h *UserDataHandler) UpdateProgress(c *gin.Context) {
	var body updateProgressRequest
	if err := request.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	if body.PositionMS == nil || body.BaseRevision == nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "position_ms 和 base_revision 必填且不能为 null", nil)
		return
	}
	data, err := h.service.UpdateProgress(c.Request.Context(), c.GetString("user_id"), c.Param("id"), *body.PositionMS, *body.BaseRevision)
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentMediaUserData(data))
}

func presentMediaUserData(data domain.MediaUserData) mediaUserDataJSON {
	result := mediaUserDataJSON{
		MediaID: data.MediaID, CustomTitle: data.CustomTitle, Favorite: data.Favorite, Notes: data.Notes,
		ProgressMS: data.ProgressMS, Completed: data.Completed, Tags: make([]tagJSON, 0, len(data.Tags)), Revision: data.Revision,
	}
	for _, tag := range data.Tags {
		result.Tags = append(result.Tags, presentTag(tag))
	}
	result.LastPlayedAt = formatOptionalTime(data.LastPlayedAt)
	result.CreatedAt = formatOptionalTime(data.CreatedAt)
	result.UpdatedAt = formatOptionalTime(data.UpdatedAt)
	return result
}

func formatOptionalTime(value *time.Time) *string {
	if value == nil {
		return nil
	}
	formatted := value.UTC().Format(time.RFC3339Nano)
	return &formatted
}
