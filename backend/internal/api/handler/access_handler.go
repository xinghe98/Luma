// 访问管理 Handler 负责管理员创建账号、重置密码、管理会话和媒体源授权。
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
)

// AccessUseCase 描述管理员管理账号、会话和来源授权所需的能力。
type AccessUseCase interface {
	ListUsers(context.Context) ([]domain.User, error)
	CreateUser(context.Context, string, string, string) (domain.User, error)
	UpdateUser(context.Context, string, *string, *bool) (domain.User, error)
	ResetPassword(context.Context, string, string) error
	ListSessions(context.Context, string) ([]domain.APIToken, error)
	RevokeSession(context.Context, string) error
	ListGrants(context.Context, string) ([]string, error)
	GrantSource(context.Context, string, string) error
	RevokeSource(context.Context, string, string) error
}

type idempotentAccessUseCase interface {
	CreateUserIdempotent(context.Context, string, string, string, string) (domain.User, error)
}

// AccessHandler 将管理请求映射为访问控制用例。
type AccessHandler struct{ service AccessUseCase }

// NewAccessHandler 创建管理员访问控制 Handler。
func NewAccessHandler(service AccessUseCase) (*AccessHandler, error) {
	if service == nil {
		return nil, errors.New("访问控制用例不能为空")
	}
	return &AccessHandler{service: service}, nil
}

type accessUserJSON struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	Enabled   bool   `json:"enabled"`
	Online    bool   `json:"online"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type sessionJSON struct {
	ID        string  `json:"id"`
	UserID    string  `json:"user_id"`
	Name      string  `json:"name"`
	ExpiresAt *string `json:"expires_at"`
	RevokedAt *string `json:"revoked_at"`
	CreatedAt string  `json:"created_at"`
}

// ListUsers 返回可管理账号列表。
func (h *AccessHandler) ListUsers(c *gin.Context) {
	users, err := h.service.ListUsers(c.Request.Context())
	if err != nil {
		response.FromError(c, err)
		return
	}
	items := make([]accessUserJSON, 0, len(users))
	for _, user := range users {
		items = append(items, presentAccessUser(user))
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// CreateUser 创建成员及其初始登录密码。
func (h *AccessHandler) CreateUser(c *gin.Context) {
	var body struct {
		Name      string `json:"name"`
		Username  string `json:"username"`
		Password  string `json:"password"`
		RequestID string `json:"request_id"`
	}
	if err := apirequest.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	var user domain.User
	var err error
	if idempotent, ok := h.service.(idempotentAccessUseCase); ok {
		user, err = idempotent.CreateUserIdempotent(c.Request.Context(), body.Name, body.Username, body.Password, body.RequestID)
	} else {
		user, err = h.service.CreateUser(c.Request.Context(), body.Name, body.Username, body.Password)
	}
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusCreated, presentAccessUser(user))
}

// UpdateUser 更新成员显示名称或启用状态。
func (h *AccessHandler) UpdateUser(c *gin.Context) {
	var body struct {
		Name    *string `json:"name"`
		Enabled *bool   `json:"enabled"`
	}
	if err := apirequest.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	if body.Name == nil && body.Enabled == nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "至少提供一个可更新字段", nil)
		return
	}
	user, err := h.service.UpdateUser(c.Request.Context(), c.Param("id"), body.Name, body.Enabled)
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentAccessUser(user))
}

// ResetPassword 重置成员密码并使其所有设备退出登录。
func (h *AccessHandler) ResetPassword(c *gin.Context) {
	var body struct {
		Password string `json:"password"`
	}
	if err := apirequest.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	if err := h.service.ResetPassword(c.Request.Context(), c.Param("id"), body.Password); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// ListSessions 返回成员的登录设备。
func (h *AccessHandler) ListSessions(c *gin.Context) {
	sessions, err := h.service.ListSessions(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	items := make([]sessionJSON, 0, len(sessions))
	for _, session := range sessions {
		items = append(items, presentSession(session))
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// RevokeSession 使一个指定登录设备立即失效。
func (h *AccessHandler) RevokeSession(c *gin.Context) {
	if err := h.service.RevokeSession(c.Request.Context(), c.Param("id")); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *AccessHandler) ListGrants(c *gin.Context) {
	ids, err := h.service.ListGrants(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"source_ids": ids})
}

func (h *AccessHandler) GrantSource(c *gin.Context) {
	if err := h.service.GrantSource(c.Request.Context(), c.Param("id"), c.Param("sourceId")); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *AccessHandler) RevokeSource(c *gin.Context) {
	if err := h.service.RevokeSource(c.Request.Context(), c.Param("id"), c.Param("sourceId")); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func presentAccessUser(user domain.User) accessUserJSON {
	return accessUserJSON{ID: user.ID, Name: user.Name, Username: user.Username, Role: user.Role, Enabled: user.Enabled, Online: user.Online, CreatedAt: user.CreatedAt.UTC().Format(time.RFC3339Nano), UpdatedAt: user.UpdatedAt.UTC().Format(time.RFC3339Nano)}
}

func presentSession(session domain.APIToken) sessionJSON {
	result := sessionJSON{ID: session.ID, UserID: session.UserID, Name: session.Name, CreatedAt: session.CreatedAt.UTC().Format(time.RFC3339Nano)}
	if session.ExpiresAt != nil {
		value := session.ExpiresAt.UTC().Format(time.RFC3339Nano)
		result.ExpiresAt = &value
	}
	if session.RevokedAt != nil {
		value := session.RevokedAt.UTC().Format(time.RFC3339Nano)
		result.RevokedAt = &value
	}
	return result
}
