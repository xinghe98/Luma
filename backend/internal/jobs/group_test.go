package jobs

import (
	"context"
	"sync"
	"testing"
	"time"
)

type scanRecoveryFake struct {
	mu    sync.Mutex
	calls int
}

func (f *scanRecoveryFake) InterruptRunningJobs(context.Context, time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	return nil
}

func (f *scanRecoveryFake) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

type groupRecoveryFake struct {
	mu           sync.Mutex
	prepareCalls int
}

func (f *groupRecoveryFake) Prepare(context.Context) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.prepareCalls++
	return nil
}

func (f *groupRecoveryFake) Run(ctx context.Context) error {
	<-ctx.Done()
	return nil
}

func (f *groupRecoveryFake) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.prepareCalls
}

type waitingRunner struct {
	started chan struct{}
}

func (r waitingRunner) Run(ctx context.Context) error {
	close(r.started)
	<-ctx.Done()
	return nil
}

func TestGroupPreparesOnceForMultipleScanWorkers(t *testing.T) {
	scans := &scanRecoveryFake{}
	recovery := &groupRecoveryFake{}
	first := waitingRunner{started: make(chan struct{})}
	second := waitingRunner{started: make(chan struct{})}
	group, err := NewGroup(scans, workerClockFake{now: time.Unix(10, 0)}, recovery, first, second)
	if err != nil {
		t.Fatal(err)
	}
	if err := group.Prepare(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := group.Prepare(context.Background()); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- group.Run(ctx) }()
	for _, started := range []chan struct{}{first.started, second.started} {
		select {
		case <-started:
		case <-time.After(time.Second):
			t.Fatal("worker did not start")
		}
	}
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if scans.count() != 1 || recovery.count() != 1 {
		t.Fatalf("prepare calls: scans=%d processing=%d", scans.count(), recovery.count())
	}
}
