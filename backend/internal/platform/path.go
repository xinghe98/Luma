package platform

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

// PathPolicy 负责验证媒体源路径没有逃出允许目录白名单。
type PathPolicy struct {
	// allowedRoots 保存配置中的根路径，每次校验都会重新解析其最终目标。
	allowedRoots []string
	mu           sync.RWMutex
}

// NewPathPolicy 创建路径策略并验证初始白名单；后续每次校验都会重新解析白名单最终目标。
func NewPathPolicy(roots []string) (*PathPolicy, error) {
	policy := &PathPolicy{}
	if err := policy.ReplaceAllowedRoots(roots); err != nil {
		return nil, err
	}
	return policy, nil
}

// ReplaceAllowedRoots 原子替换白名单；任一目录无效时保留原策略并返回错误。
func (p *PathPolicy) ReplaceAllowedRoots(roots []string) error {
	configured := make([]string, 0, len(roots))
	for _, root := range roots {
		_, err := canonicalExistingDir(root)
		if err != nil {
			return fmt.Errorf("canonicalize allowed root %q: %w", root, err)
		}
		configured = append(configured, filepath.Clean(root))
	}
	if len(configured) == 0 {
		return fmt.Errorf("at least one allowed root is required")
	}
	p.mu.Lock()
	p.allowedRoots = configured
	p.mu.Unlock()
	return nil
}

// ValidateSourceRoot 校验媒体源目录并返回其最终规范路径。
func (p *PathPolicy) ValidateSourceRoot(candidate string) (string, error) {
	resolved, err := canonicalExistingDir(candidate)
	if err != nil {
		return "", err
	}
	p.mu.RLock()
	roots := append([]string(nil), p.allowedRoots...)
	p.mu.RUnlock()
	for _, configuredRoot := range roots {
		root, rootErr := canonicalExistingDir(configuredRoot)
		if rootErr != nil {
			continue
		}
		inside, err := pathWithin(root, resolved)
		if err == nil && inside {
			if runtime.GOOS == "windows" {
				return strings.ToLower(resolved), nil
			}
			return resolved, nil
		}
	}
	return "", fmt.Errorf("path %q is outside security.allowed_roots", candidate)
}

// CanonicalDataPath 返回数据路径的最终绝对位置；不存在的尾部按最近现有父目录推导。
// 任一现有路径组件是符号链接或 Reparse Point 时返回错误，避免可写数据目录被重绑定。
func CanonicalDataPath(path string) (string, error) {
	if !filepath.IsAbs(path) {
		return "", fmt.Errorf("path must be absolute")
	}
	current := filepath.Clean(path)
	var missing []string
	for {
		_, err := os.Lstat(current)
		if err == nil {
			break
		}
		if !errors.Is(err, os.ErrNotExist) {
			return "", err
		}
		parent := filepath.Dir(current)
		if parent == current {
			return "", err
		}
		missing = append(missing, filepath.Base(current))
		current = parent
	}
	for component := current; ; component = filepath.Dir(component) {
		info, err := os.Lstat(component)
		if err != nil {
			return "", err
		}
		if IsLinkLike(info) {
			return "", fmt.Errorf("路径组件 %q 是符号链接或 Reparse Point", component)
		}
		parent := filepath.Dir(component)
		if parent == component {
			break
		}
	}
	resolved, err := filepath.EvalSymlinks(current)
	if err != nil {
		return "", err
	}
	for i := len(missing) - 1; i >= 0; i-- {
		resolved = filepath.Join(resolved, missing[i])
	}
	return filepath.Clean(resolved), nil
}

// ValidateNoLinkPath 确认从根目录到候选文件的每个组件都不是链接类对象。
// 调用方仍需在打开文件后复核句柄身份，以覆盖检查与打开之间的竞争窗口。
func ValidateNoLinkPath(root, candidate string) error {
	inside, err := pathWithin(filepath.Clean(root), filepath.Clean(candidate))
	if err != nil || !inside {
		return fmt.Errorf("候选路径逃出受控根目录")
	}
	relative, err := filepath.Rel(filepath.Clean(root), filepath.Clean(candidate))
	if err != nil {
		return err
	}
	current := filepath.Clean(root)
	components := []string{"."}
	if relative != "." {
		components = strings.Split(relative, string(filepath.Separator))
	}
	for _, component := range components {
		if component != "." {
			current = filepath.Join(current, component)
		}
		info, err := os.Lstat(current)
		if err != nil {
			return err
		}
		if IsLinkLike(info) {
			return fmt.Errorf("路径组件 %q 是符号链接或 Reparse Point", current)
		}
	}
	return nil
}

// ValidateDescendant 解析候选路径的最终目标并确认其仍位于媒体源根目录内。
func ValidateDescendant(root, candidate string) (string, error) {
	resolved, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		return "", err
	}
	inside, err := pathWithin(filepath.Clean(root), filepath.Clean(resolved))
	if err != nil {
		return "", err
	}
	if !inside {
		return "", fmt.Errorf("路径 %q 的最终目标逃出媒体源根目录", candidate)
	}
	return filepath.Clean(resolved), nil
}

// NormalizeRelativePath 校验并规范化数据库使用的媒体相对路径。
func NormalizeRelativePath(path string) (string, error) {
	cleaned := filepath.Clean(path)
	if path == "" || filepath.IsAbs(path) || cleaned == ".." || strings.HasPrefix(cleaned, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("媒体相对路径不合法")
	}
	cleaned = filepath.ToSlash(cleaned)
	if runtime.GOOS == "windows" {
		cleaned = strings.ToLower(cleaned)
	}
	return cleaned, nil
}

// canonicalExistingDir 解析绝对路径、符号链接并确认目标是现有目录。
func canonicalExistingDir(path string) (string, error) {
	if !filepath.IsAbs(path) {
		return "", fmt.Errorf("path must be absolute")
	}
	absolute, err := filepath.Abs(filepath.Clean(path))
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(resolved)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", fmt.Errorf("path is not a directory")
	}
	directory, err := os.Open(resolved)
	if err != nil {
		return "", fmt.Errorf("目录不可读: %w", err)
	}
	defer directory.Close()
	if _, err := directory.Readdirnames(1); err != nil && !errors.Is(err, io.EOF) {
		return "", fmt.Errorf("目录不可读: %w", err)
	}
	return filepath.Clean(resolved), nil
}

// pathWithin 使用平台路径规则判断候选目录是否位于根目录内。
func pathWithin(root, candidate string) (bool, error) {
	if runtime.GOOS == "windows" {
		root = strings.ToLower(root)
		candidate = strings.ToLower(candidate)
	}
	relative, err := filepath.Rel(root, candidate)
	if err != nil {
		return false, err
	}
	return relative == "." || (relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && !filepath.IsAbs(relative)), nil
}
