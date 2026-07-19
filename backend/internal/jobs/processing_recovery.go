package jobs

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/media"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

// ProcessingRecovery 恢复中断任务并补齐扫描与入队之间的异常窗口。
type ProcessingRecovery struct {
	// repo 提供媒体任务恢复和入队能力。
	repo repository.ProcessingRepository
	// ids 生成任务和资源业务标识。
	ids WorkerIDGenerator
	// clock 提供统一 UTC 时间。
	clock WorkerClock
	// probeSignal 发送媒体探测任务唤醒通知。
	probeSignal *Signal
	// thumbnailSignal 发送缩略图任务唤醒通知。
	thumbnailSignal *Signal
	// logger 记录任务恢复错误。
	logger *slog.Logger
	// thumbnailWidth 是缩略图任务的目标宽度。
	thumbnailWidth int
	// lockTimeout 是任务锁的过期时长。
	lockTimeout time.Duration
}

func NewProcessingRecovery(repo repository.ProcessingRepository, ids WorkerIDGenerator, clock WorkerClock,
	probeSignal, thumbnailSignal *Signal, logger *slog.Logger, width int, lockTimeout time.Duration) (*ProcessingRecovery, error) {
	if repo == nil || ids == nil || clock == nil || probeSignal == nil || thumbnailSignal == nil || logger == nil || width <= 0 || lockTimeout <= 0 {
		return nil, fmt.Errorf("媒体任务恢复器依赖不能为空")
	}
	return &ProcessingRecovery{
		repo: repo, ids: ids, clock: clock, probeSignal: probeSignal, thumbnailSignal: thumbnailSignal,
		logger: logger, thumbnailWidth: width, lockTimeout: lockTimeout,
	}, nil
}

func (r *ProcessingRecovery) Prepare(ctx context.Context) error {
	if err := r.repo.Recover(ctx, r.clock.Now()); err != nil {
		return err
	}
	return r.enqueueOrphans(ctx)
}

func (r *ProcessingRecovery) Run(ctx context.Context) error {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := r.repo.ReclaimExpired(ctx, r.clock.Now(), r.lockTimeout); err != nil {
				if ctx.Err() != nil {
					return nil
				}
				r.logger.Error("回收超时媒体任务失败", "error", err)
				continue
			}
			if err := r.enqueueOrphans(ctx); err != nil {
				if ctx.Err() != nil {
					return nil
				}
				r.logger.Error("补齐遗留媒体任务失败", "error", err)
			}
		}
	}
}

func (r *ProcessingRecovery) enqueueOrphans(ctx context.Context) error {
	if err := r.enqueueProbeOrphans(ctx); err != nil {
		return err
	}
	return r.enqueueThumbnailOrphans(ctx)
}

func (r *ProcessingRecovery) enqueueProbeOrphans(ctx context.Context) error {
	items, err := r.repo.ListOrphans(ctx, domain.JobTypeProbe, 100)
	if err != nil {
		return err
	}
	for _, item := range items {
		jobID, err := r.ids.New("job")
		if err != nil {
			return err
		}
		if err := r.repo.EnqueueProbe(ctx, jobID, item.ID, r.clock.Now()); err != nil {
			return err
		}
	}
	if len(items) > 0 {
		r.probeSignal.Notify()
	}
	return nil
}

func (r *ProcessingRecovery) enqueueThumbnailOrphans(ctx context.Context) error {
	items, err := r.repo.ListOrphans(ctx, domain.JobTypeThumbnail, 100)
	if err != nil {
		return err
	}
	for _, item := range items {
		jobID, err := r.ids.New("job")
		if err != nil {
			return err
		}
		assetID, err := r.ids.New("asset")
		if err != nil {
			return err
		}
		key := media.ThumbnailStorageKey(item.ID, r.thumbnailWidth)
		if err := r.repo.EnqueueThumbnail(ctx, jobID, item.ID, assetID, key, r.clock.Now()); err != nil {
			return err
		}
	}
	if len(items) > 0 {
		r.thumbnailSignal.Notify()
	}
	return nil
}
