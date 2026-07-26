// 本文件验证登录错误分类与进程内失败限流容器的容量边界。
package handler

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type authenticationUseCaseStub struct{ loginErr error }

// Login 返回测试指定的登录错误。
func (s authenticationUseCaseStub) Login(context.Context, string, string, string, string) (domain.IssuedSession, error) {
	return domain.IssuedSession{}, s.loginErr
}

// Logout 为认证接口提供无副作用的测试实现。
func (authenticationUseCaseStub) Logout(context.Context, string) error { return nil }

// TestAuthHandlerLoginClassifiesServiceErrors 验证登录失败只对未授权错误计数并返回对应状态码。
func TestAuthHandlerLoginClassifiesServiceErrors(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tests := []struct {
		name         string
		err          error
		status       int
		failureCount int
	}{
		{name: "unauthorized", err: domain.ErrUnauthorized, status: http.StatusUnauthorized, failureCount: 1},
		{name: "invalid request", err: fmt.Errorf("%w: bad device", domain.ErrInvalidRequest), status: http.StatusBadRequest},
		{name: "internal", err: errors.New("database unavailable"), status: http.StatusInternalServerError},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			handler, err := NewAuthHandler(authenticationUseCaseStub{loginErr: test.err})
			if err != nil {
				t.Fatal(err)
			}
			router := gin.New()
			router.POST("/login", handler.Login)
			request := httptest.NewRequest(http.MethodPost, "/login", bytes.NewBufferString(
				`{"username":"alice","password":"correct horse battery","device_name":"phone"}`))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if response.Code != test.status {
				t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
			}
			key := loginKey("192.0.2.1", "alice")
			if got := handler.failures[key].count; got != test.failureCount {
				t.Fatalf("failure count=%d, want %d", got, test.failureCount)
			}
		})
	}
}

// TestAuthHandlerFailureMapHasHardLimit 验证失败键容器不会突破固定容量。
func TestAuthHandlerFailureMapHasHardLimit(t *testing.T) {
	handler, err := NewAuthHandler(authenticationUseCaseStub{})
	if err != nil {
		t.Fatal(err)
	}
	for index := 0; index < maxLoginFailureKeys+100; index++ {
		handler.recordFailure(fmt.Sprintf("key-%d", index))
	}
	if len(handler.failures) != maxLoginFailureKeys {
		t.Fatalf("failure key count=%d, want %d", len(handler.failures), maxLoginFailureKeys)
	}
	if handler.failures[fmt.Sprintf("key-%d", maxLoginFailureKeys+99)].count != 1 {
		t.Fatal("new failure was not admitted at capacity")
	}
}
