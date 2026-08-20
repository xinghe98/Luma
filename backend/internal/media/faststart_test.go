package media

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type recordingRemuxRunner struct {
	calls  int
	err    error
	output []byte
}

func (r *recordingRemuxRunner) Run(_ context.Context, _ string, args ...string) ([]byte, error) {
	r.calls++
	if r.err != nil {
		return nil, r.err
	}
	if len(args) == 0 {
		return nil, nil
	}
	output := args[len(args)-1]
	payload := r.output
	if len(payload) == 0 {
		payload = concatBoxes(
			box("ftyp", []byte("isom")),
			box("moov", []byte("mvhd")),
			box("mdat", bytes.Repeat([]byte{9}, 16)),
		)
	}
	return nil, os.WriteFile(output, payload, 0o600)
}

func TestFaststartCacheRemuxesMoovAtEnd(t *testing.T) {
	root := t.TempDir()
	sourceName := "clip.mp4"
	payload := concatBoxes(
		box("ftyp", []byte("isom")),
		box("mdat", bytes.Repeat([]byte{1}, 64)),
		box("moov", []byte("mvhd")),
	)
	sourcePath := filepath.Join(root, sourceName)
	if err := os.WriteFile(sourcePath, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	runner := &recordingRemuxRunner{}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	location := domain.StreamLocation{
		ID: "media_1", Filename: sourceName, MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: sourceName,
	}
	prepared, err := cache.Prepare(context.Background(), location, domain.OpenedContent{
		Reader: file, Size: info.Size(), ModifiedAt: info.ModTime().UTC(),
	})
	if err != nil {
		t.Fatal(err)
	}
	defer prepared.Reader.Close()
	if runner.calls != 1 {
		t.Fatalf("ffmpeg calls = %d, want 1", runner.calls)
	}
	if prepared.Size == info.Size() && prepared.Reader == file {
		t.Fatal("应返回缓存副本而不是原文件")
	}
	needed, err := NeedsFastStart(prepared.Reader)
	if err != nil || needed {
		t.Fatalf("缓存副本仍需 faststart: needed=%v err=%v", needed, err)
	}

	file2, err := os.Open(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	prepared2, err := cache.Prepare(context.Background(), location, domain.OpenedContent{
		Reader: file2, Size: info.Size(), ModifiedAt: info.ModTime().UTC(),
	})
	if err != nil {
		t.Fatal(err)
	}
	defer prepared2.Reader.Close()
	if runner.calls != 1 {
		t.Fatalf("第二次应命中缓存, ffmpeg calls = %d", runner.calls)
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
	if prepared.Reader != file || runner.calls != 0 {
		t.Fatalf("faststart 原片不应 remux: calls=%d", runner.calls)
	}

	mkv, _ := os.Open(sourcePath)
	defer mkv.Close()
	prepared, err = cache.Prepare(context.Background(), domain.StreamLocation{
		ID: "media_mkv", Filename: "clip.mkv", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "ok.mp4",
	}, domain.OpenedContent{Reader: mkv, Size: info.Size(), ModifiedAt: time.Now()})
	if err != nil || prepared.Reader != mkv || runner.calls != 0 {
		t.Fatalf("mkv 不应 remux: err=%v calls=%d", err, runner.calls)
	}
}

func TestFaststartCacheFallsBackWhenRemuxFails(t *testing.T) {
	root := t.TempDir()
	payload := concatBoxes(
		box("ftyp", []byte("isom")),
		box("mdat", bytes.Repeat([]byte{1}, 32)),
		box("moov", []byte("mvhd")),
	)
	sourcePath := filepath.Join(root, "clip.mp4")
	if err := os.WriteFile(sourcePath, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(sourcePath)
	file, _ := os.Open(sourcePath)
	defer file.Close()
	runner := &recordingRemuxRunner{err: os.ErrPermission}
	cache, err := newFaststartCache("ffmpeg", t.TempDir(), runner)
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := cache.Prepare(context.Background(), domain.StreamLocation{
		ID: "media_fail", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		RootPath: root, RelativePath: "clip.mp4",
	}, domain.OpenedContent{Reader: file, Size: info.Size(), ModifiedAt: info.ModTime().UTC()})
	if err != nil {
		t.Fatal(err)
	}
	if prepared.Reader != file {
		t.Fatal("remux 失败时应回退原文件")
	}
}
