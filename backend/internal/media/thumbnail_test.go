package media

import (
	"reflect"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

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
