// 密码校验测试覆盖账号密码的字符数、字节数与编码边界。
package security

import (
	"strings"
	"testing"
)

// TestValidatePasswordEnforcesLengthLimits 验证密码字符数和 UTF-8 字节数上下限。
func TestValidatePasswordEnforcesLengthLimits(t *testing.T) {
	for _, password := range []string{"", "123456789", strings.Repeat("a", passwordMaxChars+1), strings.Repeat("界", 171), string([]byte{0xff})} {
		if err := ValidatePassword(password); err == nil {
			t.Fatalf("password with %d chars and %d bytes should be rejected", len([]rune(password)), len(password))
		}
	}
	for _, password := range []string{"1234567890", "密码长度刚好十个字符啊", strings.Repeat("a", passwordMaxChars), strings.Repeat("界", 128)} {
		if err := ValidatePassword(password); err != nil {
			t.Fatalf("password with %d chars and %d bytes rejected: %v", len([]rune(password)), len(password), err)
		}
	}
}

// TestVerifyPasswordRejectsOversizedInput 验证超长登录输入不会进入 Argon2 计算。
func TestVerifyPasswordRejectsOversizedInput(t *testing.T) {
	hash, err := HashPassword("correct horse battery")
	if err != nil {
		t.Fatal(err)
	}
	if VerifyPassword(hash, strings.Repeat("a", passwordMaxBytes+1)) {
		t.Fatal("oversized password was accepted")
	}
}
