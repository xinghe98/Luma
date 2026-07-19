package security

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// tokenBytes 是自动生成 Token 使用的安全随机字节数。
const tokenBytes = 32

// LoadOrCreateToken 读取现有 Token，或以安全权限原子创建新 Token。
func LoadOrCreateToken(path string) (string, bool, error) {
	content, err := os.ReadFile(path)
	if err == nil {
		if info, statErr := os.Stat(path); statErr != nil {
			return "", false, fmt.Errorf("stat API token file %q: %w", path, statErr)
		} else if runtime.GOOS != "windows" && info.Mode().Perm()&0o077 != 0 {
			return "", false, fmt.Errorf("API token file %q must not be accessible by group or others", path)
		}
		token := strings.TrimSpace(string(content))
		if err := validateToken(token); err != nil {
			return "", false, fmt.Errorf("invalid API token file %q: %w", path, err)
		}
		return token, false, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return "", false, fmt.Errorf("read API token file %q: %w", path, err)
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", false, fmt.Errorf("create API token directory: %w", err)
	}
	random := make([]byte, tokenBytes)
	if _, err := rand.Read(random); err != nil {
		return "", false, fmt.Errorf("generate API token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(random)
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if errors.Is(err, os.ErrExist) {
			return LoadOrCreateToken(path)
		}
		return "", false, fmt.Errorf("create API token file: %w", err)
	}
	if _, err := file.WriteString(token + "\n"); err != nil {
		_ = file.Close()
		return "", false, fmt.Errorf("write API token file: %w", err)
	}
	if err := file.Close(); err != nil {
		return "", false, fmt.Errorf("close API token file: %w", err)
	}
	return token, true, nil
}

// MatchesToken 使用常量时间比较两个 Token，降低时序攻击风险。
func MatchesToken(expected, actual string) bool {
	if expected == "" || len(expected) != len(actual) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(expected), []byte(actual)) == 1
}

// TokenAuthenticator 使用单个服务端 Token 验证 Bearer 认证头。
type TokenAuthenticator struct {
	// expected 是从安全文件加载的预期 Token。
	expected string
}

// NewTokenAuthenticator 创建 Token 认证器并校验 Token 强度。
func NewTokenAuthenticator(token string) (*TokenAuthenticator, error) {
	if err := validateToken(token); err != nil {
		return nil, err
	}
	return &TokenAuthenticator{expected: token}, nil
}

// AuthenticateAuthorization 验证完整的 HTTP Authorization 请求头。
func (a *TokenAuthenticator) AuthenticateAuthorization(authorization string) bool {
	parts := strings.Fields(authorization)
	return len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") && MatchesToken(a.expected, parts[1])
}

// validateToken 校验 Token 的最小长度和字符约束。
func validateToken(token string) error {
	if len(token) < 32 {
		return errors.New("token must contain at least 32 characters")
	}
	if strings.ContainsAny(token, " \t\r\n") {
		return errors.New("token must not contain whitespace")
	}
	return nil
}
