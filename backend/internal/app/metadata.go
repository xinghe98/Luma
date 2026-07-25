// Metadata composition wires configured scraper implementations into provider-neutral workers.
package app

import (
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/jobs"
	"github.com/xinghe98/Luma/backend/internal/metadata"
	"github.com/xinghe98/Luma/backend/internal/platform"
	"github.com/xinghe98/Luma/backend/internal/providers/nfo"
	"github.com/xinghe98/Luma/backend/internal/providers/tmdb"
	"github.com/xinghe98/Luma/backend/internal/repository"
	dbrepo "github.com/xinghe98/Luma/backend/internal/repository/sqlite"
	"github.com/xinghe98/Luma/backend/internal/storage"
	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

// buildMetadataWorkers registers compiled providers and creates online scraper workers.
func buildMetadataWorkers(cfg config.MetadataConfig, catalogRepository *dbrepo.CatalogRepository,
	sources repository.SourceRepository, sourceFactory storage.SourceFactory,
	ids platform.SecureIDGenerator, clock platform.RealClock, logger *slog.Logger) ([]jobs.Runner, *metadata.Registry, error) {
	// App tests and embedders may construct Config directly instead of going
	// through config.Load. Preserve that older call path with runtime defaults;
	// normal server startup has already applied and validated the same values.
	if cfg.RefreshInterval <= 0 {
		cfg.RefreshInterval = 30 * 24 * time.Hour
	}
	cfg.RequestTimeout = metadataRequestTimeout(cfg.RequestTimeout)
	if cfg.Workers <= 0 {
		cfg.Workers = 1
	}
	if cfg.RequestsPerSecond <= 0 {
		cfg.RequestsPerSecond = 4
	}
	registry := metadata.NewRegistry()
	if provider, ok := cfg.Providers["nfo"]; ok && provider.Enabled {
		if err := registry.Register(nfo.New()); err != nil {
			return nil, nil, err
		}
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if cfg.ProxyURL != "" {
		proxyURL, err := url.Parse(cfg.ProxyURL)
		if err != nil || (proxyURL.Scheme != "http" && proxyURL.Scheme != "https") || proxyURL.Host == "" {
			return nil, nil, fmt.Errorf("metadata.proxy_url must be an absolute HTTP/HTTPS URL")
		}
		transport.Proxy = http.ProxyURL(proxyURL)
	}
	client := &http.Client{
		Transport: &rateLimitedTransport{next: transport, interval: time.Second / time.Duration(cfg.RequestsPerSecond)},
		Timeout:   cfg.RequestTimeout,
	}
	if provider, ok := cfg.Providers["tmdb"]; ok && provider.Enabled {
		value, err := tmdb.New(provider.Options, client)
		if err != nil {
			return nil, nil, fmt.Errorf("create TMDb provider: %w", err)
		}
		if err := registry.Register(value); err != nil {
			return nil, nil, err
		}
	}
	for id, provider := range cfg.Providers {
		if provider.Enabled && id != "nfo" && id != "tmdb" {
			return nil, nil, fmt.Errorf("metadata provider %q is enabled but not compiled into this server", id)
		}
	}
	coordinator, err := metadata.NewCoordinator(registry, scraper.Locale{
		Language: cfg.Language, Region: cfg.Region, FallbackLanguages: cfg.FallbackLanguages,
	}, cfg.AutoMatchThreshold, cfg.AutoMatchMargin)
	if err != nil {
		return nil, nil, err
	}
	hasResolver := len(registry.ProvidersFor(scraper.MediaKindMovie, scraper.CapabilitySidecar)) > 0 ||
		len(registry.ProvidersFor(scraper.MediaKindSeries, scraper.CapabilitySidecar)) > 0 ||
		len(registry.ProvidersFor(scraper.MediaKindMovie, scraper.CapabilitySearch)) > 0 ||
		len(registry.ProvidersFor(scraper.MediaKindSeries, scraper.CapabilitySearch)) > 0
	if !hasResolver {
		return nil, registry, nil
	}
	runners := make([]jobs.Runner, 0, cfg.Workers)
	for range cfg.Workers {
		worker, err := jobs.NewMetadataWorker(catalogRepository, sources, sourceFactory, coordinator, ids, clock, logger,
			cfg.RefreshInterval, cfg.RequestTimeout)
		if err != nil {
			return nil, nil, err
		}
		runners = append(runners, worker)
	}
	return runners, registry, nil
}

func metadataRequestTimeout(value time.Duration) time.Duration {
	if value <= 0 {
		return 15 * time.Second
	}
	return value
}

// rateLimitedTransport spaces outbound provider requests across all scraper
// workers while still allowing cancellation during the wait.
type rateLimitedTransport struct {
	next     http.RoundTripper
	interval time.Duration
	mu       sync.Mutex
	nextAt   time.Time
}

// RoundTrip enforces the configured process-wide request rate before delegating
// to the credential-aware HTTP transport.
func (t *rateLimitedTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	t.mu.Lock()
	now := time.Now()
	start := now
	if t.nextAt.After(start) {
		start = t.nextAt
	}
	t.nextAt = start.Add(t.interval)
	t.mu.Unlock()
	if delay := time.Until(start); delay > 0 {
		timer := time.NewTimer(delay)
		defer timer.Stop()
		select {
		case <-request.Context().Done():
			return nil, request.Context().Err()
		case <-timer.C:
		}
	}
	return t.next.RoundTrip(request)
}
