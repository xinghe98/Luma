// 作品库同步器测试验证成功扫描会在同步后立即建立并唤醒资料任务。
package jobs

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"
)

type recordingCatalogSync struct{ calls int }

func (s *recordingCatalogSync) Sync(context.Context) error {
	s.calls++
	return nil
}

type recordingMetadataQueue struct {
	scanID   string
	sourceID string
	calls    int
}

func (q *recordingMetadataQueue) QueueMetadataForScan(_ context.Context, scanID, sourceID string, _ time.Time) (int, error) {
	q.calls++
	q.scanID, q.sourceID = scanID, sourceID
	return 1, nil
}

func TestCatalogSynchronizerQueuesMetadataAfterSuccessfulSync(t *testing.T) {
	signal := NewCatalogSyncSignal()
	metadataSignal := NewSignal()
	service := &recordingCatalogSync{}
	queue := &recordingMetadataQueue{}
	synchronizer, err := NewCatalogSynchronizer(service, signal, queue, metadataSignal,
		slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	signal.Notify(CatalogSyncEvent{ScanID: "scan_1", SourceID: "source_1"})
	synchronizer.syncAndQueue(context.Background())
	if service.calls != 1 || queue.calls != 1 || queue.scanID != "scan_1" || queue.sourceID != "source_1" {
		t.Fatalf("同步及入队结果错误：sync=%d queue=%#v", service.calls, queue)
	}
	select {
	case <-metadataSignal.C():
	default:
		t.Fatal("资料 Worker 未被唤醒")
	}
}
