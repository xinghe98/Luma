package jobs

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/media"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

// ThumbnailWorker 从持久化队列生成默认缩略图。
type ThumbnailWorker struct {
	// repo 提供媒体处理任务和索引事务。
	repo repository.ProcessingRepository
	// thumbnailer 生成并存储默认缩略图。
	thumbnailer media.Thumbnailer
	// clock 提供统一 UTC 时间。
	clock WorkerClock
	// signal 接收缩略图任务唤醒通知。
	signal *Signal
	// logger 记录缩略图生成错误。
	logger *slog.Logger
	// workerID 是写入任务锁的 Worker 标识。
	workerID string
	// toolTimeout 限制单次缩略图生成时长。
	toolTimeout time.Duration
}

func NewThumbnailWorker(repo repository.ProcessingRepository, thumbnailer media.Thumbnailer, ids WorkerIDGenerator,
	clock WorkerClock, signal *Signal, logger *slog.Logger, toolTimeout time.Duration) (*ThumbnailWorker, error) {
	if repo == nil || thumbnailer == nil || ids == nil || clock == nil || signal == nil || logger == nil || toolTimeout <= 0 {
		return nil, errors.New("缩略图 Worker 依赖不能为空")
	}
	id, err := ids.New("thumbworker")
	if err != nil {
		return nil, err
	}
	return &ThumbnailWorker{repo: repo, thumbnailer: thumbnailer, clock: clock, signal: signal,
		logger: logger, workerID: id, toolTimeout: toolTimeout}, nil
}

func (w *ThumbnailWorker) Run(ctx context.Context) error {
	return runProcessingLoop(ctx, w.signal, func() error { return w.runOne(ctx) })
}

func (w *ThumbnailWorker) runOne(ctx context.Context) error {
	job, err := w.repo.Claim(ctx, domain.JobTypeThumbnail, w.workerID, w.clock.Now())
	if errors.Is(err, domain.ErrNoPendingJob) {
		job, err = w.repo.Claim(ctx, domain.JobTypeCardThumbnail, w.workerID, w.clock.Now())
	}
	if err != nil {
		return err
	}
	input, err := w.repo.GetMedia(ctx, job.MediaID)
	var thumbnail domain.ThumbnailResult
	if err == nil {
		toolCtx, cancel := context.WithTimeout(ctx, w.toolTimeout)
		if job.Type == domain.JobTypeCardThumbnail {
			cardThumbnailer, ok := w.thumbnailer.(media.CardThumbnailer)
			if !ok {
				err = errors.New("缩略图生成器不支持卡片变体")
			} else {
				thumbnail, err = cardThumbnailer.GenerateCard(toolCtx, input, input.DurationMS)
			}
		} else {
			thumbnail, err = w.thumbnailer.Generate(toolCtx, input, input.DurationMS)
		}
		cancel()
		if err == nil {
			if job.Type == domain.JobTypeCardThumbnail {
				_, err = w.repo.CompleteCardThumbnail(ctx, job, input, thumbnail, w.clock.Now())
			} else {
				_, err = w.repo.CompleteThumbnail(ctx, job, input, thumbnail, w.clock.Now())
			}
			if err == nil {
				return nil
			}
		} else if errors.Is(err, context.DeadlineExceeded) {
			err = errors.New("缩略图生成超时")
		}
	}
	if isBenignJobError(err) {
		return nil
	}
	w.logger.Warn("缩略图生成失败", "media_id", job.MediaID, "error", err)
	if _, failErr := w.repo.Fail(ctx, job, "THUMBNAIL_FAILED", "缩略图生成失败", w.clock.Now()); failErr != nil && !isBenignJobError(failErr) {
		w.logger.Error("记录缩略图失败状态失败", "media_id", job.MediaID, "error", failErr)
	}
	return nil
}
