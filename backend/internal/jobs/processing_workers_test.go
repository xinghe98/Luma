package jobs

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

const testToolTimeout = time.Minute

func TestProbeWorkerCompletesAndNotifiesThumbnail(t *testing.T) {
	repo := &processingRepoFake{
		job:   domain.ProcessingJob{ID: "probe-job", MediaID: "media-1"},
		input: domain.MediaInput{ID: "media-1"},
	}
	thumbnailSignal := NewSignal()
	worker, err := NewProbeWorker(repo, proberFake{result: domain.ProbeResult{Title: "clip"}},
		workerIDsFake{}, workerClockFake{now: time.Unix(10, 0)}, NewSignal(), thumbnailSignal, testLogger(), 320, testToolTimeout)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.runOne(context.Background()); err != nil {
		t.Fatalf("runOne: %v", err)
	}
	if !repo.probeCompleted {
		t.Fatal("CompleteProbe was not called")
	}
	select {
	case <-thumbnailSignal.C():
	default:
		t.Fatal("thumbnail worker was not notified")
	}
}

func TestProbeWorkerToolFailureFailsWithoutFatalError(t *testing.T) {
	repo := &processingRepoFake{
		job:   domain.ProcessingJob{ID: "probe-job", MediaID: "media-1", Attempt: 1},
		input: domain.MediaInput{ID: "media-1"},
	}
	worker, err := NewProbeWorker(repo, proberFake{err: errors.New("ffprobe failed")}, workerIDsFake{},
		workerClockFake{}, NewSignal(), NewSignal(), testLogger(), 320, testToolTimeout)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.runOne(context.Background()); err != nil {
		t.Fatalf("tool failure became fatal: %v", err)
	}
	if !repo.failed {
		t.Fatal("Fail was not called")
	}
}

func TestProbeWorkerCompleteFailureFailsWithoutFatalError(t *testing.T) {
	repo := &processingRepoFake{
		job:         domain.ProcessingJob{ID: "probe-job", MediaID: "media-1", Attempt: 1},
		input:       domain.MediaInput{ID: "media-1"},
		completeErr: errors.New("db busy"),
	}
	worker, err := NewProbeWorker(repo, proberFake{result: domain.ProbeResult{Title: "clip"}}, workerIDsFake{},
		workerClockFake{}, NewSignal(), NewSignal(), testLogger(), 320, testToolTimeout)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.runOne(context.Background()); err != nil {
		t.Fatalf("complete failure became fatal: %v", err)
	}
	if !repo.failed {
		t.Fatal("Fail was not called after CompleteProbe error")
	}
}

func TestThumbnailWorkerCompletes(t *testing.T) {
	repo := &processingRepoFake{
		job:   domain.ProcessingJob{ID: "thumbnail-job", MediaID: "media-1"},
		input: domain.MediaInput{ID: "media-1", DurationMS: 1000},
	}
	worker, err := NewThumbnailWorker(repo, thumbnailerFake{result: domain.ThumbnailResult{StorageKey: "cover.jpg"}},
		workerIDsFake{}, workerClockFake{}, NewSignal(), testLogger(), testToolTimeout)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.runOne(context.Background()); err != nil {
		t.Fatalf("runOne: %v", err)
	}
	if !repo.thumbnailComplete {
		t.Fatal("CompleteThumbnail was not called")
	}
}

func TestThumbnailWorkerCanceledToolDoesNotFail(t *testing.T) {
	repo := &processingRepoFake{
		job:   domain.ProcessingJob{ID: "thumbnail-job", MediaID: "media-1"},
		input: domain.MediaInput{ID: "media-1"},
	}
	worker, err := NewThumbnailWorker(repo, thumbnailerFake{err: context.Canceled}, workerIDsFake{},
		workerClockFake{}, NewSignal(), testLogger(), testToolTimeout)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.runOne(context.Background()); err != nil {
		t.Fatalf("runOne: %v", err)
	}
	if repo.failed {
		t.Fatal("Fail was called for canceled external task")
	}
}

func TestThumbnailWorkerCompleteFailureFailsWithoutFatalError(t *testing.T) {
	repo := &processingRepoFake{
		job:         domain.ProcessingJob{ID: "thumbnail-job", MediaID: "media-1", Attempt: 1},
		input:       domain.MediaInput{ID: "media-1"},
		completeErr: errors.New("db busy"),
	}
	worker, err := NewThumbnailWorker(repo, thumbnailerFake{result: domain.ThumbnailResult{StorageKey: "cover.jpg"}},
		workerIDsFake{}, workerClockFake{}, NewSignal(), testLogger(), testToolTimeout)
	if err != nil {
		t.Fatal(err)
	}
	if err := worker.runOne(context.Background()); err != nil {
		t.Fatalf("complete failure became fatal: %v", err)
	}
	if !repo.failed {
		t.Fatal("Fail was not called after CompleteThumbnail error")
	}
}

func TestProcessingRecoveryPreparesAndEnqueuesOrphans(t *testing.T) {
	repo := &processingRepoFake{
		orphans:          []domain.MediaInput{{ID: "orphan-1"}, {ID: "orphan-2"}},
		thumbnailOrphans: []domain.MediaInput{{ID: "thumb-orphan"}},
	}
	probeSignal, thumbnailSignal := NewSignal(), NewSignal()
	recovery, err := NewProcessingRecovery(repo, workerIDsFake{}, workerClockFake{}, probeSignal, thumbnailSignal,
		testLogger(), 320, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if err := recovery.Prepare(context.Background()); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	if !repo.recovered {
		t.Fatal("Recover was not called")
	}
	if len(repo.enqueued) != 2 || repo.enqueued[0] != "orphan-1" || repo.enqueued[1] != "orphan-2" {
		t.Fatalf("enqueued media = %v", repo.enqueued)
	}
	if len(repo.enqueuedThumbs) != 1 || repo.enqueuedThumbs[0] != "thumb-orphan" {
		t.Fatalf("enqueued thumbnails = %v", repo.enqueuedThumbs)
	}
	select {
	case <-probeSignal.C():
	default:
		t.Fatal("probe worker was not notified")
	}
	select {
	case <-thumbnailSignal.C():
	default:
		t.Fatal("thumbnail worker was not notified")
	}
}
