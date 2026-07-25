package jobs

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
	"github.com/xinghe98/Luma/backend/internal/scanner"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// WorkerIDGenerator 定义 Worker 和媒体索引生成业务标识所需的能力。
type WorkerIDGenerator interface {
	// New 使用指定前缀生成新业务标识。
	New(string) (string, error)
}

// WorkerClock 定义扫描 Worker 读取当前时间所需的能力。
type WorkerClock interface {
	// Now 返回当前 UTC 时间。
	Now() time.Time
}

// ScanWorker 串行领取并执行持久化媒体源扫描任务。
type ScanWorker struct {
	// sources 提供媒体源配置和状态更新。
	sources repository.SourceRepository
	// scans 提供扫描任务和媒体索引事务。
	scans repository.ScanRepository
	// processing 提供扫描后媒体处理任务的入队能力。
	processing repository.ProcessingRepository
	// factory 创建只读媒体存储适配器。
	factory storage.SourceFactory
	// scanner 筛选并遍历受支持媒体文件。
	scanner scanner.Scanner
	// hasher 按需计算快速指纹。
	hasher scanner.QuickHasher
	// ids 生成 Worker 和媒体业务标识。
	ids WorkerIDGenerator
	// clock 提供统一 UTC 时间。
	clock WorkerClock
	// signal 接收新任务唤醒通知。
	signal *Signal
	// probeSignal 发送媒体探测任务唤醒通知。
	probeSignal *Signal
	// catalogSignal 发送完整扫描提交后的作品整理事件。
	catalogSignal *CatalogSyncSignal
	// logger 记录不向 API 暴露的详细扫描错误。
	logger *slog.Logger
	// workerID 是写入任务锁的本进程 Worker 标识。
	workerID string
}

// NewScanWorker 创建单并发扫描 Worker，但不会启动 Goroutine。
func NewScanWorker(
	sources repository.SourceRepository,
	scans repository.ScanRepository,
	processing repository.ProcessingRepository,
	factory storage.SourceFactory,
	fileScanner scanner.Scanner,
	hasher scanner.QuickHasher,
	ids WorkerIDGenerator,
	clock WorkerClock,
	signal *Signal,
	probeSignal *Signal,
	catalogSignal *CatalogSyncSignal,
	logger *slog.Logger,
) (*ScanWorker, error) {
	if sources == nil || scans == nil || processing == nil || factory == nil || fileScanner == nil || hasher == nil ||
		ids == nil || clock == nil || signal == nil || probeSignal == nil || catalogSignal == nil || logger == nil {
		return nil, errors.New("扫描 Worker 依赖不能为空")
	}
	workerID, err := ids.New("scanworker")
	if err != nil {
		return nil, err
	}
	return &ScanWorker{
		sources: sources, scans: scans, processing: processing, factory: factory, scanner: fileScanner,
		hasher: hasher, ids: ids, clock: clock, signal: signal, probeSignal: probeSignal, catalogSignal: catalogSignal,
		logger: logger, workerID: workerID,
	}, nil
}

// Run 持续领取扫描任务，直到上下文取消；启动恢复由 Group 统一完成。
// 空闲时同时等待 Notify 与 1 秒 ticker，避免唤醒信号丢失后任务永久挂起。
func (w *ScanWorker) Run(ctx context.Context) error {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		job, err := w.scans.ClaimNextJob(ctx, w.workerID, w.clock.Now())
		if err == nil {
			if err := w.process(ctx, job); err != nil {
				return err
			}
			continue
		}
		if !errors.Is(err, domain.ErrNoPendingScan) {
			if errors.Is(err, context.Canceled) {
				return nil
			}
			return fmt.Errorf("领取扫描任务: %w", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-w.signal.C():
		case <-ticker.C:
		}
	}
}
