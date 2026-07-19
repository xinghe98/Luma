package app

import (
	"database/sql"
	"fmt"

	"github.com/xinghe98/Luma/backend/internal/jobs"
	"github.com/xinghe98/Luma/backend/internal/media"
	"github.com/xinghe98/Luma/backend/internal/platform"
	dbrepo "github.com/xinghe98/Luma/backend/internal/repository/sqlite"
	"github.com/xinghe98/Luma/backend/internal/scanner"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

func (b *bootstrap) buildWorkers(database *sql.DB, sources *dbrepo.SourceRepository, scans *dbrepo.ScanRepository,
	localFactory *storage.LocalFactory, ids platform.SecureIDGenerator, clock platform.RealClock) (*jobs.Group, *jobs.Signal, error) {
	processing, err := dbrepo.NewProcessingRepository(database)
	if err != nil {
		return nil, nil, fmt.Errorf("创建媒体处理 Repository: %w", err)
	}
	localScanner, err := scanner.NewLocalScanner(b.config.Media.ScanExtensions)
	if err != nil {
		return nil, nil, fmt.Errorf("创建本地扫描器: %w", err)
	}
	prober, err := media.NewFFprobeProber(b.config.Media.FFprobePath)
	if err != nil {
		return nil, nil, fmt.Errorf("创建媒体探测器: %w", err)
	}
	thumbnailer, err := media.NewFFmpegThumbnailer(b.config.Media.FFmpegPath,
		b.config.Storage.ThumbnailDir, b.config.Media.ThumbnailWidth)
	if err != nil {
		return nil, nil, fmt.Errorf("创建缩略图生成器: %w", err)
	}
	scanSignal, probeSignal, thumbnailSignal := jobs.NewSignal(), jobs.NewSignal(), jobs.NewSignal()
	toolTimeout := b.config.Workers.LockTimeout
	var runners []jobs.Runner
	for range b.config.Workers.Scan {
		scanWorker, err := jobs.NewScanWorker(sources, scans, processing, localFactory, localScanner,
			scanner.SHA256QuickHasher{}, ids, clock, scanSignal, probeSignal, b.logger)
		if err != nil {
			return nil, nil, fmt.Errorf("创建扫描 Worker: %w", err)
		}
		runners = append(runners, scanWorker)
	}
	for range b.config.Workers.Probe {
		worker, err := jobs.NewProbeWorker(processing, prober, ids, clock, probeSignal,
			thumbnailSignal, b.logger, b.config.Media.ThumbnailWidth, toolTimeout)
		if err != nil {
			return nil, nil, fmt.Errorf("创建媒体探测 Worker: %w", err)
		}
		runners = append(runners, worker)
	}
	for range b.config.Workers.Thumbnail {
		worker, err := jobs.NewThumbnailWorker(processing, thumbnailer, ids, clock, thumbnailSignal, b.logger, toolTimeout)
		if err != nil {
			return nil, nil, fmt.Errorf("创建缩略图 Worker: %w", err)
		}
		runners = append(runners, worker)
	}
	recovery, err := jobs.NewProcessingRecovery(processing, ids, clock, probeSignal, thumbnailSignal, b.logger,
		b.config.Media.ThumbnailWidth, b.config.Workers.LockTimeout)
	if err != nil {
		return nil, nil, err
	}
	group, err := jobs.NewGroup(recovery, runners...)
	return group, scanSignal, err
}
