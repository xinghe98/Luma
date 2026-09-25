package handler

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
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

// pinnedStreamUseCase 提供可控的入口决策与固定表示内容。
type pinnedStreamUseCase struct {
	// target 是入口决策返回的固定表示。
	target domain.StreamTarget
	// planErr 是入口决策返回的错误。
	planErr error
	// source 是原始视频与原始图片表示的内容。
	source *closeTrackingStream
	// faststartCopy 是 faststart 副本表示的内容。
	faststartCopy *closeTrackingStream
}

func (u pinnedStreamUseCase) Plan(context.Context, string, string) (domain.StreamTarget, error) {
	return u.target, u.planErr
}

func (u pinnedStreamUseCase) OpenSource(context.Context, string, string) (domain.StreamContent, error) {
	return domain.StreamContent{
		Name: "clip.mp4", MIMEType: "video/mp4", ETag: `W/"5-1"`, Size: 5,
		ModifiedAt: time.Unix(1, 0).UTC(), Reader: u.source,
	}, nil
}

func (u pinnedStreamUseCase) OpenFaststart(_ context.Context, _, _, fingerprint string) (domain.StreamContent, error) {
	if fingerprint != "5-1000" {
		return domain.StreamContent{}, domain.ErrStreamCacheMiss
	}
	return domain.StreamContent{
		Name: "clip.mp4", MIMEType: "video/mp4", ETag: `W/"e-1"`, Size: 14,
		ModifiedAt: time.Unix(1, 0).UTC(), Reader: u.faststartCopy,
	}, nil
}

func (u pinnedStreamUseCase) OpenOriginal(context.Context, string, string) (domain.StreamContent, error) {
	return domain.StreamContent{
		Name: "photo.jpg", MIMEType: "image/jpeg", ETag: `W/"5-1"`, Size: 5,
		ModifiedAt: time.Unix(1, 0).UTC(), Reader: u.source,
	}, nil
}

// TestStreamHandlerRedirectsEntryToPinnedRepresentation 验证入口只返回固定表示地址且不返回内容字节。
func TestStreamHandlerRedirectsEntryToPinnedRepresentation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tests := []struct {
		// name 是测试场景名称。
		name string
		// route 是注册的入口路由，用于验证反向代理前缀被保留。
		route string
		// requestPath 是实际请求的入口地址。
		requestPath string
		// clientPath 模拟反向代理剥离前缀之前的客户端地址。
		clientPath string
		// target 是入口决策结果。
		target domain.StreamTarget
		// wantLocation 是期望的相对跳转地址。
		wantLocation string
	}{
		{
			name: "冷入口固定原始文件", route: "/media/:id/stream", requestPath: "/media/media/stream",
			target:       domain.StreamTarget{Representation: domain.StreamRepresentationSource},
			wantLocation: "/media/media/stream/source",
		},
		{
			name: "热入口固定缓存副本", route: "/media/:id/stream", requestPath: "/media/media/stream",
			target:       domain.StreamTarget{Representation: domain.StreamRepresentationFaststart, Fingerprint: "5-1000"},
			wantLocation: "/media/media/stream/faststart/5-1000",
		},
		{
			name: "保留反向代理前缀", route: "/luma/media/:id/stream", requestPath: "/luma/media/media/stream",
			target:       domain.StreamTarget{Representation: domain.StreamRepresentationSource},
			wantLocation: "/luma/media/media/stream/source",
		},
		{
			name: "代理剥离前缀", route: "/media/:id/stream", requestPath: "/media/media/stream",
			clientPath:   "/luma/media/media/stream",
			target:       domain.StreamTarget{Representation: domain.StreamRepresentationSource},
			wantLocation: "/luma/media/media/stream/source",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			source := &closeTrackingStream{Reader: bytes.NewReader([]byte("video"))}
			handler, err := NewStreamHandler(pinnedStreamUseCase{target: test.target, source: source})
			if err != nil {
				t.Fatal(err)
			}
			engine := gin.New()
			engine.GET(test.route, handler.Stream)
			engine.HEAD(test.route, handler.Stream)
			for _, method := range []string{http.MethodGet, http.MethodHead} {
				recorder := httptest.NewRecorder()
				engine.ServeHTTP(recorder, httptest.NewRequest(method, test.requestPath, nil))
				clientPath := test.clientPath
				if clientPath == "" {
					clientPath = test.requestPath
				}
				base, err := url.Parse(clientPath)
				if err != nil {
					t.Fatal(err)
				}
				location, err := base.Parse(recorder.Header().Get("Location"))
				if err != nil {
					t.Fatal(err)
				}
				if recorder.Code != http.StatusFound || location.Path != test.wantLocation {
					t.Fatalf("%s status=%d location=%q, want %q", method, recorder.Code, recorder.Header().Get("Location"), test.wantLocation)
				}
				if recorder.Header().Get("Cache-Control") != "no-store" {
					t.Fatalf("%s cache-control=%q", method, recorder.Header().Get("Cache-Control"))
				}
				if recorder.Header().Get("ETag") != "" {
					t.Fatalf("%s entry redirect exposed content etag %q", method, recorder.Header().Get("ETag"))
				}
				if method == http.MethodHead && recorder.Body.Len() != 0 {
					t.Fatalf("HEAD redirect body=%q", recorder.Body.String())
				}
				if source.closed {
					t.Fatal("入口决策不应打开内容字节")
				}
			}
		})
	}
}

// TestStreamHandlerEntryReportsAccessErrors 验证入口权限错误仍使用统一错误响应且不产生跳转。
func TestStreamHandlerEntryReportsAccessErrors(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler, err := NewStreamHandler(pinnedStreamUseCase{planErr: domain.ErrMediaNotFound})
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.GET("/media/:id/stream", handler.Stream)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/media/media/stream", nil))
	if recorder.Code != http.StatusNotFound || !strings.Contains(recorder.Body.String(), "MEDIA_NOT_FOUND") {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if recorder.Header().Get("Location") != "" {
		t.Fatalf("错误响应不应跳转: location=%q", recorder.Header().Get("Location"))
	}
}

// TestStreamHandlerServesSourceRepresentationBytes 验证 source 表示返回真实字节并保留 Range 边界语义。
func TestStreamHandlerServesSourceRepresentationBytes(t *testing.T) {
	gin.SetMode(gin.TestMode)
	source := &closeTrackingStream{Reader: bytes.NewReader([]byte("video"))}
	handler, err := NewStreamHandler(pinnedStreamUseCase{source: source})
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.GET("/media/:id/stream/source", handler.Source)
	engine.HEAD("/media/:id/stream/source", handler.Source)

	tests := []struct {
		// name 是测试场景名称。
		name string
		// method 是请求方法。
		method string
		// rangeHeader 是请求携带的 Range 头。
		rangeHeader string
		// status 是期望状态码。
		status int
		// body 是期望响应体；skipBody 为 true 时不比较响应体。
		body string
		// skipBody 表示该场景只校验状态与头部。
		skipBody bool
		// contentRange 是期望的 Content-Range 头。
		contentRange string
	}{
		{name: "完整内容", method: http.MethodGet, status: http.StatusOK, body: "video"},
		{name: "HEAD 元数据", method: http.MethodHead, status: http.StatusOK},
		{name: "Range", method: http.MethodGet, rangeHeader: "bytes=1-3", status: http.StatusPartialContent, body: "ide", contentRange: "bytes 1-3/5"},
		{name: "后继 Range", method: http.MethodGet, rangeHeader: "bytes=4-4", status: http.StatusPartialContent, body: "o", contentRange: "bytes 4-4/5"},
		{name: "越界 Range", method: http.MethodGet, rangeHeader: "bytes=9-12", status: http.StatusRequestedRangeNotSatisfiable, skipBody: true, contentRange: "bytes */5"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(test.method, "/media/media/stream/source", nil)
			request.Header.Set("Range", test.rangeHeader)
			recorder := httptest.NewRecorder()
			engine.ServeHTTP(recorder, request)
			if recorder.Code != test.status || (!test.skipBody && recorder.Body.String() != test.body) {
				t.Fatalf("status=%d body=%q, want %d %q", recorder.Code, recorder.Body.String(), test.status, test.body)
			}
			if got := recorder.Header().Get("Content-Range"); got != test.contentRange {
				t.Fatalf("content-range=%q, want %q", got, test.contentRange)
			}
		})
	}
	if !source.closed {
		t.Fatal("内容服务结束后必须关闭读取器")
	}
}

// TestStreamHandlerFaststartRepresentationNeverFallsBackToSource 验证副本表示只返回副本字节，缺失时明确失败。
func TestStreamHandlerFaststartRepresentationNeverFallsBackToSource(t *testing.T) {
	gin.SetMode(gin.TestMode)
	source := &closeTrackingStream{Reader: bytes.NewReader([]byte("video"))}
	copyReader := &closeTrackingStream{Reader: bytes.NewReader([]byte("faststart-copy"))}
	handler, err := NewStreamHandler(pinnedStreamUseCase{source: source, faststartCopy: copyReader})
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.GET("/media/:id/stream/faststart/:fingerprint", handler.Faststart)
	engine.HEAD("/media/:id/stream/faststart/:fingerprint", handler.Faststart)

	hit := httptest.NewRecorder()
	engine.ServeHTTP(hit, httptest.NewRequest(http.MethodGet, "/media/media/stream/faststart/5-1000", nil))
	if hit.Code != http.StatusOK || hit.Body.String() != "faststart-copy" || !copyReader.closed {
		t.Fatalf("status=%d body=%q closed=%v", hit.Code, hit.Body.String(), copyReader.closed)
	}

	head := httptest.NewRecorder()
	engine.ServeHTTP(head, httptest.NewRequest(http.MethodHead, "/media/media/stream/faststart/5-1000", nil))
	if head.Code != http.StatusOK || head.Header().Get("Content-Length") != "14" ||
		head.Header().Get("ETag") != hit.Header().Get("ETag") {
		t.Fatalf("HEAD status=%d length=%q etag=%q", head.Code, head.Header().Get("Content-Length"), head.Header().Get("ETag"))
	}

	miss := httptest.NewRecorder()
	engine.ServeHTTP(miss, httptest.NewRequest(http.MethodGet, "/media/media/stream/faststart/5-1001", nil))
	if miss.Code != http.StatusNotFound || !strings.Contains(miss.Body.String(), "STREAM_CACHE_MISS") {
		t.Fatalf("status=%d body=%s", miss.Code, miss.Body.String())
	}
	if strings.Contains(miss.Body.String(), "video") {
		t.Fatalf("副本缺失返回了原始文件字节: %s", miss.Body.String())
	}
}

func TestOriginalHandlerClosesContentAndSetsSecurityHeaders(t *testing.T) {
	gin.SetMode(gin.TestMode)
	reader := &closeTrackingStream{Reader: bytes.NewReader([]byte("image"))}
	handler, err := NewStreamHandler(pinnedStreamUseCase{source: reader})
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
