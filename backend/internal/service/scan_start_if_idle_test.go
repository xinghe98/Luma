package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type startIfIdleSources struct {
	source domain.Source
	err    error
}

func (s startIfIdleSources) List(context.Context) ([]domain.Source, error) { return nil, nil }
func (s startIfIdleSources) Get(context.Context, string) (domain.Source, error) {
	return s.source, s.err
}
func (s startIfIdleSources) Create(context.Context, domain.Source) error { return nil }
func (s startIfIdleSources) Update(context.Context, domain.Source) error { return nil }
func (s startIfIdleSources) SetStatus(context.Context, string, string, time.Time) error {
	return nil
}
func (s startIfIdleSources) SoftDelete(context.Context, string, time.Time) error { return nil }

type startIfIdleScans struct {
	createErr error
	created   int
}

func (s *startIfIdleScans) CreateJob(context.Context, domain.ScanJob) error {
	s.created++
	return s.createErr
}
func (s *startIfIdleScans) GetJob(context.Context, string) (domain.ScanJob, error) {
	return domain.ScanJob{}, nil
}
func (s *startIfIdleScans) LatestJob(context.Context, string) (domain.ScanJob, error) {
	return domain.ScanJob{}, nil
}
func (s *startIfIdleScans) HasActiveJob(context.Context, string) (bool, error) { return false, nil }
func (s *startIfIdleScans) ClaimNextJob(context.Context, string, time.Time) (domain.ScanJob, error) {
	return domain.ScanJob{}, domain.ErrNoPendingScan
}
func (s *startIfIdleScans) InterruptRunningJobs(context.Context, time.Time) error { return nil }
func (s *startIfIdleScans) NeedsQuickHash(context.Context, string, domain.DiscoveredFile) (bool, error) {
	return false, nil
}
func (s *startIfIdleScans) ReconcileFile(context.Context, string, string, string, domain.DiscoveredFile, time.Time) (domain.ReconcileResult, error) {
	return domain.ReconcileResult{}, nil
}
func (s *startIfIdleScans) ReconcileSidecar(context.Context, string, string, domain.DiscoveredFile, time.Time) error {
	return nil
}
func (s *startIfIdleScans) MarkFileFailed(context.Context, string, string, domain.DiscoveredFile, time.Time) error {
	return nil
}
func (s *startIfIdleScans) AddProgress(context.Context, string, int64, int64, int64, time.Time) error {
	return nil
}
func (s *startIfIdleScans) CompleteJob(context.Context, string, string, time.Time) error { return nil }
func (s *startIfIdleScans) FinishJobWithoutCommit(context.Context, string, string, string, string, time.Time) error {
	return nil
}

type startIfIdleIDs struct{}

func (startIfIdleIDs) New(string) (string, error) { return "scan_test", nil }

type startIfIdleClock struct{}

func (startIfIdleClock) Now() time.Time { return time.Unix(10, 0).UTC() }

type startIfIdleNotifier struct{ n int }

func (n *startIfIdleNotifier) Notify() { n.n++ }

func TestScanServiceStartIfIdleTreatsAlreadyRunningAsSuccess(t *testing.T) {
	scans := &startIfIdleScans{createErr: domain.ErrScanAlreadyRunning}
	svc, err := NewScanService(
		startIfIdleSources{source: domain.Source{ID: "src", Enabled: true}},
		scans, startIfIdleIDs{}, startIfIdleClock{}, &startIfIdleNotifier{},
	)
	if err != nil {
		t.Fatal(err)
	}
	started, err := svc.StartIfIdle(context.Background(), "src")
	if err != nil {
		t.Fatalf("StartIfIdle error=%v", err)
	}
	if started {
		t.Fatal("active scan must not be reported as newly started")
	}
	if scans.created != 1 {
		t.Fatalf("created=%d", scans.created)
	}
}

func TestScanServiceStartIfIdlePropagatesOtherErrors(t *testing.T) {
	svc, err := NewScanService(
		startIfIdleSources{err: domain.ErrSourceNotFound},
		&startIfIdleScans{}, startIfIdleIDs{}, startIfIdleClock{}, &startIfIdleNotifier{},
	)
	if err != nil {
		t.Fatal(err)
	}
	_, err = svc.StartIfIdle(context.Background(), "missing")
	if !errors.Is(err, domain.ErrSourceNotFound) {
		t.Fatalf("error=%v", err)
	}
}
