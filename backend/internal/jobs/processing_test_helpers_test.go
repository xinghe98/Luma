package jobs

import (
	"context"
	"io"
	"log/slog"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type processingRepoFake struct {
	// job 是领取操作返回的处理任务。
	job domain.ProcessingJob
	// input 是媒体查询返回的输入信息。
	input domain.MediaInput
	// orphans 是探测任务使用的孤立媒体列表。
	orphans []domain.MediaInput
	// thumbnailOrphans 是缩略图任务使用的孤立媒体列表。
	thumbnailOrphans []domain.MediaInput
	// completeErr 是完成任务时返回的错误。
	completeErr error
	// probeCompleted 记录探测任务是否完成。
	probeCompleted bool
	// thumbnailComplete 记录缩略图任务是否完成。
	thumbnailComplete bool
	// failed 记录任务是否标记失败。
	failed bool
	// recovered 记录恢复操作是否执行。
	recovered bool
	// enqueued 记录已加入探测队列的媒体 ID。
	enqueued []string
	// enqueuedThumbs 记录已加入缩略图队列的媒体 ID。
	enqueuedThumbs []string
}

func (f *processingRepoFake) EnqueueProbe(_ context.Context, _ string, mediaID string, _ time.Time) error {
	f.enqueued = append(f.enqueued, mediaID)
	return nil
}

func (f *processingRepoFake) EnqueueThumbnail(_ context.Context, _ string, mediaID, _, _ string, _ time.Time) error {
	f.enqueuedThumbs = append(f.enqueuedThumbs, mediaID)
	return nil
}

func (f *processingRepoFake) Claim(context.Context, string, string, time.Time) (domain.ProcessingJob, error) {
	return f.job, nil
}

func (f *processingRepoFake) GetMedia(context.Context, string) (domain.MediaInput, error) {
	return f.input, nil
}

func (f *processingRepoFake) CompleteProbe(context.Context, domain.ProcessingJob, domain.MediaInput,
	domain.ProbeResult, string, string, string, time.Time) (bool, error) {
	if f.completeErr != nil {
		return false, f.completeErr
	}
	f.probeCompleted = true
	return true, nil
}

func (f *processingRepoFake) CompleteThumbnail(context.Context, domain.ProcessingJob, domain.MediaInput,
	domain.ThumbnailResult, time.Time) (bool, error) {
	if f.completeErr != nil {
		return false, f.completeErr
	}
	f.thumbnailComplete = true
	return true, nil
}

func (f *processingRepoFake) Fail(context.Context, domain.ProcessingJob, string, string, time.Time) (bool, error) {
	f.failed = true
	return true, nil
}

func (f *processingRepoFake) Recover(context.Context, time.Time) error {
	f.recovered = true
	return nil
}

func (f *processingRepoFake) ReclaimExpired(context.Context, time.Time, time.Duration) error {
	return nil
}

func (f *processingRepoFake) ListOrphans(_ context.Context, jobType string, _ int) ([]domain.MediaInput, error) {
	if jobType == domain.JobTypeThumbnail {
		return f.thumbnailOrphans, nil
	}
	return f.orphans, nil
}

type proberFake struct {
	// result 是探测操作返回的结果。
	result domain.ProbeResult
	// err 是探测操作返回的错误。
	err error
}

func (f proberFake) Probe(context.Context, domain.MediaInput) (domain.ProbeResult, error) {
	return f.result, f.err
}

type thumbnailerFake struct {
	// result 是缩略图生成操作返回的结果。
	result domain.ThumbnailResult
	// err 是缩略图生成操作返回的错误。
	err error
}

func (f thumbnailerFake) Generate(context.Context, domain.MediaInput, int64) (domain.ThumbnailResult, error) {
	return f.result, f.err
}

type workerIDsFake struct{}

func (workerIDsFake) New(prefix string) (string, error) { return prefix + "-id", nil }

type workerClockFake struct {
	// now 是时钟返回的固定时间。
	now time.Time
}

func (f workerClockFake) Now() time.Time { return f.now }

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}
