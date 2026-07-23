package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type CatalogRepository interface {
	ListCandidates(context.Context, int) ([]domain.CatalogCandidate, error)
	SaveMatch(context.Context, domain.CatalogMatch, time.Time) error
	Prune(context.Context, time.Time) error
	List(context.Context, domain.CatalogListRequest, string) ([]domain.CatalogItem, error)
	Get(context.Context, string, string) (domain.CatalogItem, error)
	ListIssues(context.Context, int) ([]domain.CatalogIssue, error)
	GetCandidate(context.Context, string) (domain.CatalogCandidate, error)
}
