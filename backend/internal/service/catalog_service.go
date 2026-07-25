package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/catalog"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

type CatalogService struct {
	repository repository.CatalogRepository
	clock      Clock
}

func NewCatalogService(repository repository.CatalogRepository, clock Clock) (*CatalogService, error) {
	if repository == nil || clock == nil {
		return nil, errors.New("作品库服务依赖不能为空")
	}
	return &CatalogService{repository: repository, clock: clock}, nil
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
