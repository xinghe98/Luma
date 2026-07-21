package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

// ScanService 提供创建和查询持久化扫描任务的业务能力。
type ScanService struct {
	// sources 用于确认媒体源存在且已启用。
	sources repository.SourceRepository
	// scans 用于持久化扫描任务。
	scans repository.ScanRepository
	// ids 用于生成 scan_id。
	ids IDGenerator
	// clock 提供任务时间戳。
	clock Clock
	// notifier 在新任务写入后唤醒 Worker。
	notifier JobNotifier
}

// NewScanService 使用 Repository、标识、时钟和通知器创建扫描服务。
func NewScanService(
	sources repository.SourceRepository,
	scans repository.ScanRepository,
	ids IDGenerator,
	clock Clock,
	notifier JobNotifier,
) (*ScanService, error) {
	if sources == nil || scans == nil || ids == nil || clock == nil || notifier == nil {
		return nil, errors.New("扫描服务依赖不能为空")
	}
	return &ScanService{sources: sources, scans: scans, ids: ids, clock: clock, notifier: notifier}, nil
}

// Start 为启用的媒体源创建异步扫描任务并立即返回。
func (s *ScanService) Start(ctx context.Context, sourceID string) (domain.ScanJob, error) {
	source, err := s.sources.Get(ctx, sourceID)
	if err != nil {
		return domain.ScanJob{}, err
	}
	if !source.Enabled {
		return domain.ScanJob{}, fmt.Errorf("%w: 媒体源已禁用", domain.ErrSourceOffline)
	}
	id, err := s.ids.New("scan")
	if err != nil {
		return domain.ScanJob{}, err
	}
	now := s.clock.Now()
	job := domain.ScanJob{
		ID: id, SourceID: sourceID, Status: domain.ScanStatusPending,
		Phase: "queued", CreatedAt: now, UpdatedAt: now,
	}
	if err := s.scans.CreateJob(ctx, job); err != nil {
		return domain.ScanJob{}, err
	}
	s.notifier.Notify()
	return job, nil
}

// StartIfIdle 在媒体源空闲时创建扫描任务，并报告本次是否实际入队。
// 自动扫描调度器据此为运行中的扫描保留一次尾随重试，避免丢失文件事件。
func (s *ScanService) StartIfIdle(ctx context.Context, sourceID string) (bool, error) {
	_, err := s.Start(ctx, sourceID)
	if err == nil {
		return true, nil
	}
	if errors.Is(err, domain.ErrScanAlreadyRunning) {
		return false, nil
	}
	return false, err
}

// Get 返回指定扫描任务。
func (s *ScanService) Get(ctx context.Context, id string) (domain.ScanJob, error) {
	return s.scans.GetJob(ctx, id)
}

// Latest 返回指定媒体源或全局最近扫描任务。
func (s *ScanService) Latest(ctx context.Context, sourceID string) (domain.ScanJob, error) {
	return s.scans.LatestJob(ctx, sourceID)
}
