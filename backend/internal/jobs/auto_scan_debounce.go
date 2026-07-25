// Auto-scan debounce logic coalesces filesystem events for AutoScanScheduler.
// It shares the scheduler mutex and WaitGroup so shutdown can safely join callbacks.
package jobs

import (
	"context"
	"sync"
	"time"
)

// debounceTimer binds a cancellable timer to its one-time WaitGroup completion.
type debounceTimer struct {
	timer *time.Timer
	done  sync.Once
}

// scheduleSource starts a scan after the debounce window, retaining a trailing
// scan when a source remains busy.
func (s *AutoScanScheduler) scheduleSource(ctx context.Context, sourceID string) {
	if sourceID == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stopping || ctx.Err() != nil {
		return
	}
	if existing, ok := s.debounceTimers[sourceID]; ok && existing.timer.Stop() {
		existing.done.Do(s.timerWG.Done)
	}
	holder := &debounceTimer{}
	sourceIDCopy := sourceID
	s.timerWG.Add(1)
	holder.timer = time.AfterFunc(s.config.Debounce, func() {
		defer holder.done.Do(s.timerWG.Done)
		s.mu.Lock()
		if s.debounceTimers[sourceIDCopy] != holder {
			s.mu.Unlock()
			return
		}
		delete(s.debounceTimers, sourceIDCopy)
		s.mu.Unlock()
		if ctx.Err() != nil {
			return
		}
		started, err := s.starter.StartIfIdle(ctx, sourceIDCopy)
		if err != nil {
			s.logger.Error("防抖后自动扫描入队失败", "source_id", sourceIDCopy, "error", err)
			return
		}
		if !started {
			s.scheduleSource(ctx, sourceIDCopy)
		}
	})
	s.debounceTimers[sourceID] = holder
}

// stopDebounceTimers cancels callbacks that have not started; started callbacks
// observe Run's context and finish through timerWG.
func (s *AutoScanScheduler) stopDebounceTimers() {
	s.mu.Lock()
	s.stopping = true
	for id, holder := range s.debounceTimers {
		if holder.timer.Stop() {
			holder.done.Do(s.timerWG.Done)
		}
		delete(s.debounceTimers, id)
	}
	s.mu.Unlock()
}
