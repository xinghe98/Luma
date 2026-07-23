package handler

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type recordingMediaUseCase struct {
	request domain.MediaListRequest
	count   int
}

func (u *recordingMediaUseCase) Count(_ context.Context, request domain.MediaListRequest, _ string) (int, error) {
	u.request = request
	return u.count, nil
}

func (u *recordingMediaUseCase) List(_ context.Context, request domain.MediaListRequest, _ string) (domain.MediaPage, error) {
	u.request = request
	return domain.MediaPage{}, nil
}

func (*recordingMediaUseCase) Get(context.Context, string, string) (domain.Media, error) {
	return domain.Media{}, nil
}

func (*recordingMediaUseCase) Thumbnail(context.Context, string, string, string, string) (domain.ThumbnailContent, error) {
	return domain.ThumbnailContent{}, nil
}

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

func TestMediaSummaryIncludesCreatedAt(t *testing.T) {
	created := time.Date(2024, 6, 1, 12, 0, 0, 0, time.UTC)
	summary := presentMediaSummary(domain.Media{
		ID: "media-1", MediaType: domain.MediaTypeVideo, DiscoveredAt: created,
	})
	if summary.CreatedAt != created.Format(time.RFC3339Nano) {
		t.Fatalf("created_at = %q", summary.CreatedAt)
	}
}

func TestMediaSummaryIncludesCardThumbnailWhenReady(t *testing.T) {
	summary := presentMediaSummary(domain.Media{ID: "media-1", HasThumbnail: true, HasCardThumbnail: true})
	if summary.ThumbnailURL == "" || summary.CardThumbnailURL != "/api/v1/media/media-1/thumbnail?variant=card" {
		t.Fatalf("summary=%#v", summary)
	}
}

func TestMediaListPassesWatchStatus(t *testing.T) {
	gin.SetMode(gin.TestMode)
	useCase := &recordingMediaUseCase{}
	handler, err := NewMediaHandler(useCase)
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c.Set("user_id", "user_local")
	})
	engine.GET("/media", handler.List)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/media?watch_status=watching", nil))
	if recorder.Code != http.StatusOK || useCase.request.WatchStatus != domain.WatchStatusWatching {
		t.Fatalf("status=%d request=%#v", recorder.Code, useCase.request)
	}
}

func TestMediaCountPassesFiltersWithoutPagination(t *testing.T) {
	gin.SetMode(gin.TestMode)
	useCase := &recordingMediaUseCase{count: 7}
	handler, err := NewMediaHandler(useCase)
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.Use(func(c *gin.Context) { c.Set("user_id", "user_local") })
	engine.GET("/media/count", handler.Count)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/media/count?type=image&favorite=true", nil))
	if recorder.Code != http.StatusOK || useCase.request.MediaType != domain.MediaTypeImage || useCase.request.Favorite == nil || !*useCase.request.Favorite || recorder.Body.String() != "{\"count\":7}" {
		t.Fatalf("status=%d request=%#v body=%s", recorder.Code, useCase.request, recorder.Body.String())
	}
}
