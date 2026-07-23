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

// AccessUseCase 是管理员 API 所需的成员与授权能力。
type AccessUseCase interface {
	ListUsers(context.Context) ([]domain.User, error)
	CreateUser(context.Context, string) (domain.User, error)
	UpdateUser(context.Context, string, *string, *bool) (domain.User, error)
	ListTokens(context.Context, string) ([]domain.APIToken, error)
	IssueToken(context.Context, string, string, *time.Time) (domain.IssuedToken, error)
	RevokeToken(context.Context, string) error
	ListGrants(context.Context, string) ([]string, error)
	GrantSource(context.Context, string, string) error
	RevokeSource(context.Context, string, string) error
}

type AccessHandler struct{ service AccessUseCase }

type idempotentAccessUseCase interface {
	CreateUserIdempotent(context.Context, string, string) (domain.User, error)
	IssueTokenIdempotent(context.Context, string, string, *time.Time, string) (domain.IssuedToken, error)
}

func NewAccessHandler(service AccessUseCase) (*AccessHandler, error) {
	if service == nil {
		return nil, errors.New("访问控制用例不能为空")
	}
	return &AccessHandler{service: service}, nil
}

type accessUserJSON struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Role      string `json:"role"`
	Enabled   bool   `json:"enabled"`
	Online    bool   `json:"online"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type accessTokenJSON struct {
	ID          string  `json:"id"`
	UserID      string  `json:"user_id"`
	Name        string  `json:"name"`
	TokenPrefix string  `json:"token_prefix"`
	ExpiresAt   *string `json:"expires_at"`
	RevokedAt   *string `json:"revoked_at"`
	CreatedAt   string  `json:"created_at"`
	Secret      string  `json:"token,omitempty"`
}

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

func (h *AccessHandler) CreateUser(c *gin.Context) {
	var body struct {
		Name      string `json:"name"`
		RequestID string `json:"request_id"`
	}
	if err := apirequest.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	var user domain.User
	var err error
	if idempotent, ok := h.service.(idempotentAccessUseCase); ok {
		user, err = idempotent.CreateUserIdempotent(c.Request.Context(), body.Name, body.RequestID)
	} else {
		user, err = h.service.CreateUser(c.Request.Context(), body.Name)
	}
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusCreated, presentAccessUser(user))
}

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

func (h *AccessHandler) ListTokens(c *gin.Context) {
	tokens, err := h.service.ListTokens(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	items := make([]accessTokenJSON, 0, len(tokens))
	for _, token := range tokens {
		items = append(items, presentAccessToken(token, ""))
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (h *AccessHandler) IssueToken(c *gin.Context) {
	var body struct {
		Name      string  `json:"name"`
		ExpiresAt *string `json:"expires_at"`
		RequestID string  `json:"request_id"`
	}
	if err := apirequest.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	var expires *time.Time
	if body.ExpiresAt != nil {
		value, err := time.Parse(time.RFC3339, *body.ExpiresAt)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "expires_at 必须是 RFC3339 时间", nil)
			return
		}
		expires = &value
	}
	var issued domain.IssuedToken
	var err error
	if idempotent, ok := h.service.(idempotentAccessUseCase); ok {
		issued, err = idempotent.IssueTokenIdempotent(c.Request.Context(), c.Param("id"), body.Name, expires, body.RequestID)
	} else {
		issued, err = h.service.IssueToken(c.Request.Context(), c.Param("id"), body.Name, expires)
	}
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusCreated, presentAccessToken(issued.Token, issued.Secret))
}

func (h *AccessHandler) RevokeToken(c *gin.Context) {
	if err := h.service.RevokeToken(c.Request.Context(), c.Param("id")); err != nil {
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
	return accessUserJSON{ID: user.ID, Name: user.Name, Role: user.Role, Enabled: user.Enabled, Online: user.Online,
		CreatedAt: user.CreatedAt.UTC().Format(time.RFC3339Nano), UpdatedAt: user.UpdatedAt.UTC().Format(time.RFC3339Nano)}
}

func presentAccessToken(token domain.APIToken, secret string) accessTokenJSON {
	result := accessTokenJSON{ID: token.ID, UserID: token.UserID, Name: token.Name, TokenPrefix: token.TokenPrefix,
		CreatedAt: token.CreatedAt.UTC().Format(time.RFC3339Nano), Secret: secret}
	if token.ExpiresAt != nil {
		value := token.ExpiresAt.UTC().Format(time.RFC3339Nano)
		result.ExpiresAt = &value
	}
	if token.RevokedAt != nil {
		value := token.RevokedAt.UTC().Format(time.RFC3339Nano)
		result.RevokedAt = &value
	}
	return result
}
