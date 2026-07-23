package jobs

import (
	"context"
	"errors"
	"log/slog"
	"time"
)

// CatalogSynchronizerUseCase is the small background-facing part of the
// catalog service. Keeping it separate prevents HTTP handlers from owning
// reconciliation work.
type CatalogSynchronizerUseCase interface {
	Sync(context.Context) error
}

// CatalogSynchronizer turns completed-scan notifications into batched catalog
// reconciliation. The sparse fallback catches work left by a process restart.
type CatalogSynchronizer struct {
	service CatalogSynchronizerUseCase
	signal  *Signal
	logger  *slog.Logger
}

func NewCatalogSynchronizer(service CatalogSynchronizerUseCase, signal *Signal, logger *slog.Logger) (*CatalogSynchronizer, error) {
	if service == nil || signal == nil || logger == nil {
		return nil, errors.New("作品库后台整理依赖不能为空")
	}
	return &CatalogSynchronizer{service: service, signal: signal, logger: logger}, nil
}

func (s *CatalogSynchronizer) Run(ctx context.Context) error {
	if err := s.sync(ctx); err != nil && !errors.Is(err, context.Canceled) {
		s.logger.Error("启动作品库整理失败", "error", err)
	}
	ticker := time.NewTicker(15 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-s.signal.C():
			if err := s.sync(ctx); err != nil && !errors.Is(err, context.Canceled) {
				s.logger.Error("作品库整理失败", "error", err)
			}
		case <-ticker.C:
			if err := s.sync(ctx); err != nil && !errors.Is(err, context.Canceled) {
				s.logger.Error("作品库定期整理失败", "error", err)
			}
		}
	}
}

func (s *CatalogSynchronizer) sync(ctx context.Context) error {
	syncCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	return s.service.Sync(syncCtx)
}
