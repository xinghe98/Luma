// 非 faststart 的 MP4/MOV 在播放前异步 copy remux 到 cache_dir/faststart。
// 不改写媒体源；缓存生成失败时调用方继续使用原文件。
package media

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

const (
	faststartCacheDir                = "faststart"
	faststartTimeout                 = 15 * time.Minute
	faststartQueueCapacity           = 32
	faststartFailureCooldown         = 5 * time.Minute
	defaultFaststartCacheMaxBytes int64 = 20 * 1024 * 1024 * 1024
)

// FaststartCache 把 moov 在尾部的文件异步优化到本地缓存后供 Range 直出。
type FaststartCache struct {
	executable string
	root       string
	maxBytes   int64
	runner     commandRunner
	logger     *slog.Logger

	mu      sync.Mutex
	queue   chan faststartTask
	pending map[faststartKey]struct{}
	failed  map[faststartKey]time.Time
}

type faststartKey struct {
	id         string
	size       int64
	modifiedMS int64
}

type faststartTask struct {
	key        faststartKey
	location   domain.StreamLocation
	size       int64
	modifiedAt time.Time
	finalPath  string
}

// NewFaststartCache 创建带有磁盘配额的异步 faststart 缓存。
// maxBytes 必须为正数；logger 为空时使用 slog 默认日志器。
func NewFaststartCache(executable, cacheDir string, maxBytes int64, logger *slog.Logger) (*FaststartCache, error) {
	return newFaststartCacheWithOptions(executable, cacheDir, maxBytes, logger, execRunner{})
}

// newFaststartCache 保留测试注入命令执行器的便捷构造方式。
func newFaststartCache(executable, cacheDir string, runner commandRunner) (*FaststartCache, error) {
	return newFaststartCacheWithOptions(executable, cacheDir, defaultFaststartCacheMaxBytes, slog.Default(), runner)
}

func newFaststartCacheWithOptions(executable, cacheDir string, maxBytes int64, logger *slog.Logger, runner commandRunner) (*FaststartCache, error) {
	if executable == "" || runner == nil {
		return nil, fmt.Errorf("ffmpeg 路径和命令执行器不能为空")
	}
	if maxBytes <= 0 {
		return nil, fmt.Errorf("faststart 缓存配额必须为正数")
	}
	if !filepath.IsAbs(cacheDir) {
		return nil, fmt.Errorf("缓存目录必须是绝对路径")
	}
	if logger == nil {
		logger = slog.Default()
	}
	root := filepath.Join(filepath.Clean(cacheDir), faststartCacheDir)
	if err := os.MkdirAll(root, 0o750); err != nil {
		return nil, fmt.Errorf("创建 faststart 缓存目录: %w", err)
	}
	return &FaststartCache{
		executable: executable,
		root:       root,
		maxBytes:   maxBytes,
		runner:     runner,
		logger:     logger,
		queue:      make(chan faststartTask, faststartQueueCapacity),
		pending:    make(map[faststartKey]struct{}),
		failed:     make(map[faststartKey]time.Time),
	}, nil
}

// Prepare 检查 faststart 缓存并异步排队生成；缓存未命中时立即返回原文件快照。
// 请求上下文不控制后台任务，任务由 jobs.Group 的生命周期上下文负责取消。
func (c *FaststartCache) Prepare(_ context.Context, location domain.StreamLocation, source domain.OpenedContent) (domain.OpenedContent, error) {
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
	if err := validateCacheMediaID(location.ID); err != nil {
		return source, nil
	}
	finalPath := c.cachePath(location.ID, source.Size, source.ModifiedAt)

	if opened, err := openCachedContent(finalPath, source.ModifiedAt); err == nil {
		_ = source.Reader.Close()
		c.touchCache(finalPath)
		return opened, nil
	}

	key := faststartKey{id: location.ID, size: source.Size, modifiedMS: source.ModifiedAt.UnixMilli()}
	task := faststartTask{
		key: key, location: location, size: source.Size,
		modifiedAt: source.ModifiedAt, finalPath: finalPath,
	}
	if !c.enqueue(task) {
		return source, nil
	}
	return source, nil
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

func (c *FaststartCache) enqueue(task faststartTask) bool {
	c.mu.Lock()
	now := time.Now()
	if deadline, ok := c.failed[task.key]; ok {
		if now.Before(deadline) {
			c.mu.Unlock()
			return false
		}
		delete(c.failed, task.key)
	}
	if _, ok := c.pending[task.key]; ok {
		c.mu.Unlock()
		return false
	}
	c.pending[task.key] = struct{}{}
	c.mu.Unlock()

	select {
	case c.queue <- task:
		return true
	default:
		c.mu.Lock()
		delete(c.pending, task.key)
		c.mu.Unlock()
		return false
	}
}

// Run 启动单个 faststart 预热 Worker，直到生命周期上下文取消。
// 单项 remux 失败只记录日志并进入冷却，不会终止任务组。
func (c *FaststartCache) Run(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}
	c.cleanupLRU("")
	for {
		select {
		case <-ctx.Done():
			c.dropPending()
			return nil
		case task := <-c.queue:
			err := c.remux(ctx, task.location, task.size, task.modifiedAt, task.finalPath)
			if err != nil {
				cancelled := ctx.Err() != nil
				c.finish(task.key, !cancelled)
				if cancelled {
					c.dropPending()
					return nil
				}
				c.logger.Warn("faststart 预热失败", "media_id", task.location.ID, "error", err)
				continue
			}
			c.finish(task.key, false)
			c.cleanupLRU(task.finalPath)
		}
	}
}

func (c *FaststartCache) finish(key faststartKey, failed bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.pending, key)
	if failed {
		c.failed[key] = time.Now().Add(faststartFailureCooldown)
	}
}

func (c *FaststartCache) dropPending() {
	c.mu.Lock()
	for key := range c.pending {
		delete(c.pending, key)
	}
	c.mu.Unlock()
	for {
		select {
		case <-c.queue:
		default:
			return
		}
	}
}

func (c *FaststartCache) remux(parent context.Context, location domain.StreamLocation, size int64, modifiedAt time.Time, finalPath string) error {
	if err := validateCacheMediaID(location.ID); err != nil {
		return err
	}
	if err := parent.Err(); err != nil {
		return err
	}
	valid, err := validCacheFile(finalPath)
	if err != nil {
		return err
	}
	if valid {
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
	if secured.info.Size() != size || secured.info.ModTime().UnixMilli() != modifiedAt.UnixMilli() {
		return fmt.Errorf("媒体文件大小或修改时间已变化")
	}
	if err := secured.verify(); err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(parent, faststartTimeout)
	defer cancel()
	temporary, err := os.CreateTemp(c.root, "."+location.ID+"-*.mp4")
	if err != nil {
		return fmt.Errorf("创建 faststart 临时文件: %w", err)
	}
	temporaryPath := temporary.Name()
	_ = temporary.Close()
	defer os.Remove(temporaryPath)

	args := []string{
		"-hide_banner", "-nostdin", "-loglevel", "error", "-y",
		"-i", secured.path,
		"-map", "0", "-c", "copy", "-movflags", "+faststart",
		temporaryPath,
	}
	_, runErr := c.runner.Run(ctx, c.executable, args...)
	identityErr := secured.verify()
	if runErr == nil {
		runErr = ctx.Err()
	}
	if runErr != nil {
		if identityErr != nil {
			return identityErr
		}
		return runErr
	}
	if identityErr != nil {
		return identityErr
	}
	info, err := os.Stat(temporaryPath)
	if err != nil || !info.Mode().IsRegular() || info.Size() <= 0 {
		return fmt.Errorf("faststart 输出无效")
	}
	if err := atomicReplace(temporaryPath, finalPath); err != nil {
		return fmt.Errorf("发布 faststart 缓存: %w", err)
	}
	c.removeStaleCaches(location.ID, finalPath)
	return nil
}

func validCacheFile(path string) (bool, error) {
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	if info.Mode().IsRegular() && info.Size() > 0 {
		return true, nil
	}
	if err := os.Remove(path); err != nil {
		return false, fmt.Errorf("移除无效 faststart 缓存: %w", err)
	}
	return false, nil
}

func (c *FaststartCache) cachePath(id string, size int64, modifiedAt time.Time) string {
	name := fmt.Sprintf("%s-%d-%d.mp4", id, size, modifiedAt.UnixMilli())
	return filepath.Join(c.root, name)
}

func (c *FaststartCache) removeStaleCaches(id, keep string) {
	entries, err := os.ReadDir(c.root)
	if err != nil {
		return
	}
	pending := c.pendingPaths()
	prefix := id + "-"
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasPrefix(entry.Name(), prefix) || !strings.EqualFold(filepath.Ext(entry.Name()), ".mp4") {
			continue
		}
		path := filepath.Join(c.root, entry.Name())
		if path == keep {
			continue
		}
		if _, ok := pending[path]; ok {
			continue
		}
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			c.logger.Warn("清理旧 faststart 缓存失败", "path", path, "error", err)
		}
	}
}

func (c *FaststartCache) touchCache(path string) {
	now := time.Now()
	if err := os.Chtimes(path, now, now); err != nil {
		c.logger.Warn("更新 faststart 缓存访问时间失败", "path", path, "error", err)
	}
}

func (c *FaststartCache) pendingPaths() map[string]struct{} {
	c.mu.Lock()
	defer c.mu.Unlock()
	paths := make(map[string]struct{}, len(c.pending))
	for key := range c.pending {
		paths[c.cachePath(key.id, key.size, time.UnixMilli(key.modifiedMS))] = struct{}{}
	}
	return paths
}

type cacheEntry struct {
	path    string
	size    int64
	modTime time.Time
}

func (c *FaststartCache) cleanupLRU(current string) {
	entries, err := os.ReadDir(c.root)
	if err != nil {
		return
	}
	pending := c.pendingPaths()
	candidates := make([]cacheEntry, 0, len(entries))
	var total int64
	for _, entry := range entries {
		if entry.IsDir() || strings.HasPrefix(entry.Name(), ".") || !strings.EqualFold(filepath.Ext(entry.Name()), ".mp4") {
			continue
		}
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		path := filepath.Join(c.root, entry.Name())
		candidates = append(candidates, cacheEntry{path: path, size: info.Size(), modTime: info.ModTime()})
		total += info.Size()
	}
	if total <= c.maxBytes {
		return
	}
	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].modTime.Equal(candidates[j].modTime) {
			return candidates[i].path < candidates[j].path
		}
		return candidates[i].modTime.Before(candidates[j].modTime)
	})
	protected := current
	if protected == "" && len(candidates) > 0 {
		newest := candidates[len(candidates)-1]
		if newest.size > c.maxBytes {
			protected = newest.path
		}
	}
	for _, candidate := range candidates {
		if total <= c.maxBytes {
			break
		}
		if candidate.path == protected {
			continue
		}
		if _, ok := pending[candidate.path]; ok {
			continue
		}
		if err := os.Remove(candidate.path); err != nil {
			if !os.IsNotExist(err) {
				c.logger.Warn("清理 faststart 缓存失败", "path", candidate.path, "error", err)
			}
			continue
		}
		if candidate.size >= total {
			total = 0
		} else {
			total -= candidate.size
		}
	}
}

func openCachedContent(path string, sourceModifiedAt time.Time) (domain.OpenedContent, error) {
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
		Reader: file, Size: info.Size(), ModifiedAt: sourceModifiedAt,
	}, nil
}

func validateCacheMediaID(id string) error {
	if id == "" || filepath.Base(id) != id || id == "." || id == ".." {
		return fmt.Errorf("媒体 ID 不适合作为缓存键")
	}
	return nil
}
