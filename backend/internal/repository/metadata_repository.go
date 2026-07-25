// Metadata repository contracts isolate scraper workers from SQLite details.
package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// MetadataRepository persists catalog scrape jobs, candidates, rich metadata, and artwork.
type MetadataRepository interface {
	// QueueMetadataForScan 为一次成功扫描创建资料运行并只入队本次关联的未完成作品。
	QueueMetadataForScan(context.Context, string, string, time.Time) (int, error)
	// EnqueuePendingMetadata creates jobs for pending or stale works without disturbing active backoff.
	EnqueuePendingMetadata(context.Context, time.Time, time.Time) (int, error)
	// ClaimMetadata atomically claims one due scrape job.
	ClaimMetadata(context.Context, string, time.Time) (domain.CatalogScrapeInput, error)
	// SaveMetadataCandidates completes a scrape as needs_review with scored candidates.
	SaveMetadataCandidates(context.Context, string, []domain.CatalogMetadataCandidate, time.Time) error
	// CompleteMetadata commits normalized rich metadata and selected artwork references.
	CompleteMetadata(context.Context, domain.CatalogMetadataResult, time.Time) error
	// FailMetadata records a sanitized failure and reports whether it was requeued.
	FailMetadata(context.Context, string, string, string, time.Time, time.Time) (bool, error)
	// RefreshMetadata requeues one item or all visible items in an optional source.
	RefreshMetadata(context.Context, string, string, time.Time) (int, error)
	// SelectMetadataIdentity locks a user-selected provider identity with optimistic concurrency.
	SelectMetadataIdentity(context.Context, string, string, string, int, time.Time) error
	// ListMetadataCandidates returns persisted candidates for an item.
	ListMetadataCandidates(context.Context, string) ([]domain.CatalogMetadataCandidate, error)
	// GetCatalogArtwork enforces source grants before returning an artwork reference.
	GetCatalogArtwork(context.Context, string, string) (domain.CatalogArtwork, error)
	// UpdateCatalogArtworkCache records a validated local cache object.
	UpdateCatalogArtworkCache(context.Context, string, string, string, string, time.Time) error
	// RecoverMetadataJobs requeues work left running by an interrupted process.
	RecoverMetadataJobs(context.Context, time.Time) error
	// MetadataSidecars returns media and NFO paths used to select safe work-level sidecars.
	MetadataSidecars(context.Context, string) (domain.CatalogSidecarContext, error)
}
