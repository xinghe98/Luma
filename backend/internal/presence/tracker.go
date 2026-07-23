// Package presence keeps short-lived, in-memory member activity state.
package presence

import (
	"strings"
	"sync"
	"time"
)

// OnlineWindow is deliberately short: a member is online only while the
// server has observed recent authenticated activity from that account.
const OnlineWindow = 2 * time.Minute

// Tracker is process-local. A service restart correctly resets all users to
// offline instead of presenting stale historical activity as a live session.
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
