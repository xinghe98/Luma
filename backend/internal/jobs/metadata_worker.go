// Metadata worker persistently resolves catalog identities and rich provider metadata.
package jobs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/metadata"
	"github.com/xinghe98/Luma/backend/internal/repository"
	"github.com/xinghe98/Luma/backend/internal/storage"
	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

// MetadataWorker asynchronously consumes the dedicated catalog scrape queue.
type MetadataWorker struct {
	repository      repository.MetadataRepository
	sources         repository.SourceRepository
	sourceFactory   storage.SourceFactory
	coordinator     *metadata.Coordinator
	ids             WorkerIDGenerator
	clock           WorkerClock
	logger          *slog.Logger
	workerID        string
	refreshInterval time.Duration
	requestTimeout  time.Duration
}

// NewMetadataWorker creates a persistent scraper worker.
func NewMetadataWorker(repo repository.MetadataRepository, sources repository.SourceRepository,
	sourceFactory storage.SourceFactory, coordinator *metadata.Coordinator,
	ids WorkerIDGenerator, clock WorkerClock, logger *slog.Logger,
	refreshInterval, requestTimeout time.Duration) (*MetadataWorker, error) {
	if repo == nil || sources == nil || sourceFactory == nil || coordinator == nil ||
		ids == nil || clock == nil || logger == nil ||
		refreshInterval <= 0 || requestTimeout <= 0 {
		return nil, errors.New("刮削 Worker 依赖不能为空")
	}
	workerID, err := ids.New("metadataworker")
	if err != nil {
		return nil, err
	}
	return &MetadataWorker{
		repository: repo, sources: sources, sourceFactory: sourceFactory,
		coordinator: coordinator, ids: ids, clock: clock, logger: logger,
		workerID: workerID, refreshInterval: refreshInterval, requestTimeout: requestTimeout,
	}, nil
}

// Run recovers interrupted work and polls without blocking media scanning.
func (w *MetadataWorker) Run(ctx context.Context) error {
	if err := w.repository.RecoverMetadataJobs(ctx, w.clock.Now()); err != nil {
		return fmt.Errorf("恢复刮削任务: %w", err)
	}
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		if err := w.runOne(ctx); err != nil && !errors.Is(err, domain.ErrNoPendingJob) {
			if errors.Is(err, context.Canceled) {
				return nil
			}
			return err
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

func (w *MetadataWorker) runOne(ctx context.Context) error {
	now := w.clock.Now()
	if _, err := w.repository.EnqueuePendingMetadata(ctx, now, now.Add(-w.refreshInterval)); err != nil {
		return err
	}
	input, err := w.repository.ClaimMetadata(ctx, w.workerID, now)
	if err != nil {
		return err
	}
	requestCtx, cancel := context.WithTimeout(ctx, w.requestTimeout)
	patches, sidecarErr := w.loadSidecars(requestCtx, input)
	if sidecarErr != nil {
		cancel()
		return w.fail(ctx, input.ItemID, sidecarErr)
	}
	outcome, resolveErr := w.coordinator.Resolve(requestCtx, input, patches...)
	cancel()
	if resolveErr != nil {
		if errors.Is(resolveErr, metadata.ErrNoOnlineProvider) {
			return w.repository.SaveMetadataCandidates(ctx, input.ItemID, nil, w.clock.Now())
		}
		return w.fail(ctx, input.ItemID, resolveErr)
	}
	if outcome.Result != nil {
		if err := w.repository.CompleteMetadata(ctx, *outcome.Result, w.clock.Now()); err != nil {
			return w.fail(ctx, input.ItemID, err)
		}
		return nil
	}
	return w.repository.SaveMetadataCandidates(ctx, input.ItemID, outcome.Candidates, w.clock.Now())
}

// loadSidecars opens only conventionally named work-level NFO files through the
// source abstraction. It never constructs or opens an absolute path itself.
func (w *MetadataWorker) loadSidecars(ctx context.Context, input domain.CatalogScrapeInput) ([]scraper.MetadataPatch, error) {
	sidecars, err := w.repository.MetadataSidecars(ctx, input.ItemID)
	if err != nil {
		return nil, fmt.Errorf("读取 NFO 索引: %w", err)
	}
	selected := selectWorkSidecars(input.Kind, sidecars.MediaPaths, sidecars.SidecarPaths)
	if len(selected) == 0 {
		return nil, nil
	}
	source, err := w.sources.Get(ctx, sidecars.SourceID)
	if err != nil {
		return nil, fmt.Errorf("读取 NFO 媒体源: %w", err)
	}
	mediaSource, err := w.sourceFactory.Local(source.RootPath)
	if err != nil {
		return nil, fmt.Errorf("打开 NFO 媒体源: %w", err)
	}
	patches := make([]scraper.MetadataPatch, 0, len(selected))
	for _, relativePath := range selected {
		reader, err := mediaSource.Open(ctx, relativePath)
		if err != nil {
			return nil, fmt.Errorf("打开 NFO 侧车 %q: %w", relativePath, err)
		}
		patch, parseErr := w.coordinator.ParseSidecar(ctx, scraper.SidecarRequest{
			Kind: scraper.MediaKind(input.Kind), Filename: path.Base(filepath.ToSlash(relativePath)),
			Body: io.Reader(reader),
		})
		closeErr := reader.Close()
		if parseErr != nil {
			return nil, fmt.Errorf("解析 NFO 侧车 %q: %w", relativePath, parseErr)
		}
		if closeErr != nil {
			return nil, fmt.Errorf("关闭 NFO 侧车 %q: %w", relativePath, closeErr)
		}
		patches = append(patches, patch)
	}
	return patches, nil
}

func selectWorkSidecars(kind string, mediaPaths, sidecarPaths []string) []string {
	indexed := make(map[string]string, len(sidecarPaths))
	for _, value := range sidecarPaths {
		normalized := strings.Trim(filepath.ToSlash(value), "/")
		indexed[strings.ToLower(normalized)] = normalized
	}
	var desired []string
	switch kind {
	case domain.CatalogKindMovie:
		for _, mediaPath := range mediaPaths {
			normalized := strings.Trim(filepath.ToSlash(mediaPath), "/")
			parent := path.Dir(normalized)
			if parent == "." {
				parent = ""
			}
			desired = append(desired, path.Join(parent, "movie.nfo"))
			stem := strings.TrimSuffix(path.Base(normalized), path.Ext(normalized))
			desired = append(desired, path.Join(parent, stem+".nfo"))
		}
	case domain.CatalogKindSeries:
		for _, mediaPath := range mediaPaths {
			parts := strings.Split(strings.Trim(filepath.ToSlash(mediaPath), "/"), "/")
			root := ""
			if len(parts) > 1 {
				root = parts[0]
			}
			desired = append(desired, path.Join(root, "tvshow.nfo"))
		}
	}
	result := make([]string, 0, len(desired))
	seen := map[string]struct{}{}
	for _, value := range desired {
		if actual, ok := indexed[strings.ToLower(value)]; ok {
			if _, duplicate := seen[strings.ToLower(actual)]; duplicate {
				continue
			}
			seen[strings.ToLower(actual)] = struct{}{}
			result = append(result, actual)
		}
	}
	return result
}

func (w *MetadataWorker) fail(ctx context.Context, itemID string, cause error) error {
	code, message := "SCRAPE_FAILED", "影视资料刮削失败"
	retryAt := time.Time{}
	var providerErr *scraper.ProviderError
	if errors.As(cause, &providerErr) {
		code = "PROVIDER_" + string(providerErr.Kind)
		switch providerErr.Kind {
		case scraper.ErrorTemporary:
			retryAt = w.clock.Now().Add(time.Minute)
		case scraper.ErrorRateLimited:
			delay := providerErr.RetryAfter
			if delay <= 0 {
				delay = time.Minute
			}
			retryAt = w.clock.Now().Add(delay)
		}
	} else if errors.Is(cause, context.DeadlineExceeded) {
		code, retryAt = "PROVIDER_TIMEOUT", w.clock.Now().Add(time.Minute)
	}
	if providerErr != nil {
		w.logger.Warn("影视资料 Provider 操作失败", "catalog_item_id", itemID,
			"provider", providerErr.ProviderID, "operation", providerErr.Operation, "kind", providerErr.Kind)
	} else {
		w.logger.Warn("影视资料刮削失败", "catalog_item_id", itemID, "error", cause)
	}
	_, err := w.repository.FailMetadata(ctx, itemID, code, message, retryAt, w.clock.Now())
	return err
}
