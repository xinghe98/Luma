package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

type client struct {
	origin  string
	session string
	http    *http.Client
}

func (c client) call(method, endpoint string, body any) error {
	data, err := c.request(method, endpoint, body)
	if err != nil {
		return err
	}
	if len(data) == 0 {
		fmt.Println("ok")
		return nil
	}
	var value any
	if json.Unmarshal(data, &value) == nil {
		return printJSON(value)
	}
	fmt.Println(string(data))
	return nil
}

func (c client) callJSON(method, endpoint string, body, target any) error {
	data, err := c.request(method, endpoint, body)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(data, target); err != nil {
		return fmt.Errorf("decode response JSON: %w", err)
	}
	return nil
}

func (c client) request(method, endpoint string, body any) ([]byte, error) {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(data)
	}
	request, err := http.NewRequest(method, c.origin+endpoint, reader)
	if err != nil {
		return nil, err
	}
	request.Header.Set("Authorization", "Bearer "+c.session)
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := c.http.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %s: %s", response.Status, strings.TrimSpace(string(data)))
	}
	return data, nil
}

// login 仅在命令启动时提交管理员密码和安装级标识，后续请求复用内存中的会话。
func (c *client) login(username, password, deviceKey string) error {
	if strings.TrimSpace(username) == "" || password == "" {
		return errors.New("set LUMA_ADMIN_USERNAME and LUMA_ADMIN_PASSWORD_FILE or provide -username and -password-file")
	}
	data, err := c.requestWithoutAuthorization(http.MethodPost, "/api/v1/auth/login", map[string]string{
		"username": username, "password": password, "device_name": "luma-admin", "device_key": deviceKey,
	})
	if err != nil {
		return err
	}
	var result struct {
		SessionToken string `json:"session_token"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return err
	}
	if result.SessionToken == "" {
		return errors.New("login response did not include a session")
	}
	c.session = result.SessionToken
	return nil
}

// logout 尝试撤销当前进程取得的会话；未登录时不发请求。
func (c client) logout() error {
	if c.session == "" {
		return nil
	}
	_, err := c.request(http.MethodPost, "/api/v1/auth/logout", nil)
	return err
}

func (c client) requestWithoutAuthorization(method, endpoint string, body any) ([]byte, error) {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(data)
	}
	request, err := http.NewRequest(method, c.origin+endpoint, reader)
	if err != nil {
		return nil, err
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := c.http.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %s: %s", response.Status, strings.TrimSpace(string(data)))
	}
	return data, nil
}

func printJSON(value any) error {
	pretty, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(pretty))
	return nil
}

func readAdminPassword(filename string) (string, error) {
	if strings.TrimSpace(filename) == "" {
		return "", errors.New("set LUMA_ADMIN_PASSWORD_FILE or provide -password-file")
	}
	data, err := os.ReadFile(filename)
	if err != nil {
		return "", err
	}
	value := strings.TrimSpace(string(data))
	if value == "" {
		return "", errors.New("administrator password file is empty")
	}
	return value, nil
}

// loadOrCreateAdminDeviceKey 读取安装级随机标识；路径为空时使用用户配置目录。
// 首次创建采用排他写入，多个 CLI 同时启动时会复用胜出的完整值。
func loadOrCreateAdminDeviceKey(filename string) (string, error) {
	if strings.TrimSpace(filename) == "" {
		configDir, err := os.UserConfigDir()
		if err != nil {
			return "", fmt.Errorf("locate user config directory: %w", err)
		}
		filename = filepath.Join(configDir, "Luma", "admin-device-key")
	}
	if key, err := readAdminDeviceKey(filename); err == nil {
		return key, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(filename), 0o700); err != nil {
		return "", fmt.Errorf("create device key directory: %w", err)
	}
	random := make([]byte, 24)
	if _, err := rand.Read(random); err != nil {
		return "", fmt.Errorf("generate device key: %w", err)
	}
	key := base64.RawURLEncoding.EncodeToString(random)
	file, err := os.OpenFile(filename, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if errors.Is(err, os.ErrExist) {
		return waitForAdminDeviceKey(filename)
	}
	if err != nil {
		return "", fmt.Errorf("create device key file: %w", err)
	}
	if _, err := file.WriteString(key + "\n"); err != nil {
		_ = file.Close()
		_ = os.Remove(filename)
		return "", fmt.Errorf("write device key file: %w", err)
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(filename)
		return "", fmt.Errorf("close device key file: %w", err)
	}
	return key, nil
}

// waitForAdminDeviceKey 等待并发创建者完成短文件写入，避免读取到暂时的空文件。
func waitForAdminDeviceKey(filename string) (string, error) {
	var err error
	for range 20 {
		var key string
		key, err = readAdminDeviceKey(filename)
		if err == nil {
			return key, nil
		}
		time.Sleep(5 * time.Millisecond)
	}
	return "", err
}

// readAdminDeviceKey 校验持久化标识，避免空值或损坏内容创建不可替换会话。
func readAdminDeviceKey(filename string) (string, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return "", err
	}
	key := strings.TrimSpace(string(data))
	if key == "" || len(key) > 64 {
		return "", errors.New("administrator device key file must contain 1 to 64 characters")
	}
	return key, nil
}

func validateAdminOrigin(raw string, allowInsecure bool) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return "", errors.New("-server must be an absolute http(s) origin")
	}
	if parsed.Scheme == "http" && !allowInsecure && !isLoopback(parsed.Hostname()) {
		return "", errors.New("plain HTTP management is limited to loopback; use HTTPS or -allow-insecure")
	}
	parsed.Path = path.Clean("/" + strings.Trim(parsed.Path, "/"))
	if parsed.Path == "/" {
		parsed.Path = ""
	}
	parsed.RawQuery, parsed.Fragment = "", ""
	return strings.TrimSuffix(parsed.String(), "/"), nil
}

func isLoopback(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
