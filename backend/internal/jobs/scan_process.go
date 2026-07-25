package jobs

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// process 执行一个完整扫描，并确保失败或中断时绝不提交 missing。
func (w *ScanWorker) process(ctx context.Context, job domain.ScanJob) error {
	source, err := w.sources.Get(ctx, job.SourceID)
	if err != nil {
		return w.finishFailed(job, domain.ScanStatusFailed, "SOURCE_NOT_FOUND", "媒体源不存在", err)
	}
	if !source.Enabled {
		return w.finishFailed(job, domain.ScanStatusFailed, "SOURCE_OFFLINE", "媒体源已禁用", domain.ErrSourceOffline)
	}
	mediaSource, err := w.factory.Local(source.RootPath)
	if err != nil {
		return w.sourceFailed(job, err)
	}
	if _, err := mediaSource.Health(ctx); err != nil {
		return w.sourceFailed(job, err)
	}
	scanErr := w.scanner.Scan(ctx, mediaSource, func(file domain.DiscoveredFile) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := w.processFile(ctx, job, source.ID, source.LibraryKind, mediaSource, file); err != nil {
			if errors.Is(err, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
				return err
			}
			w.logger.Error("扫描单文件失败", "scan_id", job.ID, "source_id", source.ID,
				"relative_path", file.RelativePath, "error", err)
			return w.scans.MarkFileFailed(ctx, job.ID, source.ID, file, w.clock.Now())
		}
		return nil
	})
	if scanErr != nil {
		if errors.Is(scanErr, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
			return w.finishFailed(job, domain.ScanStatusInterrupted, "SCAN_INTERRUPTED", "服务退出导致扫描中断", scanErr)
		}
		_ = w.setSourceStatus(job.SourceID, domain.SourceStatusDegraded)
		return w.finishFailed(job, domain.ScanStatusFailed, "SCAN_FAILED", "扫描媒体源失败", scanErr)
	}
	if err := w.scans.CompleteJob(ctx, job.ID, source.ID, w.clock.Now()); err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
			return w.finishFailed(job, domain.ScanStatusInterrupted, "SCAN_INTERRUPTED", "服务退出导致扫描中断", err)
		}
		return w.finishFailed(job, domain.ScanStatusFailed, "SCAN_COMMIT_FAILED", "提交扫描结果失败", err)
	}
	w.catalogSignal.Notify(CatalogSyncEvent{ScanID: job.ID, SourceID: source.ID})
	return nil
}

func (w *ScanWorker) processFile(ctx context.Context, job domain.ScanJob, sourceID, libraryKind string,
	mediaSource storage.MediaSource, file domain.DiscoveredFile) error {
	if file.MediaType == domain.MediaTypeSidecar {
		if libraryKind == domain.LibraryKindMovies || libraryKind == domain.LibraryKindTV {
			if err := w.scans.ReconcileSidecar(ctx, job.ID, sourceID, file, w.clock.Now()); err != nil {
				return err
			}
		}
		return w.scans.AddProgress(ctx, job.ID, 1, 1, 0, w.clock.Now())
	}
	needsHash, err := w.scans.NeedsQuickHash(ctx, sourceID, file)
	if err != nil {
		return err
	}
	if needsHash {
		file.QuickHash, err = w.hasher.Hash(ctx, mediaSource, file.RelativePath, file.Size)
		if err != nil {
			return err
		}
	}
	mediaID, err := w.ids.New("media")
	if err != nil {
		return err
	}
	result, err := w.scans.ReconcileFile(ctx, job.ID, sourceID, mediaID, file, w.clock.Now())
	if err != nil {
		return err
	}
	if result.NeedsProbe {
		probeJobID, err := w.ids.New("job")
		if err != nil {
			return err
		}
		if err := w.processing.EnqueueProbe(ctx, probeJobID, result.MediaID, w.clock.Now()); err != nil {
			return err
		}
		w.probeSignal.Notify()
	}
	return w.scans.AddProgress(ctx, job.ID, 1, 1, 0, w.clock.Now())
}

func (w *ScanWorker) sourceFailed(job domain.ScanJob, cause error) error {
	_ = w.setSourceStatus(job.SourceID, domain.SourceStatusOffline)
	return w.finishFailed(job, domain.ScanStatusFailed, "SOURCE_OFFLINE", "媒体源当前不可访问", cause)
}

func (w *ScanWorker) finishFailed(job domain.ScanJob, status, code, message string, cause error) error {
	w.logger.Error("扫描任务失败", "scan_id", job.ID, "source_id", job.SourceID, "error", cause)
	finishCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := w.scans.FinishJobWithoutCommit(finishCtx, job.ID, status, code, message, w.clock.Now()); err != nil {
		return fmt.Errorf("保存扫描失败状态: %w", err)
	}
	return nil
}

func (w *ScanWorker) setSourceStatus(sourceID, status string) error {
	statusCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return w.sources.SetStatus(statusCtx, sourceID, status, w.clock.Now())
}
