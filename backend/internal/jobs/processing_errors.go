package jobs

import (
	"context"
	"errors"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func isBenignJobError(err error) bool {
	return err == nil ||
		errors.Is(err, context.Canceled) ||
		errors.Is(err, domain.ErrNoPendingJob) ||
		errors.Is(err, domain.ErrMediaNotFound)
}
