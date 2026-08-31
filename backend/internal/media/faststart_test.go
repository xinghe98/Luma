package media

import (
	"bytes"
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type recordingRemuxRunner struct {
	mu         sync.Mutex
	calls      int
	err        error
	output     []byte
	skipOutput bool
	release    chan struct{}
	started    chan struct{}
	finished   chan struct{}
}

func (r *recordingRemuxRunner) Run(ctx context.Context, _ string, args ...string) ([]byte, error) {
	r.mu.Lock()
	r.calls++
	err := r.err
	output := append([]byte(nil), r.output...)
	release := r.release
	r.mu.Unlock()
	if r.started != nil {
		r.started <- struct{}{}
	}
	if release != nil {
		select {
		case <-release:
		case <-ctx.Done():
			if r.finished != nil {
				r.finished <- struct{}{}
			}
			return nil, ctx.Err()
		}
	}
	if err != nil {
		if r.finished != nil {
			r.finished <- struct{}{}
		}
		return nil, err
	}
	if !r.skipOutput {
		if len(output) == 0 {
			output = concatBoxes(
				box("ftyp", []byte("isom")),
				box("moov", []byte("mvhd")),
				box("mdat", bytes.Repeat([]byte{9}, 16)),
			)
		}
		if len(args) > 0 {
			if err := os.WriteFile(args[len(args)-1], output, 0o600); err != nil {
				if r.finished != nil {
					r.finished <- struct{}{}
				}
				return nil, err
			}
		}
	}
	if r.finished != nil {
		r.finished <- struct{}{}
	}
	return nil, nil
}

func (r *recordingRemuxRunner) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.calls
}

func waitFaststartSignal(t *testing.T, signals <-chan struct{}) {
	t.Helper()
	select {
	case <-signals:
	case <-time.After(time.Second):
		t.Fatal("faststart worker did not reach expected state")
	}
}

func waitFaststartCondition(t *testing.T, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("faststart state did not settle")
}

func openFaststartSource(t *testing.T, root, filename string) domain.OpenedContent {
	t.Helper()
	path := filepath.Join(root, filename)
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	return domain.OpenedContent{Reader: file, Size: info.Size(), ModifiedAt: info.ModTime().UTC()}
}

func newFaststartSource(t *testing.T, root, filename string) domain.OpenedContent {
	t.Helper()
	path := filepath.Join(root, filename)
	payload := concatBoxes(
		box("ftyp", []byte("isom")),
		box("mdat", bytes.Repeat([]byte{1}, 64)),
		box("moov", []byte("mvhd")),
	)
	if err := os.WriteFile(path, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	return openFaststartSource(t, root, filename)
}

func startFaststartRunner(t *testing.T, cache *FaststartCache) (context.CancelFunc, <-chan error) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- cache.Run(ctx) }()
	return cancel, done
}

func TestFaststartCacheColdPrepareReturnsOriginalAndLaterHitsCache(t *testing.T) {
	root := t.TempDir()
	runner := &recordingRemuxRunner{
		release:  make(chan struct{}),
		started:  make(chan struct{}, 1),
		finished: make(chan struct{}, 1),
	}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	cancel, done := startFaststartRunner(t, cache)
	defer func() {
		cancel()
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}()
	location := domain.StreamLocation{
		ID: "media_cold", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "clip.mp4",
	}
	source := newFaststartSource(t, root, "clip.mp4")
	prepared, err := cache.Prepare(context.Background(), location, source)
	if err != nil {
		t.Fatal(err)
	}
	if prepared.Reader != source.Reader || prepared.Size != source.Size {
		t.Fatalf("cold prepare = %#v, want original snapshot", prepared)
	}
	waitFaststartSignal(t, runner.started)
	if runner.count() != 1 {
		t.Fatalf("ffmpeg calls while blocked = %d, want 1", runner.count())
	}
	if _, err := os.Stat(cache.cachePath(location.ID, source.Size, source.ModifiedAt)); !os.IsNotExist(err) {
		t.Fatalf("cache should not publish while runner is blocked: %v", err)
	}
	close(runner.release)
	waitFaststartSignal(t, runner.finished)
	waitFaststartCondition(t, func() bool {
		_, err := os.Stat(cache.cachePath(location.ID, source.Size, source.ModifiedAt))
		return err == nil
	})
	_ = source.Reader.Close()

	source2 := openFaststartSource(t, root, "clip.mp4")
	prepared2, err := cache.Prepare(context.Background(), location, source2)
	if err != nil {
		t.Fatal(err)
	}
	defer prepared2.Reader.Close()
	if prepared2.Reader == source2.Reader || runner.count() != 1 {
		t.Fatalf("second prepare did not hit cache: reader=%T calls=%d", prepared2.Reader, runner.count())
	}
	if !prepared2.ModifiedAt.Equal(source2.ModifiedAt) {
		t.Fatalf("cache modified time = %v, want source %v", prepared2.ModifiedAt, source2.ModifiedAt)
	}
}

func TestFaststartCacheSkipsAlreadyOptimizedAndNonMP4(t *testing.T) {
	root := t.TempDir()
	faststartPayload := concatBoxes(
		box("ftyp", []byte("isom")),
		box("moov", []byte("mvhd")),
		box("mdat", bytes.Repeat([]byte{1}, 16)),
	)
	sourcePath := filepath.Join(root, "ok.mp4")
	if err := os.WriteFile(sourcePath, faststartPayload, 0o600); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(sourcePath)
	file, _ := os.Open(sourcePath)
	defer file.Close()
	runner := &recordingRemuxRunner{}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := cache.Prepare(context.Background(), domain.StreamLocation{
		ID: "media_ok", Filename: "ok.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "ok.mp4",
	}, domain.OpenedContent{Reader: file, Size: info.Size(), ModifiedAt: info.ModTime().UTC()})
	if err != nil {
		t.Fatal(err)
	}
	if prepared.Reader != file || runner.count() != 0 {
		t.Fatalf("faststart 原片不应 remux: calls=%d", runner.count())
	}

	mkv, _ := os.Open(sourcePath)
	defer mkv.Close()
	prepared, err = cache.Prepare(context.Background(), domain.StreamLocation{
		ID: "media_mkv", Filename: "clip.mkv", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "ok.mp4",
	}, domain.OpenedContent{Reader: mkv, Size: info.Size(), ModifiedAt: time.Now()})
	if err != nil || prepared.Reader != mkv || runner.count() != 0 {
		t.Fatalf("mkv 不应 remux: err=%v calls=%d", err, runner.count())
	}
}

func TestFaststartCacheCoalescesSameKeyAndUsesSingleWorker(t *testing.T) {
	root := t.TempDir()
	runner := &recordingRemuxRunner{
		release:  make(chan struct{}),
		started:  make(chan struct{}, 2),
		finished: make(chan struct{}, 2),
	}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	cancel, done := startFaststartRunner(t, cache)
	defer func() {
		cancel()
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}()
	location := domain.StreamLocation{
		ID: "media_same", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "clip.mp4",
	}
	const callers = 8
	template := newFaststartSource(t, root, "clip.mp4")
	templateSize, templateModified := template.Size, template.ModifiedAt
	_ = template.Reader.Close()
	readers := make([]domain.StreamReader, callers)
	errs := make(chan error, callers)
	var group sync.WaitGroup
	group.Add(callers)
	for i := range callers {
		go func(i int) {
			defer group.Done()
			file, err := os.Open(filepath.Join(root, "clip.mp4"))
			if err != nil {
				errs <- err
				return
			}
			prepared, err := cache.Prepare(context.Background(), location, domain.OpenedContent{
				Reader: file, Size: templateSize, ModifiedAt: templateModified,
			})
			if err != nil {
				_ = file.Close()
				errs <- err
				return
			}
			readers[i] = prepared.Reader
		}(i)
	}
	group.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	close(runner.release)
	waitFaststartSignal(t, runner.finished)
	for _, reader := range readers {
		if reader != nil {
			_ = reader.Close()
		}
	}
}

func TestFaststartCacheDifferentKeysRemainSingleWorker(t *testing.T) {
	root := t.TempDir()
	runner := &recordingRemuxRunner{
		release:  make(chan struct{}),
		started:  make(chan struct{}, 2),
		finished: make(chan struct{}, 2),
	}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	cancel, done := startFaststartRunner(t, cache)
	defer func() {
		cancel()
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}()
	source1 := newFaststartSource(t, root, "first.mp4")
	first, err := cache.Prepare(context.Background(), domain.StreamLocation{
		ID: "media_first", Filename: "first.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "first.mp4",
	}, source1)
	if err != nil {
		t.Fatal(err)
	}
	defer first.Reader.Close()
	waitFaststartSignal(t, runner.started)
	source2 := newFaststartSource(t, root, "second.mp4")
	second, err := cache.Prepare(context.Background(), domain.StreamLocation{
		ID: "media_second", Filename: "second.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "second.mp4",
	}, source2)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Reader.Close()
	select {
	case <-runner.started:
		t.Fatal("second remux started before first completed")
	case <-time.After(20 * time.Millisecond):
	}
	if runner.count() != 1 {
		t.Fatalf("blocked worker calls = %d, want 1", runner.count())
	}
	close(runner.release)
	waitFaststartSignal(t, runner.finished)
	waitFaststartSignal(t, runner.started)
	waitFaststartSignal(t, runner.finished)
	if runner.count() != 2 {
		t.Fatalf("different key ffmpeg calls = %d, want 2", runner.count())
	}
}

func TestFaststartCacheQueueFullFallsBackImmediately(t *testing.T) {
	root := t.TempDir()
	runner := &recordingRemuxRunner{}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	readers := make([]domain.StreamReader, 0, faststartQueueCapacity+1)
	for i := range faststartQueueCapacity + 1 {
		source := newFaststartSource(t, root, "clip.mp4")
		prepared, err := cache.Prepare(context.Background(), domain.StreamLocation{
			ID: "media_queue_" + string(rune('a'+i)), Filename: "clip.mp4",
			MediaType: domain.MediaTypeVideo, RootPath: root, RelativePath: "clip.mp4",
		}, source)
		if err != nil {
			t.Fatal(err)
		}
		if prepared.Reader != source.Reader {
			t.Fatal("queue miss should return original reader")
		}
		readers = append(readers, prepared.Reader)
	}
	for _, reader := range readers {
		_ = reader.Close()
	}
	if len(cache.queue) != faststartQueueCapacity {
		t.Fatalf("queue length = %d, want %d", len(cache.queue), faststartQueueCapacity)
	}
	cache.mu.Lock()
	pending := len(cache.pending)
	cache.mu.Unlock()
	if pending != faststartQueueCapacity {
		t.Fatalf("pending keys = %d, want %d", pending, faststartQueueCapacity)
	}
}

func TestFaststartCacheFailureCooldownAndInvalidOutputLeaveNoCache(t *testing.T) {
	tests := []struct {
		name       string
		skipOutput bool
		err        error
	}{
		{name: "失败", err: os.ErrPermission},
		{name: "无效输出", skipOutput: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()
			runner := &recordingRemuxRunner{
				skipOutput: test.skipOutput, err: test.err,
				started: make(chan struct{}, 1), finished: make(chan struct{}, 1),
			}
			cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
			if err != nil {
				t.Fatal(err)
			}
			cancel, done := startFaststartRunner(t, cache)
			defer func() {
				cancel()
				if err := <-done; err != nil {
					t.Fatal(err)
				}
			}()
			location := domain.StreamLocation{
				ID: "media_failure_" + test.name, Filename: "clip.mp4",
				MediaType: domain.MediaTypeVideo, RootPath: root, RelativePath: "clip.mp4",
			}
			source := newFaststartSource(t, root, "clip.mp4")
			prepared, err := cache.Prepare(context.Background(), location, source)
			if err != nil {
				t.Fatal(err)
			}
			waitFaststartSignal(t, runner.finished)
			waitFaststartCondition(t, func() bool {
				cache.mu.Lock()
				defer cache.mu.Unlock()
				return len(cache.pending) == 0 && len(cache.failed) == 1
			})
			_ = prepared.Reader.Close()
			source2 := openFaststartSource(t, root, "clip.mp4")
			prepared2, err := cache.Prepare(context.Background(), location, source2)
			if err != nil {
				t.Fatal(err)
			}
			defer prepared2.Reader.Close()
			if runner.count() != 1 {
				t.Fatalf("cooldown ffmpeg calls = %d, want 1", runner.count())
			}
			if _, err := os.Stat(cache.cachePath(location.ID, source2.Size, source2.ModifiedAt)); !os.IsNotExist(err) {
				t.Fatalf("failed remux left final cache: %v", err)
			}
		})
	}
}

func TestFaststartCacheCancellationDropsQueuedWorkAndStopsRunner(t *testing.T) {
	root := t.TempDir()
	runner := &recordingRemuxRunner{
		release: make(chan struct{}), started: make(chan struct{}, 1), finished: make(chan struct{}, 1),
	}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- cache.Run(ctx) }()
	location := domain.StreamLocation{
		ID: "media_cancel", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "clip.mp4",
	}
	source := newFaststartSource(t, root, "clip.mp4")
	prepared, err := cache.Prepare(context.Background(), location, source)
	if err != nil {
		t.Fatal(err)
	}
	waitFaststartSignal(t, runner.started)
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	_ = prepared.Reader.Close()
	cache.mu.Lock()
	pending := len(cache.pending)
	cache.mu.Unlock()
	if pending != 0 {
		t.Fatalf("pending keys after cancellation = %d", pending)
	}
	if _, err := os.Stat(cache.cachePath(location.ID, source.Size, source.ModifiedAt)); !os.IsNotExist(err) {
		t.Fatalf("cancelled remux left final cache: %v", err)
	}
}

func TestFaststartCacheRechecksSizeAndMtimeBeforePublishing(t *testing.T) {
	root := t.TempDir()
	runner := &recordingRemuxRunner{finished: make(chan struct{}, 1)}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	location := domain.StreamLocation{
		ID: "media_changed", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "clip.mp4",
	}
	source := newFaststartSource(t, root, "clip.mp4")
	oldSize, oldModified := source.Size, source.ModifiedAt
	if _, err := cache.Prepare(context.Background(), location, source); err != nil {
		t.Fatal(err)
	}
	_ = source.Reader.Close()
	fileToChange, err := os.OpenFile(filepath.Join(root, "clip.mp4"), os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fileToChange.Write([]byte{7}); err != nil {
		_ = fileToChange.Close()
		t.Fatal(err)
	}
	if err := fileToChange.Close(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- cache.Run(ctx) }()
	waitFaststartCondition(t, func() bool {
		cache.mu.Lock()
		defer cache.mu.Unlock()
		return len(cache.pending) == 0 && len(cache.failed) == 1
	})
	if runner.count() != 0 {
		t.Fatalf("changed source should fail before ffmpeg, calls=%d", runner.count())
	}
	if _, err := os.Stat(cache.cachePath(location.ID, oldSize, oldModified)); !os.IsNotExist(err) {
		t.Fatalf("stale identity cache was published: %v", err)
	}
	source2 := openFaststartSource(t, root, "clip.mp4")
	prepared, err := cache.Prepare(context.Background(), location, source2)
	if err != nil {
		t.Fatal(err)
	}
	_ = prepared.Reader.Close()
	waitFaststartSignal(t, runner.finished)
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestFaststartCacheAtomicPublishFailureCleansTemporaryFile(t *testing.T) {
	root := t.TempDir()
	runner := &recordingRemuxRunner{}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	source := newFaststartSource(t, root, "clip.mp4")
	location := domain.StreamLocation{
		ID: "media_atomic", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "clip.mp4",
	}
	finalPath := filepath.Join(cache.root, "missing", "media_atomic.mp4")
	if err := cache.remux(context.Background(), location, source.Size, source.ModifiedAt, finalPath); err == nil {
		t.Fatal("atomic publish failure should be returned")
	}
	entries, err := os.ReadDir(cache.root)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), ".") && strings.HasSuffix(entry.Name(), ".mp4") {
			t.Fatalf("atomic failure left final cache %q", entry.Name())
		}
	}
	_ = source.Reader.Close()
}

func TestFaststartCacheLRUEvictsOldFilesAndKeepsOversizedNewest(t *testing.T) {
	cache, err := newFaststartCacheWithOptions("ffmpeg", t.TempDir(), 10, slog.Default(), &recordingRemuxRunner{})
	if err != nil {
		t.Fatal(err)
	}
	oldPath := filepath.Join(cache.root, "old-6-1.mp4")
	newPath := filepath.Join(cache.root, "new-6-2.mp4")
	if err := os.WriteFile(oldPath, bytes.Repeat([]byte{1}, 6), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(newPath, bytes.Repeat([]byte{2}, 6), 0o600); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	_ = os.Chtimes(oldPath, now.Add(-time.Hour), now.Add(-time.Hour))
	_ = os.Chtimes(newPath, now, now)
	cache.cleanupLRU(newPath)
	if _, err := os.Stat(oldPath); !os.IsNotExist(err) {
		t.Fatalf("old LRU file still exists: %v", err)
	}
	if _, err := os.Stat(newPath); err != nil {
		t.Fatalf("new LRU file missing: %v", err)
	}

	cache.maxBytes = 4
	oversized := filepath.Join(cache.root, "newest-8-3.mp4")
	if err := os.WriteFile(oldPath, bytes.Repeat([]byte{3}, 2), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(oversized, bytes.Repeat([]byte{4}, 8), 0o600); err != nil {
		t.Fatal(err)
	}
	cache.cleanupLRU(oversized)
	if _, err := os.Stat(oldPath); !os.IsNotExist(err) {
		t.Fatalf("oversized cache cleanup kept old file: %v", err)
	}
	if _, err := os.Stat(oversized); err != nil {
		t.Fatalf("oversized newest cache was removed: %v", err)
	}
}

func TestFaststartCacheUsesMillisecondKeyAndStableSourceModifiedAtAfterTouch(t *testing.T) {
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), &recordingRemuxRunner{})
	if err != nil {
		t.Fatal(err)
	}
	first := time.Unix(100, int64(123*time.Millisecond)).UTC()
	second := time.Unix(100, int64(124*time.Millisecond)).UTC()
	firstPath := cache.cachePath("media_milli", 10, first)
	secondPath := cache.cachePath("media_milli", 10, second)
	if firstPath == secondPath || !strings.Contains(filepath.Base(firstPath), "-100123.mp4") {
		t.Fatalf("millisecond cache paths = %q, %q", firstPath, secondPath)
	}

	root := t.TempDir()
	sourcePath := filepath.Join(root, "clip.mp4")
	payload := concatBoxes(
		box("ftyp", []byte("isom")),
		box("mdat", []byte{1, 2, 3}),
		box("moov", []byte("mvhd")),
	)
	if err := os.WriteFile(sourcePath, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	sourceModified := time.Unix(1700000000, int64(123*time.Millisecond)).UTC()
	if err := os.Chtimes(sourcePath, sourceModified, sourceModified); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(sourcePath)
	cachePath := cache.cachePath("media_touch", info.Size(), sourceModified)
	if err := os.WriteFile(cachePath, []byte("cached"), 0o600); err != nil {
		t.Fatal(err)
	}
	oldCacheTime := time.Now().Add(-time.Hour)
	if err := os.Chtimes(cachePath, oldCacheTime, oldCacheTime); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := cache.Prepare(context.Background(), domain.StreamLocation{
		ID: "media_touch", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "clip.mp4",
	}, domain.OpenedContent{Reader: file, Size: info.Size(), ModifiedAt: sourceModified})
	if err != nil {
		t.Fatal(err)
	}
	defer prepared.Reader.Close()
	if !prepared.ModifiedAt.Equal(sourceModified) {
		t.Fatalf("cached source modified time = %v, want %v", prepared.ModifiedAt, sourceModified)
	}
	cacheInfo, err := os.Stat(cachePath)
	if err != nil {
		t.Fatal(err)
	}
	if !cacheInfo.ModTime().After(oldCacheTime) {
		t.Fatalf("cache mtime was not touched: %v <= %v", cacheInfo.ModTime(), oldCacheTime)
	}
}
