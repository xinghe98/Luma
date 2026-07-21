package jobs

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

type fakeAutoScanSources struct {
	sources []domain.Source
	err     error
}

func (f fakeAutoScanSources) List(context.Context) ([]domain.Source, error) {
	return f.sources, f.err
}

type fakeAutoScanStarter struct {
	mu      sync.Mutex
	calls   []string
	results map[string]error
	started map[string]bool
}

func (f *fakeAutoScanStarter) StartIfIdle(_ context.Context, sourceID string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, sourceID)
	if f.results == nil {
		return f.started == nil || f.started[sourceID], nil
	}
	return f.started == nil || f.started[sourceID], f.results[sourceID]
}

func (f *fakeAutoScanStarter) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.calls)
}

func (f *fakeAutoScanStarter) calledIDs() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.calls...)
}

type fixedClock struct{ now time.Time }

func (c fixedClock) Now() time.Time { return c.now }

func TestAutoScanSchedulerDisabledWaitsForCancel(t *testing.T) {
	starter := &fakeAutoScanStarter{}
	scheduler, err := NewAutoScanScheduler(
		fakeAutoScanSources{}, starter,
		config.AutoScanConfig{Enabled: false, Mode: config.AutoScanModePoll, Interval: time.Minute, Debounce: time.Second},
		fixedClock{now: time.Unix(1, 0)}, slog.Default(),
	)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- scheduler.Run(ctx) }()
	time.Sleep(20 * time.Millisecond)
	cancel()
	if err := <-done; err != nil {
		t.Fatalf("run error: %v", err)
	}
	if starter.callCount() != 0 {
		t.Fatalf("disabled scheduler must not start scans, calls=%v", starter.calledIDs())
	}
}

func TestAutoScanSchedulerPollStartsEnabledSourcesOnly(t *testing.T) {
	root := t.TempDir()
	starter := &fakeAutoScanStarter{}
	sources := fakeAutoScanSources{sources: []domain.Source{
		{ID: "on", Type: domain.SourceTypeLocal, RootPath: root, Enabled: true},
		{ID: "off", Type: domain.SourceTypeLocal, RootPath: root, Enabled: false},
		{ID: "empty", Type: domain.SourceTypeLocal, RootPath: "", Enabled: true},
	}}
	scheduler, err := NewAutoScanScheduler(
		sources, starter,
		config.AutoScanConfig{
			Enabled: true, Mode: config.AutoScanModePoll,
			Interval: time.Hour, Debounce: 5 * time.Millisecond,
		},
		fixedClock{now: time.Unix(1, 0)}, slog.Default(),
	)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = scheduler.Run(ctx) }()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if starter.callCount() >= 1 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	cancel()
	ids := starter.calledIDs()
	if len(ids) == 0 {
		t.Fatal("expected at least one StartIfIdle call")
	}
	for _, id := range ids {
		if id != "on" {
			t.Fatalf("unexpected source started: %s in %v", id, ids)
		}
	}
}

func TestAutoScanSchedulerDebounceCoalescesEvents(t *testing.T) {
	starter := &fakeAutoScanStarter{}
	scheduler, err := NewAutoScanScheduler(
		fakeAutoScanSources{}, starter,
		config.AutoScanConfig{
			Enabled: true, Mode: config.AutoScanModeWatch,
			Interval: time.Hour, Debounce: 40 * time.Millisecond,
		},
		fixedClock{now: time.Unix(1, 0)}, slog.Default(),
	)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	scheduler.scheduleSource(ctx, "src-a")
	scheduler.scheduleSource(ctx, "src-a")
	scheduler.scheduleSource(ctx, "src-a")
	time.Sleep(80 * time.Millisecond)
	if got := starter.callCount(); got != 1 {
		t.Fatalf("debounce should coalesce to 1 call, got %d (%v)", got, starter.calledIDs())
	}
}

func TestAutoScanSchedulerIgnoresAlreadyRunning(t *testing.T) {
	// StartIfIdle 契约由 starter 实现；调度器应把任意 nil 错误视为成功。
	starter := &fakeAutoScanStarter{results: map[string]error{"src": nil}}
	scheduler, err := NewAutoScanScheduler(
		fakeAutoScanSources{sources: []domain.Source{
			{ID: "src", Type: domain.SourceTypeLocal, RootPath: t.TempDir(), Enabled: true},
		}},
		starter,
		config.AutoScanConfig{
			Enabled: true, Mode: config.AutoScanModePoll,
			Interval: time.Hour, Debounce: 5 * time.Millisecond,
		},
		fixedClock{now: time.Unix(1, 0)}, slog.Default(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := scheduler.reconcile(context.Background(), false, true); err != nil {
		t.Fatal(err)
	}
	if starter.callCount() != 1 {
		t.Fatalf("calls=%v", starter.calledIDs())
	}
}

func TestAutoScanSchedulerWatchTriggersAfterFileCreate(t *testing.T) {
	root := t.TempDir()
	starter := &fakeAutoScanStarter{}
	scheduler, err := NewAutoScanScheduler(
		fakeAutoScanSources{sources: []domain.Source{
			{ID: "watched", Type: domain.SourceTypeLocal, RootPath: root, Enabled: true},
		}},
		starter,
		config.AutoScanConfig{
			Enabled: true, Mode: config.AutoScanModeWatch,
			Interval: time.Hour, Debounce: 30 * time.Millisecond,
		},
		fixedClock{now: time.Unix(1, 0)}, slog.Default(),
	)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = scheduler.Run(ctx) }()

	// 等待 watcher 注册完成。
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		scheduler.mu.Lock()
		ready := len(scheduler.rootBySource) > 0
		scheduler.mu.Unlock()
		if ready {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	if err := os.WriteFile(filepath.Join(root, "clip.mp4"), []byte("data"), 0o644); err != nil {
		t.Fatal(err)
	}

	deadline = time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if starter.callCount() >= 1 {
			cancel()
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	cancel()
	t.Fatalf("expected watch event to schedule scan, calls=%v", starter.calledIDs())
}

func TestPathIsWithinRoot(t *testing.T) {
	root := filepath.Clean(`/media/library`)
	if !pathIsWithinRoot(root, root) {
		t.Fatal("root should contain itself")
	}
	if !pathIsWithinRoot(root, filepath.Join(root, "a", "b.mp4")) {
		t.Fatal("nested path should be within root")
	}
	if pathIsWithinRoot(root, filepath.Clean(`/media/library-other`)) {
		t.Fatal("sibling prefix must not match")
	}
}
