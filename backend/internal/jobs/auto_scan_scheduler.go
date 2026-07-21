package jobs

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// autoScanSourceLister 列出可用于自动扫描的媒体源。
type autoScanSourceLister interface {
	List(context.Context) ([]domain.Source, error)
}

// autoScanStarter 在源空闲时创建全量扫描任务；已有进行中任务时应返回 nil。
type autoScanStarter interface {
	StartIfIdle(context.Context, string) (bool, error)
}

// debounceTimer 把可取消的 timer 与唯一的 WaitGroup 计数绑定。
// Stop 成功时回调不会执行，调用方必须主动 Done；回调已开始则由回调 Done。
type debounceTimer struct {
	timer *time.Timer
	done  sync.Once
}

// AutoScanScheduler 根据配置用目录监听与/或定时轮询自动调用全量扫描。
// 不引入新的 job 类型：只调用 StartIfIdle，依赖库内每源单飞约束合并重复触发。
type AutoScanScheduler struct {
	// sources 提供媒体源列表与根路径。
	sources autoScanSourceLister
	// starter 创建扫描任务（已运行则 no-op）。
	starter autoScanStarter
	// config 是自动扫描策略；Enabled=false 时 Run 立即空转等待退出。
	config config.AutoScanConfig
	// clock 提供 debounce 与日志时间（便于测试注入）。
	clock WorkerClock
	// logger 记录调度与监听异常，不向 API 暴露。
	logger *slog.Logger

	mu sync.Mutex
	// debounceTimers 按 sourceID 合并短时间内的多次触发。
	debounceTimers map[string]*debounceTimer
	// rootBySource 记录当前已监视源的根路径，用于热更新。
	rootBySource map[string]string
	// sourceByWatchPath 将 watcher 路径映射回 sourceID。
	sourceByWatchPath map[string]string
	// watcher 在 watch/hybrid 模式下监听本地目录；失败时降级为仅 poll。
	watcher *fsnotify.Watcher
	// stopping 阻止关闭阶段新增 timer，保证 Wait 不会与 Add 并发。
	stopping bool
	timerWG  sync.WaitGroup
	// watcherWG 确保关闭 watcher 前消费协程已经退出。
	watcherWG sync.WaitGroup
}

// NewAutoScanScheduler 创建自动扫描调度器，不会启动 Goroutine。
func NewAutoScanScheduler(
	sources autoScanSourceLister,
	starter autoScanStarter,
	cfg config.AutoScanConfig,
	clock WorkerClock,
	logger *slog.Logger,
) (*AutoScanScheduler, error) {
	if sources == nil || starter == nil || clock == nil || logger == nil {
		return nil, errors.New("自动扫描调度器依赖不能为空")
	}
	if strings.TrimSpace(cfg.Mode) == "" {
		cfg.Mode = config.AutoScanModeHybrid
	}
	return &AutoScanScheduler{
		sources: sources, starter: starter, config: cfg, clock: clock, logger: logger,
		debounceTimers:    make(map[string]*debounceTimer),
		rootBySource:      make(map[string]string),
		sourceByWatchPath: make(map[string]string),
	}, nil
}

// Run 阻塞运行自动扫描，直到上下文取消。
func (s *AutoScanScheduler) Run(ctx context.Context) error {
	if !s.config.Enabled {
		s.logger.Info("自动扫描已关闭")
		<-ctx.Done()
		return nil
	}
	s.logger.Info("自动扫描已启用",
		"mode", s.config.Mode,
		"interval", s.config.Interval.String(),
		"debounce", s.config.Debounce.String(),
	)
	runCtx, cancel := context.WithCancel(ctx)
	s.mu.Lock()
	s.stopping = false
	s.mu.Unlock()
	defer func() {
		cancel()
		s.stopDebounceTimers()
		s.timerWG.Wait()
		s.watcherWG.Wait()
		s.shutdown()
	}()

	useWatch := s.config.Mode == config.AutoScanModeHybrid || s.config.Mode == config.AutoScanModeWatch
	usePoll := s.config.Mode == config.AutoScanModeHybrid || s.config.Mode == config.AutoScanModePoll
	if useWatch {
		if err := s.openWatcher(); err != nil {
			s.logger.Error("创建目录监听失败，将仅依赖定时扫描", "error", err)
			useWatch = false
			if !usePoll {
				// watch-only 且监听失败时退化为 poll，避免完全失去自动发现能力。
				usePoll = true
			}
		} else {
			watcher := s.watcher
			s.watcherWG.Add(1)
			go func() {
				defer s.watcherWG.Done()
				s.consumeWatcher(runCtx, watcher)
			}()
		}
	}

	// 启动时先对齐一次源列表与监视表（不立即全量扫）。
	if err := s.reconcile(runCtx, useWatch, false); err != nil && !errors.Is(err, context.Canceled) {
		s.logger.Error("自动扫描初始化失败", "error", err)
	}

	// 统一 ticker：poll/hybrid 时顺带 Start；watch-only 时仅刷新监视表与源列表。
	ticker := time.NewTicker(s.config.Interval)
	defer ticker.Stop()
	var firstPoll <-chan time.Time
	var firstTimer *time.Timer
	if usePoll {
		// 与主循环共用生命周期，避免留下未 join 的首次轮询 goroutine。
		firstTimer = time.NewTimer(minDuration(s.config.Debounce, 5*time.Second))
		firstPoll = firstTimer.C
		defer firstTimer.Stop()
	}

	for {
		select {
		case <-runCtx.Done():
			return nil
		case <-firstPoll:
			firstPoll = nil
			if err := s.reconcile(runCtx, useWatch, true); err != nil && !errors.Is(err, context.Canceled) {
				s.logger.Error("自动扫描首次轮询失败", "error", err)
			}
		case <-ticker.C:
			if err := s.reconcile(runCtx, useWatch, usePoll); err != nil && !errors.Is(err, context.Canceled) {
				s.logger.Error("自动扫描周期任务失败", "error", err)
			}
		}
	}
}

// reconcile 同步启用源的监视表；startScans 为 true 时对每个启用源尝试入队扫描。
func (s *AutoScanScheduler) reconcile(ctx context.Context, useWatch, startScans bool) error {
	sources, err := s.sources.List(ctx)
	if err != nil {
		return fmt.Errorf("列出媒体源: %w", err)
	}
	enabled := make([]domain.Source, 0, len(sources))
	for _, source := range sources {
		if source.Enabled && source.Type == domain.SourceTypeLocal && strings.TrimSpace(source.RootPath) != "" {
			enabled = append(enabled, source)
		}
	}
	if useWatch {
		if err := s.syncWatches(enabled); err != nil {
			s.logger.Error("同步目录监听失败", "error", err)
		}
	}
	if !startScans {
		return nil
	}
	for _, source := range enabled {
		if err := ctx.Err(); err != nil {
			return err
		}
		if _, err := s.starter.StartIfIdle(ctx, source.ID); err != nil {
			s.logger.Error("自动扫描入队失败", "source_id", source.ID, "error", err)
		}
	}
	return nil
}

// scheduleSource 在 debounce 窗口结束后对该源调用 StartIfIdle。
func (s *AutoScanScheduler) scheduleSource(ctx context.Context, sourceID string) {
	if sourceID == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stopping || ctx.Err() != nil {
		return
	}
	if existing, ok := s.debounceTimers[sourceID]; ok && existing.timer.Stop() {
		existing.done.Do(s.timerWG.Done)
	}
	holder := &debounceTimer{}
	sourceIDCopy := sourceID
	s.timerWG.Add(1)
	holder.timer = time.AfterFunc(s.config.Debounce, func() {
		defer holder.done.Do(s.timerWG.Done)
		s.mu.Lock()
		if s.debounceTimers[sourceIDCopy] != holder {
			s.mu.Unlock()
			return
		}
		delete(s.debounceTimers, sourceIDCopy)
		s.mu.Unlock()
		if ctx.Err() != nil {
			return
		}
		started, err := s.starter.StartIfIdle(ctx, sourceIDCopy)
		if err != nil {
			s.logger.Error("防抖后自动扫描入队失败", "source_id", sourceIDCopy, "error", err)
			return
		}
		if !started {
			// 文件变更落在长扫描期间时，保留一次尾随扫描而不是静默丢弃。
			s.scheduleSource(ctx, sourceIDCopy)
		}
	})
	s.debounceTimers[sourceID] = holder
}

func (s *AutoScanScheduler) openWatcher() error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	s.watcher = watcher
	return nil
}

// consumeWatcher 将文件系统事件映射到对应媒体源并重置 debounce。
func (s *AutoScanScheduler) consumeWatcher(ctx context.Context, watcher *fsnotify.Watcher) {
	for {
		select {
		case <-ctx.Done():
			return
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			s.logger.Error("目录监听错误", "error", err)
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			// 忽略纯权限位变化可减少噪声；其余 Create/Write/Remove/Rename 均触发。
			if event.Has(fsnotify.Chmod) && !event.Has(fsnotify.Write) &&
				!event.Has(fsnotify.Create) && !event.Has(fsnotify.Remove) && !event.Has(fsnotify.Rename) {
				continue
			}
			sourceID := s.lookupSource(event.Name)
			if sourceID == "" {
				continue
			}
			// 新建子目录时补注册监视，便于后续深层文件事件到达。
			if event.Has(fsnotify.Create) {
				if info, err := os.Stat(event.Name); err == nil && info.IsDir() {
					_ = s.addWatchPath(sourceID, event.Name)
				}
			}
			s.scheduleSource(ctx, sourceID)
		}
	}
}

func (s *AutoScanScheduler) lookupSource(eventPath string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	clean := filepath.Clean(eventPath)
	if id, ok := s.sourceByWatchPath[clean]; ok {
		return id
	}
	// 事件可能落在已监视目录的子路径上：向上查找最近的监视根。
	dir := clean
	for {
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		if id, ok := s.sourceByWatchPath[parent]; ok {
			return id
		}
		dir = parent
	}
	for sourceID, root := range s.rootBySource {
		if pathIsWithinRoot(root, clean) {
			return sourceID
		}
	}
	return ""
}

func (s *AutoScanScheduler) syncWatches(enabled []domain.Source) error {
	if s.watcher == nil {
		return nil
	}
	desired := make(map[string]string, len(enabled))
	for _, source := range enabled {
		desired[source.ID] = filepath.Clean(source.RootPath)
	}

	s.mu.Lock()
	current := make(map[string]string, len(s.rootBySource))
	for id, root := range s.rootBySource {
		current[id] = root
	}
	s.mu.Unlock()

	// 移除已禁用、删除或根路径变更的源。
	for sourceID, root := range current {
		next, ok := desired[sourceID]
		if ok && next == root {
			continue
		}
		s.removeSourceWatches(sourceID)
	}
	// 添加或刷新启用源。
	for sourceID, root := range desired {
		if current[sourceID] == root {
			continue
		}
		if err := s.watchSourceTree(sourceID, root); err != nil {
			s.logger.Error("监视媒体源目录失败", "source_id", sourceID, "root", root, "error", err)
		}
	}
	return nil
}

func (s *AutoScanScheduler) watchSourceTree(sourceID, root string) error {
	info, err := os.Stat(root)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("根路径不是目录: %s", root)
	}
	// 递归注册子目录：fsnotify 默认非递归，深层变更依赖子目录监视。
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			// 单个子目录不可读时跳过，不中断整棵树。
			s.logger.Warn("遍历媒体源子目录失败", "path", path, "error", walkErr)
			if entry != nil && entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !entry.IsDir() {
			return nil
		}
		return s.addWatchPath(sourceID, path)
	})
	if err != nil {
		// 半注册状态不能视为成功；下次 reconcile 会重试。
		s.removeSourceWatches(sourceID)
		return err
	}
	s.mu.Lock()
	s.rootBySource[sourceID] = root
	s.mu.Unlock()
	return nil
}

func (s *AutoScanScheduler) addWatchPath(sourceID, path string) error {
	if s.watcher == nil {
		return nil
	}
	clean := filepath.Clean(path)
	if err := s.watcher.Add(clean); err != nil {
		return err
	}
	s.mu.Lock()
	s.sourceByWatchPath[clean] = sourceID
	s.mu.Unlock()
	return nil
}

func (s *AutoScanScheduler) removeSourceWatches(sourceID string) {
	if s.watcher == nil {
		return
	}
	s.mu.Lock()
	var paths []string
	for path, id := range s.sourceByWatchPath {
		if id == sourceID {
			paths = append(paths, path)
			delete(s.sourceByWatchPath, path)
		}
	}
	delete(s.rootBySource, sourceID)
	if timer, ok := s.debounceTimers[sourceID]; ok {
		if timer.timer.Stop() {
			timer.done.Do(s.timerWG.Done)
		}
		delete(s.debounceTimers, sourceID)
	}
	s.mu.Unlock()
	for _, path := range paths {
		_ = s.watcher.Remove(path)
	}
}

func (s *AutoScanScheduler) shutdown() {
	s.mu.Lock()
	s.sourceByWatchPath = make(map[string]string)
	s.rootBySource = make(map[string]string)
	watcher := s.watcher
	s.watcher = nil
	s.mu.Unlock()
	if watcher != nil {
		_ = watcher.Close()
	}
}

// stopDebounceTimers 取消未开始的回调；已开始的回调使用 Run 的 context，
// 会自行退出并在 timerWG 中完成。
func (s *AutoScanScheduler) stopDebounceTimers() {
	s.mu.Lock()
	s.stopping = true
	for id, holder := range s.debounceTimers {
		if holder.timer.Stop() {
			holder.done.Do(s.timerWG.Done)
		}
		delete(s.debounceTimers, id)
	}
	s.mu.Unlock()
}

func pathIsWithinRoot(root, candidate string) bool {
	root = filepath.Clean(root)
	candidate = filepath.Clean(candidate)
	if runtime.GOOS == "windows" {
		root = strings.ToLower(root)
		candidate = strings.ToLower(candidate)
	}
	if root == candidate {
		return true
	}
	return strings.HasPrefix(candidate, root+string(filepath.Separator))
}

func minDuration(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}
