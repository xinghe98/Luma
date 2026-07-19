package platform

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// SecureIDGenerator 使用系统安全随机源生成业务标识。
type SecureIDGenerator struct{}

// New 使用指定前缀生成 128 位随机业务标识。
func (SecureIDGenerator) New(prefix string) (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("生成随机业务标识: %w", err)
	}
	return prefix + "_" + hex.EncodeToString(value), nil
}
