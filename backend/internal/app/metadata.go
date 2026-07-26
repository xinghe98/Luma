// 本文件组装元数据 Provider、限速传输层和后台 Worker，并由应用统一管理传输层生命周期。
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

// buildMetadataWorkers 注册已编译 Provider 并创建 Worker；返回的传输层必须由应用关闭空闲连接。
func buildMetadataWorkers(cfg config.MetadataConfig, catalogRepository *dbrepo.CatalogRepository,
	sources repository.SourceRepository, sourceFactory storage.SourceFactory,
	ids platform.SecureIDGenerator, clock platform.RealClock, logger *slog.Logger, signal *jobs.Signal) ([]jobs.Runner, *metadata.Registry, *http.Transport, error) {
	// 测试可直接构造 Config，因此这里补齐与正常加载路径一致的运行时默认值。
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
			return nil, nil, nil, err
		}
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if cfg.ProxyURL != "" {
		proxyURL, err := url.Parse(cfg.ProxyURL)
		if err != nil || (proxyURL.Scheme != "http" && proxyURL.Scheme != "https") || proxyURL.Host == "" {
			return nil, nil, nil, fmt.Errorf("metadata.proxy_url must be an absolute HTTP/HTTPS URL")
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
			return nil, nil, nil, fmt.Errorf("create TMDb provider: %w", err)
		}
		if err := registry.Register(value); err != nil {
			return nil, nil, nil, err
		}
	}
	for id, provider := range cfg.Providers {
		if provider.Enabled && id != "nfo" && id != "tmdb" {
			return nil, nil, nil, fmt.Errorf("metadata provider %q is enabled but not compiled into this server", id)
		}
	}
	coordinator, err := metadata.NewCoordinator(registry, scraper.Locale{
		Language: cfg.Language, Region: cfg.Region, FallbackLanguages: cfg.FallbackLanguages,
	}, cfg.AutoMatchThreshold, cfg.AutoMatchMargin)
	if err != nil {
		return nil, nil, nil, err
	}
	// 即使未配置在线 Provider 也保留 Worker：它会把本次扫描的作品归为无候选终态，
	// 避免客户端一直停在“正在匹配影视资料”。
	runners := make([]jobs.Runner, 0, cfg.Workers)
	for range cfg.Workers {
		worker, err := jobs.NewMetadataWorker(catalogRepository, sources, sourceFactory, coordinator, ids, clock, logger,
			cfg.RefreshInterval, cfg.RequestTimeout, signal)
		if err != nil {
			return nil, nil, nil, err
		}
		runners = append(runners, worker)
	}
	return runners, registry, transport, nil
}

func metadataRequestTimeout(value time.Duration) time.Duration {
	if value <= 0 {
		return 15 * time.Second
	}
	return value
}

// rateLimitedTransport 在全部刮削 Worker 之间限制请求速率，并允许等待期间取消。
type rateLimitedTransport struct {
	next     http.RoundTripper
	interval time.Duration
	mu       sync.Mutex
	nextAt   time.Time
}

// RoundTrip 等待进程级限速窗口后转发请求；上下文取消时不再发送请求。
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
