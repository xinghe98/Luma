// MetadataArtworkStore persists validated provider images below Luma's writable cache directory.
// It never reads from or writes to a media source.
package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const MaxMetadataArtworkBytes = 16 << 20

// MetadataArtworkStore owns the provider artwork cache namespace.
type MetadataArtworkStore struct {
	root string
}

// NewMetadataArtworkStore creates and validates the metadata artwork cache directory.
func NewMetadataArtworkStore(cacheDir string) (*MetadataArtworkStore, error) {
	if !filepath.IsAbs(cacheDir) {
		return nil, errors.New("元数据缓存目录必须是绝对路径")
	}
	root := filepath.Join(cacheDir, "metadata-artwork")
	if err := os.MkdirAll(root, 0o750); err != nil {
		return nil, fmt.Errorf("创建元数据图片缓存: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, err
	}
	return &MetadataArtworkStore{root: resolved}, nil
}

// Read reads one previously validated cache object.
func (s *MetadataArtworkStore) Read(storageKey string) ([]byte, error) {
	path, err := s.resolve(storageKey)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if len(data) > MaxMetadataArtworkBytes {
		return nil, errors.New("元数据图片缓存超过大小限制")
	}
	return data, nil
}

// Write atomically stores one provider image and returns its key and SHA-256 digest.
func (s *MetadataArtworkStore) Write(id string, source io.Reader) (string, string, error) {
	if source == nil || strings.TrimSpace(id) == "" {
		return "", "", errors.New("元数据图片写入参数无效")
	}
	temp, err := os.CreateTemp(s.root, ".artwork-*")
	if err != nil {
		return "", "", err
	}
	tempName := temp.Name()
	defer os.Remove(tempName)
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(temp, hash), io.LimitReader(source, MaxMetadataArtworkBytes+1))
	closeErr := temp.Close()
	if copyErr != nil {
		return "", "", copyErr
	}
	if closeErr != nil {
		return "", "", closeErr
	}
	if written > MaxMetadataArtworkBytes {
		return "", "", errors.New("Provider 图片超过 16 MiB 限制")
	}
	key := id + ".img"
	target, err := s.resolve(key)
	if err != nil {
		return "", "", err
	}
	_ = os.Remove(target)
	if err := os.Rename(tempName, target); err != nil {
		return "", "", err
	}
	return key, hex.EncodeToString(hash.Sum(nil)), nil
}

func (s *MetadataArtworkStore) resolve(key string) (string, error) {
	if key == "" || filepath.Base(key) != key || strings.ContainsAny(key, `/\`) {
		return "", errors.New("非法元数据图片缓存键")
	}
	candidate := filepath.Join(s.root, key)
	relative, err := filepath.Rel(s.root, candidate)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", errors.New("元数据图片缓存路径越界")
	}
	return candidate, nil
}
