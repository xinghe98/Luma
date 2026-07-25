package presence

import (
	"strings"
	"sync"
	"time"
)

const OnlineWindow = 2 * time.Minute

type Tracker struct {
	now func() time.Time

	mu       sync.RWMutex
	lastSeen map[string]time.Time
}

func New(now func() time.Time) *Tracker {
	if now == nil {
		now = time.Now
	}
	return &Tracker{now: now, lastSeen: map[string]time.Time{}}
}

func (t *Tracker) Observe(userID string) {
	if t == nil || strings.TrimSpace(userID) == "" {
		return
	}
	t.mu.Lock()
	t.lastSeen[userID] = t.now().UTC()
	t.mu.Unlock()
}

func (t *Tracker) IsOnline(userID string) bool {
	if t == nil || strings.TrimSpace(userID) == "" {
		return false
	}
	t.mu.RLock()
	lastSeen, exists := t.lastSeen[userID]
	t.mu.RUnlock()
	if !exists {
		return false
	}
	return t.now().UTC().Sub(lastSeen) <= OnlineWindow
}
