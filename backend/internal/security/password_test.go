// 密码校验测试覆盖家庭账号允许的最小密码长度边界。
package security

import (
	"strings"
	"testing"
)

// TestValidatePasswordRequiresAtLeastThreeCharacters 验证密码最少 3 个字符且不限制最大长度。
func TestValidatePasswordRequiresAtLeastThreeCharacters(t *testing.T) {
	for _, password := range []string{"", "a", "密码"} {
		if err := ValidatePassword(password); err == nil {
			t.Fatalf("password %q should be rejected", password)
		}
	}
	for _, password := range []string{"abc", "密码啊", strings.Repeat("a", 4096)} {
		if err := ValidatePassword(password); err != nil {
			t.Fatalf("password length %d rejected: %v", len([]rune(password)), err)
		}
	}
}
