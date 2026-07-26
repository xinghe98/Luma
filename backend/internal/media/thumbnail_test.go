package media

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type thumbnailCommandRunner struct{ call uint8 }

// Run 生成颜色随调用变化的有效 JPEG，模拟外部缩略图工具。
func (r *thumbnailCommandRunner) Run(_ context.Context, _ string, args ...string) ([]byte, error) {
	r.call++
	file, err := os.Create(args[len(args)-1])
	if err != nil {
		return nil, err
	}
	generated := image.NewRGBA(image.Rect(0, 0, 2, 2))
	for y := 0; y < 2; y++ {
		for x := 0; x < 2; x++ {
			generated.Set(x, y, color.RGBA{R: r.call, A: 255})
		}
	}
	encodeErr := jpeg.Encode(file, generated, nil)
	closeErr := file.Close()
	if encodeErr != nil {
		return nil, encodeErr
	}
	return nil, closeErr
}

func TestThumbnailArgsVideo(t *testing.T) {
	got := thumbnailArgs(domain.MediaTypeVideo, "input.mp4", "cover.jpg", 640, 100000)
	want := []string{
		"-v", "error", "-nostdin", "-y",
		"-ss", "10.000", "-i", "input.mp4", "-frames:v", "1",
		"-vf", "scale=640:-2,format=yuvj420p", "-q:v", "3", "-c:v", "mjpeg",
		"-f", "image2", "cover.jpg",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("thumbnailArgs(video) = %#v, want %#v", got, want)
	}
}

func TestThumbnailArgsImage(t *testing.T) {
	got := thumbnailArgs(domain.MediaTypeImage, "input.png", "cover.jpg", 320, 0)
	want := []string{
		"-v", "error", "-nostdin", "-y", "-i", "input.png",
		"-frames:v", "1", "-vf", "scale=320:-2,format=yuvj420p", "-q:v", "3",
		"-c:v", "mjpeg", "-f", "image2", "cover.jpg",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("thumbnailArgs(image) = %#v, want %#v", got, want)
	}
}

func TestCardThumbnailArgsUseCenteredCoverCrop(t *testing.T) {
	got := cardThumbnailArgs(domain.MediaTypeImage, "portrait.jpg", "card.jpg", 640, 400, 0)
	wantFilter := "scale=640:400:force_original_aspect_ratio=increase,crop=640:400,format=yuvj420p"
	found := false
	for _, value := range got {
		if value == wantFilter {
			found = true
		}
	}
	if !found {
		t.Fatalf("card args = %#v, missing %q", got, wantFilter)
	}
	if cardThumbnailHeight(640) != 400 {
		t.Fatalf("height=%d", cardThumbnailHeight(640))
	}
}

func TestThumbnailStorageKey(t *testing.T) {
	if got := ThumbnailStorageKey("media-1", 640); got != "thumbnails/media-1/cover-640-v1.jpg" {
		t.Fatalf("ThumbnailStorageKey = %q", got)
	}
}

func TestCardThumbnailStorageKey(t *testing.T) {
	if got := CardThumbnailStorageKey("media-1", 640, 400); got != "thumbnails/media-1/cover-card-640x400-v1.jpg" {
		t.Fatalf("CardThumbnailStorageKey = %q", got)
	}
}

// TestThumbnailGenerationPublishesImmutableStorageKeys 验证后续任务不会覆盖先前发布的缩略图文件。
func TestThumbnailGenerationPublishesImmutableStorageKeys(t *testing.T) {
	mediaRoot := t.TempDir()
	if err := os.WriteFile(filepath.Join(mediaRoot, "image.jpg"), []byte("source"), 0o600); err != nil {
		t.Fatal(err)
	}
	thumbnailRoot := t.TempDir()
	thumbnailer, err := newFFmpegThumbnailer("ffmpeg", thumbnailRoot, 16, &thumbnailCommandRunner{})
	if err != nil {
		t.Fatal(err)
	}
	input := domain.MediaInput{ID: "media-1", RootPath: mediaRoot, RelativePath: "image.jpg", MediaType: domain.MediaTypeImage}
	first, err := thumbnailer.Generate(context.Background(), input, 0)
	if err != nil {
		t.Fatal(err)
	}
	firstPath := filepath.Join(thumbnailRoot, filepath.FromSlash(strings.TrimPrefix(first.StorageKey, "thumbnails/")))
	firstData, err := os.ReadFile(firstPath)
	if err != nil {
		t.Fatal(err)
	}
	second, err := thumbnailer.Generate(context.Background(), input, 0)
	if err != nil {
		t.Fatal(err)
	}
	if first.StorageKey == second.StorageKey {
		t.Fatalf("storage keys should differ: %q", first.StorageKey)
	}
	currentFirstData, err := os.ReadFile(firstPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(currentFirstData, firstData) {
		t.Fatal("later generation overwrote the previously published thumbnail")
	}
}

func TestSeekSecondsUnknownDuration(t *testing.T) {
	if got := seekSeconds(0); got != 0 {
		t.Fatalf("seekSeconds(0) = %v, want 0", got)
	}
}

func TestThumbnailSeekCandidatesFallback(t *testing.T) {
	got := thumbnailSeekCandidates(domain.MediaTypeVideo, 2_898_175)
	want := []float64{120, 1, 0}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("thumbnailSeekCandidates() = %#v, want %#v", got, want)
	}
	if got := thumbnailSeekCandidates(domain.MediaTypeImage, 0); !reflect.DeepEqual(got, []float64{0}) {
		t.Fatalf("image candidates = %#v", got)
	}
}
