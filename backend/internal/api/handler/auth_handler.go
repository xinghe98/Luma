// 登录 Handler 提供公开登录与受保护登出接口，并在进程内限制失败尝试。
package handler

import (
	"context"
	"errors"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/middleware"
	apirequest "github.com/xinghe98/Luma/backend/internal/api/request"
	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// AuthenticationUseCase 是登录与登出所需的最小用例边界。
type AuthenticationUseCase interface {
	Login(context.Context, string, string, string) (domain.IssuedSession, error)
	Logout(context.Context, string) error
}

// AuthHandler 管理登录限流状态；该状态只影响当前服务进程。
type AuthHandler struct {
	service  AuthenticationUseCase
	mu       sync.Mutex
	failures map[string]loginFailure
}

type loginFailure struct {
	count int
	until time.Time
}

// NewAuthHandler 创建认证 Handler。
func NewAuthHandler(service AuthenticationUseCase) (*AuthHandler, error) {
	if service == nil {
		return nil, errors.New("认证用例不能为空")
	}
	return &AuthHandler{service: service, failures: map[string]loginFailure{}}, nil
}

// Login 验证用户名密码并返回一条新的设备会话。
func (h *AuthHandler) Login(c *gin.Context) {
	var body struct {
		Username   string `json:"username"`
		Password   string `json:"password"`
		DeviceName string `json:"device_name"`
	}
	if err := apirequest.DecodeJSON(c, &body); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	key := loginKey(c.ClientIP(), body.Username)
	if retryAfter, blocked := h.blocked(key); blocked {
		c.Header("Retry-After", retryAfter)
		response.Error(c, http.StatusTooManyRequests, "RATE_LIMITED", "too many login attempts", nil)
		return
	}
	issued, err := h.service.Login(c.Request.Context(), body.Username, body.Password, body.DeviceName)
	if err != nil {
		h.recordFailure(key)
		response.Error(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid username or password", nil)
		return
	}
	h.clearFailure(key)
	var expiresAt any
	if issued.Session.ExpiresAt != nil {
		expiresAt = issued.Session.ExpiresAt.UTC().Format(time.RFC3339Nano)
	}
	c.JSON(http.StatusOK, gin.H{"session_token": issued.Secret, "token_type": "Bearer", "expires_at": expiresAt, "user": presentAccessUser(issued.User)})
}

// Logout 撤销认证中间件识别出的当前设备会话。
func (h *AuthHandler) Logout(c *gin.Context) {
	if err := h.service.Logout(c.Request.Context(), middleware.Principal(c).CredentialID); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func loginKey(ip, username string) string {
	return net.JoinHostPort(ip, "") + "\x00" + strings.ToLower(strings.TrimSpace(username))
}
func (h *AuthHandler) blocked(key string) (string, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	value, ok := h.failures[key]
	if !ok || time.Now().After(value.until) {
		if ok {
			delete(h.failures, key)
		}
		return "", false
	}
	if value.count < 5 {
		return "", false
	}
	return "900", true
}
func (h *AuthHandler) recordFailure(key string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	now := time.Now()
	value := h.failures[key]
	if now.After(value.until) {
		value = loginFailure{until: now.Add(15 * time.Minute)}
	}
	value.count++
	value.until = now.Add(15 * time.Minute)
	h.failures[key] = value
	if len(h.failures) > 4096 {
		for old, candidate := range h.failures {
			if now.After(candidate.until) {
				delete(h.failures, old)
				break
			}
		}
	}
}
func (h *AuthHandler) clearFailure(key string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.failures, key)
}
