package platform

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// PathPolicy 负责验证媒体源路径没有逃出允许目录白名单。
type PathPolicy struct {
	// allowedRoots 保存完成符号链接解析后的规范根目录。
	allowedRoots []string
}

// NewPathPolicy 创建路径策略，并预先规范化所有允许根目录。
func NewPathPolicy(roots []string) (*PathPolicy, error) {
	policy := &PathPolicy{allowedRoots: make([]string, 0, len(roots))}
	for _, root := range roots {
		resolved, err := canonicalExistingDir(root)
		if err != nil {
			return nil, fmt.Errorf("canonicalize allowed root %q: %w", root, err)
		}
		policy.allowedRoots = append(policy.allowedRoots, resolved)
	}
	if len(policy.allowedRoots) == 0 {
		return nil, fmt.Errorf("at least one allowed root is required")
	}
	return policy, nil
}

// ValidateSourceRoot 校验媒体源目录并返回其最终规范路径。
func (p *PathPolicy) ValidateSourceRoot(candidate string) (string, error) {
	resolved, err := canonicalExistingDir(candidate)
	if err != nil {
		return "", err
	}
	for _, root := range p.allowedRoots {
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
