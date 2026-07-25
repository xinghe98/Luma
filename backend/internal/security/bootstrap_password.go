// 初始管理员密码文件仅用于首次初始化数据库中的本地管理员账号。
package security

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// LoadOrCreateBootstrapPassword 读取初始密码，缺失时安全生成并写入指定文件。
func LoadOrCreateBootstrapPassword(path string) (string, bool, error) {
	content, err := os.ReadFile(path)
	if err == nil {
		if info, statErr := os.Stat(path); statErr != nil {
			return "", false, fmt.Errorf("读取管理员密码文件状态: %w", statErr)
		} else if runtime.GOOS != "windows" && info.Mode().Perm()&0o077 != 0 {
			return "", false, errors.New("管理员密码文件不能向组或其他用户开放")
		}
		password := strings.TrimSpace(string(content))
		if err := ValidatePassword(password); err != nil {
			return "", false, fmt.Errorf("管理员密码文件无效: %w", err)
		}
		return password, false, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return "", false, fmt.Errorf("读取管理员密码文件: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", false, fmt.Errorf("创建管理员密码目录: %w", err)
	}
	random := make([]byte, 24)
	if _, err := rand.Read(random); err != nil {
		return "", false, fmt.Errorf("生成管理员密码: %w", err)
	}
	password := base64.RawURLEncoding.EncodeToString(random)
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if errors.Is(err, os.ErrExist) {
			return LoadOrCreateBootstrapPassword(path)
		}
		return "", false, fmt.Errorf("创建管理员密码文件: %w", err)
	}
	if _, err := file.WriteString(password + "\n"); err != nil {
		_ = file.Close()
		return "", false, fmt.Errorf("写入管理员密码文件: %w", err)
	}
	if err := file.Close(); err != nil {
		return "", false, fmt.Errorf("关闭管理员密码文件: %w", err)
	}
	return password, true, nil
}
