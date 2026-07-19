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

// ProbeWorker 从持久化队列提取媒体元数据。
type ProbeWorker struct {
	// repo 提供媒体处理任务和索引事务。
	repo repository.ProcessingRepository
	// prober 提取媒体元数据。
	prober media.Prober
	// ids 生成资源和任务业务标识。
	ids WorkerIDGenerator
	// clock 提供统一 UTC 时间。
	clock WorkerClock
	// signal 接收媒体探测任务唤醒通知。
	signal *Signal
	// thumbnailSignal 发送缩略图任务唤醒通知。
	thumbnailSignal *Signal
	// logger 记录媒体探测错误。
	logger *slog.Logger
	// workerID 是写入任务锁的 Worker 标识。
	workerID string
	// thumbnailWidth 是后续缩略图的目标宽度。
	thumbnailWidth int
	// toolTimeout 限制单次媒体探测时长。
	toolTimeout time.Duration
}

func NewProbeWorker(repo repository.ProcessingRepository, prober media.Prober, ids WorkerIDGenerator,
	clock WorkerClock, signal, thumbnailSignal *Signal, logger *slog.Logger, width int, toolTimeout time.Duration) (*ProbeWorker, error) {
	if repo == nil || prober == nil || ids == nil || clock == nil || signal == nil || thumbnailSignal == nil ||
		logger == nil || width <= 0 || toolTimeout <= 0 {
		return nil, errors.New("媒体探测 Worker 依赖不能为空")
	}
	id, err := ids.New("probeworker")
	if err != nil {
		return nil, err
	}
	return &ProbeWorker{repo: repo, prober: prober, ids: ids, clock: clock, signal: signal,
		thumbnailSignal: thumbnailSignal, logger: logger, workerID: id, thumbnailWidth: width, toolTimeout: toolTimeout}, nil
}

func (w *ProbeWorker) Run(ctx context.Context) error {
	return runProcessingLoop(ctx, w.signal, func() error { return w.runOne(ctx) })
}

func (w *ProbeWorker) runOne(ctx context.Context) error {
	job, err := w.repo.Claim(ctx, domain.JobTypeProbe, w.workerID, w.clock.Now())
	if err != nil {
		return err
	}
	input, err := w.repo.GetMedia(ctx, job.MediaID)
	if err == nil {
		toolCtx, cancel := context.WithTimeout(ctx, w.toolTimeout)
		var result domain.ProbeResult
		result, err = w.prober.Probe(toolCtx, input)
		cancel()
		if err == nil {
			return w.complete(ctx, job, input, result)
		}
		if errors.Is(err, context.DeadlineExceeded) {
			err = errors.New("媒体探测超时")
		}
	}
	return w.failed(ctx, job, "PROBE_FAILED", err)
}

func (w *ProbeWorker) complete(ctx context.Context, job domain.ProcessingJob, input domain.MediaInput, probe domain.ProbeResult) error {
	assetID, err := w.ids.New("asset")
	if err != nil {
		return w.failed(ctx, job, "PROBE_FAILED", err)
	}
	thumbnailJobID, err := w.ids.New("job")
	if err != nil {
		return w.failed(ctx, job, "PROBE_FAILED", err)
	}
	key := media.ThumbnailStorageKey(input.ID, w.thumbnailWidth)
	matched, err := w.repo.CompleteProbe(ctx, job, input, probe, assetID, thumbnailJobID, key, w.clock.Now())
	if err == nil {
		if matched {
			w.thumbnailSignal.Notify()
		}
		return nil
	}
	return w.failed(ctx, job, "PROBE_FAILED", err)
}

func (w *ProbeWorker) failed(ctx context.Context, job domain.ProcessingJob, code string, cause error) error {
	if isBenignJobError(cause) {
		return nil
	}
	w.logger.Warn("媒体探测失败", "media_id", job.MediaID, "error", cause)
	if _, err := w.repo.Fail(ctx, job, code, "媒体元数据提取失败", w.clock.Now()); err != nil && !isBenignJobError(err) {
		w.logger.Error("记录媒体探测失败状态失败", "media_id", job.MediaID, "error", err)
	}
	return nil
}
