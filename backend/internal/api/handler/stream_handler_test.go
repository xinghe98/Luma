package handler

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type closeTrackingStream struct {
	// Reader 提供测试流的读取和定位能力。
	*bytes.Reader
	// closed 记录测试流是否已关闭。
	closed bool
}

func (r *closeTrackingStream) Close() error { r.closed = true; return nil }

type closeTrackingStreamUseCase struct {
	// reader 是业务用例返回的测试流。
	reader *closeTrackingStream
	// location 是测试定位信息。
	location domain.StreamLocation
	// transcodeErr 是转码测试错误。
	transcodeErr error
}

func (u closeTrackingStreamUseCase) GetLocation(context.Context, string, string) (domain.StreamLocation, error) {
	if u.location.ID != "" {
		return u.location, nil
	}
	return domain.StreamLocation{ID: "media", MediaType: domain.MediaTypeVideo, SourceType: domain.SourceTypeLocal, AudioCodec: "aac"}, nil
}

func (u closeTrackingStreamUseCase) OpenTranscodeStream(context.Context, string, string) (io.ReadCloser, string, error) {
	if u.transcodeErr != nil {
		return nil, "", u.transcodeErr
	}
	return io.NopCloser(bytes.NewReader([]byte("transcoded"))), "video/mp4", nil
}

func (u closeTrackingStreamUseCase) Open(context.Context, string, string) (domain.StreamContent, error) {
	return domain.StreamContent{
		Name: "clip.mp4", MIMEType: "video/mp4", ETag: `W/"5-1"`, Size: 5,
		ModifiedAt: time.Unix(1, 0).UTC(), Reader: u.reader,
	}, nil
}

func (u closeTrackingStreamUseCase) OpenOriginal(context.Context, string, string) (domain.StreamContent, error) {
	return domain.StreamContent{
		Name: "photo.jpg", MIMEType: "image/jpeg", ETag: `W/"5-1"`, Size: 5,
		ModifiedAt: time.Unix(1, 0).UTC(), Reader: u.reader,
	}, nil
}

func TestStreamHandlerClosesContent(t *testing.T) {
	gin.SetMode(gin.TestMode)
	reader := &closeTrackingStream{Reader: bytes.NewReader([]byte("video"))}
	handler, err := NewStreamHandler(closeTrackingStreamUseCase{reader: reader})
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.GET("/media/:id/stream", handler.Stream)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/media/media/stream", nil))
	if recorder.Code != http.StatusOK || !reader.closed {
		t.Fatalf("status=%d closed=%v", recorder.Code, reader.closed)
	}
}

func TestOriginalHandlerClosesContentAndSetsSecurityHeaders(t *testing.T) {
	gin.SetMode(gin.TestMode)
	reader := &closeTrackingStream{Reader: bytes.NewReader([]byte("image"))}
	handler, err := NewStreamHandler(closeTrackingStreamUseCase{reader: reader})
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.GET("/media/:id/original", handler.Original)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/media/media/original", nil))
	if recorder.Code != http.StatusOK || !reader.closed {
		t.Fatalf("status=%d closed=%v", recorder.Code, reader.closed)
	}
	if recorder.Header().Get("Content-Type") != "image/jpeg" || recorder.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("headers=%v", recorder.Header())
	}
}
