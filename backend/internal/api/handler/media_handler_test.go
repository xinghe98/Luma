package handler

import (
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestMediaSummaryExposesTypeSpecificContentURL(t *testing.T) {
	video := presentMediaSummary(domain.Media{ID: "video", MediaType: domain.MediaTypeVideo})
	if video.StreamURL == nil || *video.StreamURL != "/api/v1/media/video/stream" {
		t.Fatalf("video stream URL = %#v", video.StreamURL)
	}
	if video.OriginalURL != nil {
		t.Fatalf("video original URL = %#v", video.OriginalURL)
	}
	image := presentMediaSummary(domain.Media{ID: "image", MediaType: domain.MediaTypeImage})
	if image.StreamURL != nil {
		t.Fatalf("image stream URL = %#v", image.StreamURL)
	}
	if image.OriginalURL == nil || *image.OriginalURL != "/api/v1/media/image/original" {
		t.Fatalf("image original URL = %#v", image.OriginalURL)
	}
}
