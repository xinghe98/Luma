package jobs

import (
	"context"
	"errors"
	"log/slog"
	"time"
)

type CatalogSynchronizerUseCase interface {
	Sync(context.Context) error
}

// CatalogMetadataQueue 在同步完成后创建一次扫描对应的资料任务。
type CatalogMetadataQueue interface {
	QueueMetadataForScan(context.Context, string, string, time.Time) (int, error)
}

type CatalogSynchronizer struct {
	service        CatalogSynchronizerUseCase
	signal         *CatalogSyncSignal
	queue          CatalogMetadataQueue
	metadataSignal *Signal
	logger         *slog.Logger
}

// NewCatalogSynchronizer 创建扫描后同步作品库并安排资料任务的后台服务。
func NewCatalogSynchronizer(service CatalogSynchronizerUseCase, signal *CatalogSyncSignal, queue CatalogMetadataQueue, metadataSignal *Signal, logger *slog.Logger) (*CatalogSynchronizer, error) {
	if service == nil || signal == nil || queue == nil || metadataSignal == nil || logger == nil {
		return nil, errors.New("作品库后台整理依赖不能为空")
	}
	return &CatalogSynchronizer{service: service, signal: signal, queue: queue, metadataSignal: metadataSignal, logger: logger}, nil
}

func (s *CatalogSynchronizer) Run(ctx context.Context) error {
	if err := s.sync(ctx); err != nil && !errors.Is(err, context.Canceled) {
		s.logger.Error("启动作品库整理失败", "error", err)
	}
	ticker := time.NewTicker(15 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-s.signal.C():
			s.syncAndQueue(ctx)
		case <-ticker.C:
			s.syncAndQueue(ctx)
		}
	}
}

// syncAndQueue 仅在同步成功后取走扫描事件，失败事件会保留至下一次重试。
func (s *CatalogSynchronizer) syncAndQueue(ctx context.Context) {
	if err := s.sync(ctx); err != nil {
		if !errors.Is(err, context.Canceled) {
			s.logger.Error("作品库整理失败", "error", err)
		}
		return
	}
	for _, event := range s.signal.Take() {
		if _, err := s.queue.QueueMetadataForScan(ctx, event.ScanID, event.SourceID, time.Now().UTC()); err != nil {
			s.logger.Error("创建扫描资料任务失败", "scan_id", event.ScanID, "source_id", event.SourceID, "error", err)
			continue
		}
		s.metadataSignal.Notify()
	}
}

func (s *CatalogSynchronizer) sync(ctx context.Context) error {
	syncCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	return s.service.Sync(syncCtx)
}
