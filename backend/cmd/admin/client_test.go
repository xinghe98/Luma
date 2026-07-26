// 本文件借助临时文件与 HTTP 测试服务验证管理 CLI 的安装标识及单次会话生命周期。
package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

// TestLoadOrCreateAdminDeviceKeyStable 验证同一安装文件始终返回相同随机标识。
func TestLoadOrCreateAdminDeviceKeyStable(t *testing.T) {
	filename := filepath.Join(t.TempDir(), "config", "device-key")
	first, err := loadOrCreateAdminDeviceKey(filename)
	if err != nil {
		t.Fatal(err)
	}
	second, err := loadOrCreateAdminDeviceKey(filename)
	if err != nil {
		t.Fatal(err)
	}
	if first == "" || first != second || len(first) > 64 {
		t.Fatalf("device keys first=%q second=%q", first, second)
	}
}

// TestRunAlwaysAttemptsLogout 验证登录后的成功、命令错误和登出错误路径都遵守 best-effort 退出语义。
func TestRunAlwaysAttemptsLogout(t *testing.T) {
	for _, test := range []struct {
		name          string
		group         string
		action        string
		logoutStatus  int
		commandStatus int
		wantRunError  bool
	}{
		{name: "success", group: "sources", action: "list", logoutStatus: http.StatusNoContent, commandStatus: http.StatusOK},
		{name: "dispatch error", group: "unknown", action: "action", logoutStatus: http.StatusNoContent, wantRunError: true},
		{name: "request error", group: "sources", action: "list", logoutStatus: http.StatusNoContent, commandStatus: http.StatusInternalServerError, wantRunError: true},
		{name: "logout error is ignored", group: "sources", action: "list", logoutStatus: http.StatusInternalServerError, commandStatus: http.StatusOK},
	} {
		t.Run(test.name, func(t *testing.T) {
			var mu sync.Mutex
			loginCount, logoutCount := 0, 0
			var receivedDeviceKey string
			server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
				mu.Lock()
				defer mu.Unlock()
				switch request.URL.Path {
				case "/api/v1/auth/login":
					loginCount++
					var body map[string]string
					if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
						t.Errorf("decode login: %v", err)
					}
					receivedDeviceKey = body["device_key"]
					writer.Header().Set("Content-Type", "application/json")
					_, _ = writer.Write([]byte(`{"session_token":"session_test"}`))
				case "/api/v1/auth/logout":
					logoutCount++
					if request.Header.Get("Authorization") != "Bearer session_test" {
						t.Errorf("logout authorization = %q", request.Header.Get("Authorization"))
					}
					writer.WriteHeader(test.logoutStatus)
				case "/api/v1/sources":
					writer.WriteHeader(test.commandStatus)
					writer.Header().Set("Content-Type", "application/json")
					if test.commandStatus == http.StatusOK {
						_, _ = writer.Write([]byte(`{"items":[]}`))
					}
				default:
					writer.WriteHeader(http.StatusNotFound)
				}
			}))
			defer server.Close()

			passwordFile := filepath.Join(t.TempDir(), "password")
			if err := os.WriteFile(passwordFile, []byte("administrator-password\n"), 0o600); err != nil {
				t.Fatal(err)
			}
			deviceKeyFile := filepath.Join(t.TempDir(), "device-key")
			err := run([]string{
				"-server", server.URL, "-username", "admin", "-password-file", passwordFile,
				"-device-key-file", deviceKeyFile, test.group, test.action,
			})
			if (err != nil) != test.wantRunError {
				t.Fatalf("run error = %v", err)
			}
			mu.Lock()
			defer mu.Unlock()
			if loginCount != 1 || logoutCount != 1 || receivedDeviceKey == "" {
				t.Fatalf("login=%d logout=%d device_key=%q", loginCount, logoutCount, receivedDeviceKey)
			}
		})
	}
}

// TestRunDoesNotLogoutAfterFailedLogin 验证未取得会话时不会发送无效登出请求。
func TestRunDoesNotLogoutAfterFailedLogin(t *testing.T) {
	logoutCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/api/v1/auth/logout" {
			logoutCount++
		}
		writer.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()
	passwordFile := filepath.Join(t.TempDir(), "password")
	if err := os.WriteFile(passwordFile, []byte("administrator-password"), 0o600); err != nil {
		t.Fatal(err)
	}
	err := run([]string{
		"-server", server.URL, "-username", "admin", "-password-file", passwordFile,
		"-device-key-file", filepath.Join(t.TempDir(), "device-key"), "sources", "list",
	})
	if err == nil || logoutCount != 0 {
		t.Fatalf("run error=%v logout=%d", err, logoutCount)
	}
}
