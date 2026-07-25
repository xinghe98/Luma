package jobs

import (
	"context"
	"sync"
	"time"
)

type debounceTimer struct {
	timer *time.Timer
	done  sync.Once
}

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
