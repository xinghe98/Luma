package jobs

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
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

func minDuration(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}
