package presence

import (
	"testing"
	"time"
)

func TestTrackerExpiresInactiveUsers(t *testing.T) {
	now := time.Date(2026, time.July, 23, 8, 0, 0, 0, time.UTC)
	tracker := New(func() time.Time { return now })

	tracker.Observe("member")
	if !tracker.IsOnline("member") {
		t.Fatal("member should be online immediately after activity")
	}

	now = now.Add(OnlineWindow + time.Second)
	if tracker.IsOnline("member") {
		t.Fatal("member should be offline after the activity window expires")
	}
}
