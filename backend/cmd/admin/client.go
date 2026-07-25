package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path"
	"strings"
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

// login 仅在命令启动时提交管理员密码，后续请求复用内存中的会话。
func (c *client) login(username, password string) error {
	if strings.TrimSpace(username) == "" || password == "" {
		return errors.New("set LUMA_ADMIN_USERNAME and LUMA_ADMIN_PASSWORD_FILE or provide -username and -password-file")
	}
	data, err := c.requestWithoutAuthorization(http.MethodPost, "/api/v1/auth/login", map[string]string{
		"username": username, "password": password, "device_name": "luma-admin",
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
