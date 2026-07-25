// 会话密钥组件负责生成登录后的一次性会话密钥及其数据库摘要。
package security

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
)

const sessionSecretBytes = 32

// GenerateSessionSecret 生成仅在登录响应中返回一次的随机会话密钥。
func GenerateSessionSecret() (string, error) {
	random := make([]byte, sessionSecretBytes)
	if _, err := rand.Read(random); err != nil {
		return "", fmt.Errorf("生成会话密钥: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(random), nil
}

// HashSessionSecret 返回用于数据库匹配的固定长度摘要，不保留会话明文。
func HashSessionSecret(secret string) string {
	sum := sha256.Sum256([]byte(secret))
	return hex.EncodeToString(sum[:])
}
