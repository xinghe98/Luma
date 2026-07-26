// 密码哈希组件负责使用 Argon2id 保存和校验登录密码，不保存明文密码。
package security

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
)

const (
	passwordSaltBytes = 16
	passwordKeyBytes  = 32
	passwordMemoryKB  = 19 * 1024
	passwordTime      = 2
	passwordThreads   = 1
	passwordMinChars  = 10
	passwordMaxChars  = 128
	passwordMaxBytes  = 512
)

// HashPassword 生成可携带参数的 Argon2id 密码摘要；调用方不得记录 password。
func HashPassword(password string) (string, error) {
	if err := ValidatePassword(password); err != nil {
		return "", err
	}
	salt := make([]byte, passwordSaltBytes)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("生成密码盐: %w", err)
	}
	key := argon2.IDKey([]byte(password), salt, passwordTime, passwordMemoryKB, passwordThreads, passwordKeyBytes)
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s", passwordMemoryKB, passwordTime, passwordThreads,
		base64.RawStdEncoding.EncodeToString(salt), base64.RawStdEncoding.EncodeToString(key)), nil
}

// VerifyPassword 以常量时间比较校验密码；损坏摘要、非法编码、超限输入与密码错误都返回 false。
func VerifyPassword(encoded, password string) bool {
	if !utf8.ValidString(password) || len(password) > passwordMaxBytes || utf8.RuneCountInString(password) > passwordMaxChars {
		return false
	}
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" || parts[2] != "v=19" || parts[3] != fmt.Sprintf("m=%d,t=%d,p=%d", passwordMemoryKB, passwordTime, passwordThreads) {
		return false
	}
	salt, saltErr := base64.RawStdEncoding.DecodeString(parts[4])
	expected, hashErr := base64.RawStdEncoding.DecodeString(parts[5])
	if saltErr != nil || hashErr != nil || len(salt) != passwordSaltBytes || len(expected) != passwordKeyBytes {
		return false
	}
	actual := argon2.IDKey([]byte(password), salt, passwordTime, passwordMemoryKB, passwordThreads, passwordKeyBytes)
	return subtle.ConstantTimeCompare(expected, actual) == 1
}

// ConsumePasswordVerificationTime 为不存在的账号执行等量 Argon2 工作，降低用户名时序枚举风险。
func ConsumePasswordVerificationTime(password string) {
	salt := make([]byte, passwordSaltBytes)
	expected := make([]byte, passwordKeyBytes)
	actual := argon2.IDKey([]byte(password), salt, passwordTime, passwordMemoryKB, passwordThreads, passwordKeyBytes)
	_ = subtle.ConstantTimeCompare(expected, actual)
}

// ValidatePassword 要求密码为 10 至 128 个字符且不超过 512 字节，允许有效 Unicode 与空白字符。
func ValidatePassword(password string) error {
	if !utf8.ValidString(password) {
		return errors.New("密码必须是有效的 UTF-8 文本")
	}
	length := utf8.RuneCountInString(password)
	if length < passwordMinChars {
		return errors.New("密码长度至少为 10 个字符")
	}
	if length > passwordMaxChars {
		return errors.New("密码长度最多为 128 个字符")
	}
	if len(password) > passwordMaxBytes {
		return errors.New("密码最多为 512 字节")
	}
	return nil
}
