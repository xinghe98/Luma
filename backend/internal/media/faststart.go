// 非 faststart 的 MP4/MOV 在播放前 copy remux 到 cache_dir/faststart。
// 不改写媒体源；失败时调用方继续使用原文件。
package media

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

const (
	faststartCacheDir = "faststart"
	faststartTimeout  = 15 * time.Minute
)

// FaststartCache 把 moov 在尾部的文件优化到本地缓存后供 Range 直出。
type FaststartCache struct {
	executable string
	root       string
	runner     commandRunner
	mu         sync.Mutex
	inFlight   map[string]*faststartFlight
}

type faststartFlight struct {
	done chan struct{}
	err  error
}

// NewFaststartCache 在 cacheDir/faststart 下创建可复用的 remux 缓存。
func NewFaststartCache(executable, cacheDir string) (*FaststartCache, error) {
	return newFaststartCache(executable, cacheDir, execRunner{})
}

func newFaststartCache(executable, cacheDir string, runner commandRunner) (*FaststartCache, error) {
	if executable == "" || runner == nil {
		return nil, fmt.Errorf("ffmpeg 路径和命令执行器不能为空")
	}
	if !filepath.IsAbs(cacheDir) {
		return nil, fmt.Errorf("缓存目录必须是绝对路径")
	}
	root := filepath.Join(filepath.Clean(cacheDir), faststartCacheDir)
	if err := os.MkdirAll(root, 0o750); err != nil {
		return nil, fmt.Errorf("创建 faststart 缓存目录: %w", err)
	}
	return &FaststartCache{
		executable: executable,
		root:       root,
		runner:     runner,
		inFlight:   make(map[string]*faststartFlight),
	}, nil
}

// Prepare 若源文件需要 faststart，则关闭源并返回缓存副本；否则原样返回 source。
func (c *FaststartCache) Prepare(ctx context.Context, location domain.StreamLocation, source domain.OpenedContent) (domain.OpenedContent, error) {
	if source.Reader == nil {
		return source, nil
	}
	if !shouldConsiderFaststart(location) {
		return source, nil
	}
	needed, err := NeedsFastStart(source.Reader)
	_, _ = source.Reader.Seek(0, 0)
	if err != nil || !needed {
		return source, nil
	}
	cached, err := c.ensure(ctx, location, source.Size, source.ModifiedAt)
	if err != nil {
		_, _ = source.Reader.Seek(0, 0)
		return source, nil
	}
	_ = source.Reader.Close()
	return cached, nil
}

func shouldConsiderFaststart(location domain.StreamLocation) bool {
	if location.MediaType != domain.MediaTypeVideo {
		return false
	}
	switch strings.ToLower(filepath.Ext(location.Filename)) {
	case ".mp4", ".m4v", ".mov":
		return true
	default:
		return false
	}
}

func (c *FaststartCache) ensure(ctx context.Context, location domain.StreamLocation, size int64, modifiedAt time.Time) (domain.OpenedContent, error) {
	if err := ctx.Err(); err != nil {
		return domain.OpenedContent{}, err
	}
	if err := validateCacheMediaID(location.ID); err != nil {
		return domain.OpenedContent{}, err
	}
	finalPath := c.cachePath(location.ID, size, modifiedAt)
	if opened, err := openCachedContent(finalPath); err == nil {
		return opened, nil
	}
	if err := c.remuxShared(ctx, location, size, modifiedAt, finalPath); err != nil {
		return domain.OpenedContent{}, err
	}
	return openCachedContent(finalPath)
}

func (c *FaststartCache) remuxShared(ctx context.Context, location domain.StreamLocation, size int64, modifiedAt time.Time, finalPath string) error {
	key := finalPath
	c.mu.Lock()
	if flight, ok := c.inFlight[key]; ok {
		c.mu.Unlock()
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-flight.done:
			return flight.err
		}
	}
	flight := &faststartFlight{done: make(chan struct{})}
	c.inFlight[key] = flight
	c.mu.Unlock()

	err := c.remux(ctx, location, size, modifiedAt, finalPath)
	flight.err = err
	close(flight.done)

	c.mu.Lock()
	delete(c.inFlight, key)
	c.mu.Unlock()
	return err
}

func (c *FaststartCache) remux(parent context.Context, location domain.StreamLocation, size int64, modifiedAt time.Time, finalPath string) error {
	if _, err := os.Stat(finalPath); err == nil {
		return nil
	}
	input := domain.MediaInput{
		ID: location.ID, RootPath: location.RootPath, RelativePath: location.RelativePath,
		MediaType: location.MediaType, FileSize: size, ModifiedAtMS: modifiedAt.UnixMilli(),
	}
	secured, err := openInputPath(input)
	if err != nil {
		return err
	}
	defer secured.Close()
	if secured.info.Size() != size {
		return fmt.Errorf("媒体文件大小已变化")
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(parent), faststartTimeout)
	defer cancel()
	temporary, err := os.CreateTemp(c.root, "."+location.ID+"-*.mp4")
	if err != nil {
		return fmt.Errorf("创建 faststart 临时文件: %w", err)
	}
	temporaryPath := temporary.Name()
	_ = temporary.Close()
	if err := secured.verify(); err != nil {
		_ = os.Remove(temporaryPath)
		return err
	}
	args := []string{
		"-hide_banner", "-nostdin", "-loglevel", "error", "-y",
		"-i", secured.path,
		"-map", "0", "-c", "copy", "-movflags", "+faststart",
		temporaryPath,
	}
	_, runErr := c.runner.Run(ctx, c.executable, args...)
	identityErr := secured.verify()
	if runErr != nil {
		_ = os.Remove(temporaryPath)
		if identityErr != nil {
			return identityErr
		}
		return runErr
	}
	if identityErr != nil {
		_ = os.Remove(temporaryPath)
		return identityErr
	}
	info, err := os.Stat(temporaryPath)
	if err != nil || !info.Mode().IsRegular() || info.Size() <= 0 {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("faststart 输出无效")
	}
	if err := atomicReplace(temporaryPath, finalPath); err != nil {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("发布 faststart 缓存: %w", err)
	}
	c.removeStaleCaches(location.ID, finalPath)
	return nil
}

func (c *FaststartCache) cachePath(id string, size int64, modifiedAt time.Time) string {
	name := fmt.Sprintf("%s-%d-%d.mp4", id, size, modifiedAt.Unix())
	return filepath.Join(c.root, name)
}

func (c *FaststartCache) removeStaleCaches(id, keep string) {
	entries, err := os.ReadDir(c.root)
	if err != nil {
		return
	}
	prefix := id + "-"
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasPrefix(entry.Name(), prefix) || !strings.HasSuffix(entry.Name(), ".mp4") {
			continue
		}
		path := filepath.Join(c.root, entry.Name())
		if path == keep {
			continue
		}
		_ = os.Remove(path)
	}
}

func openCachedContent(path string) (domain.OpenedContent, error) {
	file, err := os.Open(path)
	if err != nil {
		return domain.OpenedContent{}, err
	}
	info, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return domain.OpenedContent{}, err
	}
	if !info.Mode().IsRegular() || info.Size() <= 0 {
		_ = file.Close()
		return domain.OpenedContent{}, fmt.Errorf("faststart 缓存不是有效文件")
	}
	return domain.OpenedContent{
		Reader: file, Size: info.Size(), ModifiedAt: info.ModTime().UTC(),
	}, nil
}

func validateCacheMediaID(id string) error {
	if id == "" || filepath.Base(id) != id || id == "." || id == ".." {
		return fmt.Errorf("媒体 ID 不适合作为缓存键")
	}
	return nil
}
