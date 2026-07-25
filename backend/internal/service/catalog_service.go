package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/catalog"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/metadata"
	"github.com/xinghe98/Luma/backend/internal/repository"
	"github.com/xinghe98/Luma/backend/internal/storage"
	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

type CatalogService struct {
	repository         repository.CatalogRepository
	clock              Clock
	metadataRepository repository.MetadataRepository
	metadataRegistry   *metadata.Registry
	artworkStore       *storage.MetadataArtworkStore
	metadataTimeout    time.Duration
}

func NewCatalogService(repository repository.CatalogRepository, clock Clock) (*CatalogService, error) {
	if repository == nil || clock == nil {
		return nil, errors.New("作品库服务依赖不能为空")
	}
	return &CatalogService{repository: repository, clock: clock}, nil
}

// EnableMetadata attaches the optional scraper subsystem before the HTTP server starts.
func (s *CatalogService) EnableMetadata(repo repository.MetadataRepository, registry *metadata.Registry,
	store *storage.MetadataArtworkStore, requestTimeout time.Duration) error {
	if repo == nil || registry == nil || store == nil || requestTimeout <= 0 {
		return errors.New("刮削服务依赖不能为空")
	}
	s.metadataRepository = repo
	s.metadataRegistry = registry
	s.artworkStore = store
	s.metadataTimeout = requestTimeout
	return nil
}

// MetadataCandidates returns persisted candidates for manual identification.
func (s *CatalogService) MetadataCandidates(ctx context.Context, itemID string) ([]domain.CatalogMetadataCandidate, error) {
	if s.metadataRepository == nil || strings.TrimSpace(itemID) == "" {
		return nil, fmt.Errorf("%w: 刮削服务未启用或作品 ID 无效", domain.ErrInvalidRequest)
	}
	return s.metadataRepository.ListMetadataCandidates(ctx, itemID)
}

// RefreshMetadata queues one item, one source, or all works for asynchronous refresh.
func (s *CatalogService) RefreshMetadata(ctx context.Context, itemID, sourceID string) (int, error) {
	if s.metadataRepository == nil {
		return 0, fmt.Errorf("%w: 刮削服务未启用", domain.ErrInvalidRequest)
	}
	itemID, sourceID = strings.TrimSpace(itemID), strings.TrimSpace(sourceID)
	count, err := s.metadataRepository.RefreshMetadata(ctx, itemID, sourceID, s.clock.Now())
	if err == nil && itemID != "" && count == 0 {
		return 0, domain.ErrCatalogNotFound
	}
	return count, err
}

// SelectMetadataIdentity locks a user-selected provider identity and queues its details.
func (s *CatalogService) SelectMetadataIdentity(ctx context.Context, itemID, provider, providerItemID string, revision int) error {
	if s.metadataRepository == nil || s.metadataRegistry == nil {
		return fmt.Errorf("%w: 刮削服务未启用", domain.ErrInvalidRequest)
	}
	itemID, provider, providerItemID = strings.TrimSpace(itemID), strings.TrimSpace(provider), strings.TrimSpace(providerItemID)
	if itemID == "" || provider == "" || providerItemID == "" || len(provider) > 32 ||
		len(providerItemID) > 256 || revision < 1 {
		return fmt.Errorf("%w: Provider 身份或版本无效", domain.ErrInvalidRequest)
	}
	if _, ok := s.metadataRegistry.Provider(provider); !ok {
		return fmt.Errorf("%w: 未注册的 Provider %q", domain.ErrInvalidRequest, provider)
	}
	return s.metadataRepository.SelectMetadataIdentity(ctx, itemID, provider, providerItemID, revision, s.clock.Now())
}

// MetadataProviders returns sanitized registered provider capabilities and optional health.
func (s *CatalogService) MetadataProviders(ctx context.Context) []domain.MetadataProviderStatus {
	if s.metadataRegistry == nil {
		return nil
	}
	result := make([]domain.MetadataProviderStatus, 0)
	for _, descriptor := range s.metadataRegistry.Descriptors() {
		value := domain.MetadataProviderStatus{ID: descriptor.ID, Name: descriptor.Name, Enabled: true}
		for _, capability := range descriptor.Capabilities {
			value.Capabilities = append(value.Capabilities, string(capability))
		}
		provider, _ := s.metadataRegistry.Provider(descriptor.ID)
		if health, ok := provider.(scraper.HealthChecker); ok {
			checkCtx, cancel := context.WithTimeout(ctx, s.metadataTimeout)
			status := health.CheckHealth(checkCtx)
			cancel()
			value.Available, value.Message = status.Available, status.Message
		} else {
			value.Available = true
		}
		result = append(result, value)
	}
	return result
}

// Artwork returns authorized provider artwork, populating the local cache on first access.
func (s *CatalogService) Artwork(ctx context.Context, artworkID, userID, ifNoneMatch string) (domain.CatalogArtworkContent, error) {
	if s.metadataRepository == nil || s.metadataRegistry == nil || s.artworkStore == nil {
		return domain.CatalogArtworkContent{}, fmt.Errorf("%w: 刮削服务未启用", domain.ErrInvalidRequest)
	}
	artwork, err := s.metadataRepository.GetCatalogArtwork(ctx, artworkID, userID)
	if err != nil {
		return domain.CatalogArtworkContent{}, err
	}
	if artwork.Status == "ready" && artwork.StorageKey != "" {
		data, readErr := s.artworkStore.Read(artwork.StorageKey)
		if readErr == nil {
			etag := `"` + artwork.ContentSHA256 + `"`
			return domain.CatalogArtworkContent{
				Data: data, MIMEType: artwork.MIMEType, ETag: etag,
				NotModified: ifNoneMatch != "" && ifNoneMatch == etag,
			}, nil
		}
	}
	provider, ok := s.metadataRegistry.Provider(artwork.Provider)
	if !ok {
		return domain.CatalogArtworkContent{}, domain.ErrCatalogNotFound
	}
	fetcher, ok := provider.(scraper.ArtworkFetcher)
	if !ok {
		return domain.CatalogArtworkContent{}, domain.ErrCatalogNotFound
	}
	requestCtx, cancel := context.WithTimeout(ctx, s.metadataTimeout)
	content, err := fetcher.OpenArtwork(requestCtx, scraper.ArtworkRequest{
		Reference: scraper.ArtworkRef{ProviderID: artwork.Provider, Key: artwork.OpaqueKey},
	})
	if err != nil {
		cancel()
		return domain.CatalogArtworkContent{}, err
	}
	defer content.Body.Close()
	mimeType, _, _ := mime.ParseMediaType(content.MIMEType)
	if !strings.HasPrefix(mimeType, "image/") {
		cancel()
		return domain.CatalogArtworkContent{}, errors.New("Provider 返回的海报不是图片")
	}
	key, sha, err := s.artworkStore.Write(artwork.ID, io.LimitReader(content.Body, storage.MaxMetadataArtworkBytes+1))
	cancel()
	if err != nil {
		return domain.CatalogArtworkContent{}, err
	}
	if err := s.metadataRepository.UpdateCatalogArtworkCache(ctx, artwork.ID, key, mimeType, sha, s.clock.Now()); err != nil {
		return domain.CatalogArtworkContent{}, err
	}
	data, err := s.artworkStore.Read(key)
	if err != nil {
		return domain.CatalogArtworkContent{}, err
	}
	etag := `"` + sha + `"`
	return domain.CatalogArtworkContent{
		Data: data, MIMEType: mimeType, ETag: etag,
		NotModified: ifNoneMatch != "" && ifNoneMatch == etag,
	}, nil
}

func (s *CatalogService) List(ctx context.Context, request domain.CatalogListRequest, userID string) ([]domain.CatalogItem, error) {
	request.Query = strings.TrimSpace(request.Query)
	if len([]rune(request.Query)) > 200 {
		return nil, fmt.Errorf("%w: q 最多 200 个字符", domain.ErrInvalidRequest)
	}
	if request.Kind != "" && request.Kind != domain.CatalogKindMovie && request.Kind != domain.CatalogKindSeries {
		return nil, fmt.Errorf("%w: kind 必须是 movie 或 series", domain.ErrInvalidRequest)
	}
	if request.Limit == 0 {
		request.Limit = 50
	}
	if request.Limit < 1 || request.Limit > 100 {
		return nil, fmt.Errorf("%w: limit 必须在 1 到 100 之间", domain.ErrInvalidRequest)
	}
	return s.repository.List(ctx, request, userID)
}

func (s *CatalogService) Get(ctx context.Context, id, userID string) (domain.CatalogItem, error) {
	if strings.TrimSpace(id) == "" {
		return domain.CatalogItem{}, fmt.Errorf("%w: 作品 ID 无效", domain.ErrInvalidRequest)
	}
	return s.repository.Get(ctx, id, userID)
}

func (s *CatalogService) Issues(ctx context.Context, limit int) ([]domain.CatalogIssue, error) {
	if limit == 0 {
		limit = 50
	}
	if limit < 1 || limit > 100 {
		return nil, fmt.Errorf("%w: limit 必须在 1 到 100 之间", domain.ErrInvalidRequest)
	}
	return s.repository.ListIssues(ctx, limit)
}

func (s *CatalogService) UpdateMatch(ctx context.Context, command domain.UpdateCatalogMatchCommand) error {
	candidate, err := s.repository.GetCandidate(ctx, command.MediaID)
	if err != nil {
		return err
	}
	if command.Ignored {
		return s.repository.SaveMatch(ctx, domain.CatalogMatch{MediaID: candidate.MediaID, SourceID: candidate.SourceID, Ignored: true, Locked: true, MediaUpdatedAt: candidate.MediaUpdatedAt}, s.clock.Now())
	}
	title := strings.Join(strings.Fields(command.Title), " ")
	if title == "" || len([]rune(title)) > 200 {
		return fmt.Errorf("%w: 作品标题须为 1 到 200 个字符", domain.ErrInvalidRequest)
	}
	kind := command.Kind
	if kind == "" {
		if candidate.LibraryKind == domain.LibraryKindTV {
			kind = domain.CatalogKindSeries
		} else {
			kind = domain.CatalogKindMovie
		}
	}
	if kind != domain.CatalogKindMovie && kind != domain.CatalogKindSeries {
		return fmt.Errorf("%w: kind 无效", domain.ErrInvalidRequest)
	}
	if command.Year != nil && (*command.Year < 1800 || *command.Year > 3000) {
		return fmt.Errorf("%w: year 无效", domain.ErrInvalidRequest)
	}
	if kind == domain.CatalogKindSeries {
		if command.SeasonNumber == nil || command.EpisodeNumber == nil || *command.SeasonNumber < 0 || *command.EpisodeNumber < 1 {
			return fmt.Errorf("%w: 剧集必须提供有效季号和集号", domain.ErrInvalidRequest)
		}
	}
	episodeTitle := ""
	if command.EpisodeNumber != nil {
		episodeTitle = fmt.Sprintf("第 %d 集", *command.EpisodeNumber)
	}
	return s.repository.SaveMatch(ctx, domain.CatalogMatch{MediaID: candidate.MediaID, SourceID: candidate.SourceID,
		Kind: kind, Title: title, SortTitle: catalog.NormalizeTitle(title), Year: command.Year,
		SeasonNumber: command.SeasonNumber, EpisodeNumber: command.EpisodeNumber, EpisodeTitle: episodeTitle,
		Status: domain.CatalogMatchMatched, Confidence: 100, Locked: true, MediaUpdatedAt: candidate.MediaUpdatedAt}, s.clock.Now())
}

func (s *CatalogService) Sync(ctx context.Context) error {
	if err := s.repository.Prune(ctx, s.clock.Now()); err != nil {
		return err
	}
	for batch := 0; batch < 100; batch++ {
		candidates, err := s.repository.ListCandidates(ctx, 200)
		if err != nil {
			return err
		}
		if len(candidates) == 0 {
			return nil
		}
		matches := make([]domain.CatalogMatch, 0, len(candidates))
		for _, candidate := range candidates {
			matches = append(matches, catalog.Match(candidate))
		}
		now := s.clock.Now()
		if bulk, ok := s.repository.(interface {
			SaveMatches(context.Context, []domain.CatalogMatch, time.Time) error
		}); ok {
			if err := bulk.SaveMatches(ctx, matches, now); err != nil {
				return err
			}
			continue
		}
		for _, match := range matches {
			if err := s.repository.SaveMatch(ctx, match, now); err != nil {
				return err
			}
		}
	}
	return fmt.Errorf("作品整理队列超过单次同步上限")
}
