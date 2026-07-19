package jobs

import (
	"context"
	"errors"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func runProcessingLoop(ctx context.Context, signal *Signal, runOne func() error) error {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		err := runOne()
		if err == nil {
			continue
		}
		if !errors.Is(err, domain.ErrNoPendingJob) {
			if errors.Is(err, context.Canceled) {
				return nil
			}
			return err
		}
		select {
		case <-ctx.Done():
			return nil
		case <-signal.C():
		case <-ticker.C:
		}
	}
}
