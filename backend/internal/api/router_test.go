package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/api/handler"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/security"
	"github.com/xinghe98/Luma/backend/internal/service"
)

// fakeSystemUseCase 为 Router 测试提供可预测的系统业务结果。
type fakeSystemUseCase struct{}

// Health 返回固定健康状态。
func (fakeSystemUseCase) Health(context.Context) domain.Health {
	return domain.Health{Status: "ok", Version: "0.1.0"}
}

// fakeSourceUseCase 为 Router 测试提供空媒体源业务能力。
type fakeSourceUseCase struct{}

// List 返回空媒体源列表。
func (fakeSourceUseCase) ListVisible(context.Context, string) ([]domain.Source, error) {
	return nil, nil
}

// Create 返回请求对应的测试媒体源。
func (fakeSourceUseCase) Create(_ context.Context, command domain.CreateSourceCommand) (domain.Source, error) {
	return domain.Source{Name: command.Name}, nil
}

// Update 返回测试媒体源。
func (fakeSourceUseCase) Update(_ context.Context, command domain.UpdateSourceCommand) (domain.Source, error) {
	return domain.Source{ID: command.ID}, nil
}

// Delete 模拟成功软删除媒体源。
func (fakeSourceUseCase) Delete(context.Context, string) error { return nil }

// fakeScanUseCase 为 Router 测试提供空扫描任务业务能力。
type fakeScanUseCase struct{}

// fakeMediaUseCase 为 Router 测试提供媒体 API 结果。
type fakeMediaUseCase struct{}

type fakeCatalogUseCase struct{}

type fakeAccessUseCase struct{}

func (fakeAccessUseCase) ListUsers(context.Context) ([]domain.User, error) {
	return []domain.User{}, nil
}
func (fakeAccessUseCase) CreateUser(_ context.Context, name, username, _ string) (domain.User, error) {
	return domain.User{ID: "user_test", Name: name, Username: username, Role: domain.RoleMember, Enabled: true}, nil
}
func (fakeAccessUseCase) UpdateUser(context.Context, string, *string, *bool) (domain.User, error) {
	return domain.User{ID: "user_test", Role: domain.RoleMember, Enabled: true}, nil
}
func (fakeAccessUseCase) ResetPassword(context.Context, string, string) error { return nil }
func (fakeAccessUseCase) ListSessions(context.Context, string) ([]domain.APIToken, error) {
	return []domain.APIToken{}, nil
}
func (fakeAccessUseCase) RevokeSession(context.Context, string) error { return nil }
func (fakeAccessUseCase) ListGrants(context.Context, string) ([]string, error) {
	return []string{}, nil
}
func (fakeAccessUseCase) GrantSource(context.Context, string, string) error  { return nil }
func (fakeAccessUseCase) RevokeSource(context.Context, string, string) error { return nil }

type fakeAuthenticationUseCase struct{}

func (fakeAuthenticationUseCase) Login(context.Context, string, string, string) (domain.IssuedSession, error) {
	return domain.IssuedSession{}, nil
}
func (fakeAuthenticationUseCase) Logout(context.Context, string) error { return nil }

func (fakeCatalogUseCase) List(context.Context, domain.CatalogListRequest, string) ([]domain.CatalogItem, error) {
	return []domain.CatalogItem{}, nil
}
func (fakeCatalogUseCase) Get(context.Context, string, string) (domain.CatalogItem, error) {
	return domain.CatalogItem{ID: "catalog_test", Kind: domain.CatalogKindMovie, Title: "测试电影"}, nil
}
func (fakeCatalogUseCase) Issues(context.Context, int) ([]domain.CatalogIssue, error) {
	return []domain.CatalogIssue{}, nil
}
func (fakeCatalogUseCase) UpdateMatch(context.Context, domain.UpdateCatalogMatchCommand) error {
	return nil
}

// fakeStreamUseCase 为 Router 测试提供可定位的原始媒体内容。
type fakeStreamUseCase struct{}

type fakeUserDataUseCase struct{}

func (fakeUserDataUseCase) Get(_ context.Context, userID, mediaID string) (domain.MediaUserData, error) {
	return domain.MediaUserData{UserID: userID, MediaID: mediaID, Tags: []domain.Tag{}}, nil
}

func (fakeUserDataUseCase) Update(_ context.Context, command domain.UpdateUserDataCommand) (domain.MediaUserData, error) {
	return domain.MediaUserData{UserID: command.UserID, MediaID: command.MediaID, Revision: command.BaseRevision + 1, Tags: []domain.Tag{}}, nil
}

func (fakeUserDataUseCase) UpdateProgress(_ context.Context, userID, mediaID string, positionMS, baseRevision int64) (domain.MediaUserData, error) {
	return domain.MediaUserData{UserID: userID, MediaID: mediaID, ProgressMS: positionMS, Revision: baseRevision + 1, Tags: []domain.Tag{}}, nil
}

type fakeTagUseCase struct{}

func (fakeTagUseCase) List(context.Context, string) ([]domain.Tag, error) { return []domain.Tag{}, nil }
func (fakeTagUseCase) Create(_ context.Context, command domain.CreateTagCommand) (domain.Tag, error) {
	return domain.Tag{ID: "tag_test", UserID: command.UserID, Name: command.Name, Revision: 1}, nil
}
func (fakeTagUseCase) Update(_ context.Context, command domain.UpdateTagCommand) (domain.Tag, error) {
	return domain.Tag{ID: command.ID, UserID: command.UserID, Name: command.Name, Revision: command.BaseRevision + 1}, nil
}
func (fakeTagUseCase) Delete(context.Context, string, string) error { return nil }

type memoryStream struct {
	// Reader 提供内存流的读取和定位能力。
	*bytes.Reader
}

func (*memoryStream) Close() error { return nil }

func (fakeStreamUseCase) Open(context.Context, string, string) (domain.StreamContent, error) {
	return domain.StreamContent{
		Name: "test.mp4", MIMEType: "video/mp4", ETag: `W/"c-3b9aca00"`, Size: 12,
		ModifiedAt: time.Unix(1, 0).UTC(), Reader: &memoryStream{bytes.NewReader([]byte("video-stream"))},
	}, nil
}

func (fakeStreamUseCase) OpenOriginal(context.Context, string, string) (domain.StreamContent, error) {
	return domain.StreamContent{
		Name: "photo.jpg", MIMEType: "image/jpeg", ETag: `W/"a-3b9aca00"`, Size: 10,
		ModifiedAt: time.Unix(1, 0).UTC(), Reader: &memoryStream{bytes.NewReader([]byte("image-data"))},
	}, nil
}

func (fakeMediaUseCase) List(context.Context, domain.MediaListRequest, string) (domain.MediaPage, error) {
	return domain.MediaPage{Items: []domain.Media{{
		ID: "media_test", Filename: "test.mp4", Title: "test.mp4", MediaType: domain.MediaTypeVideo,
		Status: domain.MediaStatusReady, HasThumbnail: true,
	}}}, nil
}

func (fakeMediaUseCase) Count(context.Context, domain.MediaListRequest, string) (int, error) {
	return 1, nil
}

func (fakeMediaUseCase) Get(context.Context, string, string) (domain.Media, error) {
	return domain.Media{
		ID: "media_test", Filename: "test.mp4", Title: "test.mp4", MediaType: domain.MediaTypeVideo,
		Status: domain.MediaStatusReady, HasThumbnail: true,
	}, nil
}

func (fakeMediaUseCase) Thumbnail(_ context.Context, _, _, ifNoneMatch, _ string) (domain.ThumbnailContent, error) {
	const etag = `"etag"`
	if ifNoneMatch == etag {
		return domain.ThumbnailContent{MIMEType: "image/jpeg", ETag: etag, NotModified: true}, nil
	}
	return domain.ThumbnailContent{Data: []byte("jpeg"), MIMEType: "image/jpeg", ETag: etag}, nil
}

// Start 返回待执行测试扫描任务。
func (fakeScanUseCase) Start(_ context.Context, sourceID string) (domain.ScanJob, error) {
	return domain.ScanJob{ID: "scan_test", SourceID: sourceID}, nil
}

// Get 返回指定测试扫描任务。
func (fakeScanUseCase) Get(_ context.Context, id string) (domain.ScanJob, error) {
	return domain.ScanJob{ID: id}, nil
}

// Latest 返回最近测试扫描任务。
func (fakeScanUseCase) Latest(context.Context, string) (domain.ScanJob, error) {
	return domain.ScanJob{ID: "scan_latest"}, nil
}

// Info 返回固定系统信息。
func (fakeSystemUseCase) Info(context.Context) (domain.SystemInfo, error) {
	return domain.SystemInfo{
		Version: "0.1.0", Platform: "test", Architecture: "test", Database: "ok",
	}, nil
}

type fakeManagedSourceUseCase struct{}

func (fakeManagedSourceUseCase) Create(context.Context, service.ManagedMediaSourceCommand) (service.ManagedMediaSourceResult, error) {
	return service.ManagedMediaSourceResult{}, nil
}

func (fakeManagedSourceUseCase) ListAvailableRoots() ([]string, error) {
	return []string{"/media/family", "/media/movies"}, nil
}

// testRouter 创建注入测试替身的完整 Router。
func testRouter(t *testing.T) http.Handler {
	t.Helper()
	useCase := fakeSystemUseCase{}
	health, err := handler.NewHealthHandler(useCase)
	if err != nil {
		t.Fatal(err)
	}
	system, err := handler.NewSystemHandler(useCase)
	if err != nil {
		t.Fatal(err)
	}
	sources, err := handler.NewSourceHandler(fakeSourceUseCase{}, fakeManagedSourceUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	scans, err := handler.NewScanHandler(fakeScanUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	media, err := handler.NewMediaHandler(fakeMediaUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	stream, err := handler.NewStreamHandler(fakeStreamUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	userData, err := handler.NewUserDataHandler(fakeUserDataUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	tags, err := handler.NewTagHandler(fakeTagUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	catalogHandler, err := handler.NewCatalogHandler(fakeCatalogUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	accessHandler, err := handler.NewAccessHandler(fakeAccessUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	authHandler, err := handler.NewAuthHandler(fakeAuthenticationUseCase{})
	if err != nil {
		t.Fatal(err)
	}
	authenticator, err := security.NewTokenAuthenticator("abcdefghijklmnopqrstuvwxyz123456")
	if err != nil {
		t.Fatal(err)
	}
	router, err := NewRouter(RouterParams{
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Health: health, System: system, Sources: sources, Scans: scans, Media: media, Stream: stream,
		UserData: userData, Tags: tags, Catalog: catalogHandler, Access: accessHandler, Auth: authHandler,
		Authenticator: authenticator,
	})
	if err != nil {
		t.Fatal(err)
	}
	return router
}

// TestStreamRouteSupportsRangeHeadAndConditionalRequests 验证完整 Router 不破坏标准内容服务语义。
func TestStreamRouteSupportsRangeHeadAndConditionalRequests(t *testing.T) {
	router := testRouter(t)
	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/media/media_test/stream", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status=%d", unauthorized.Code)
	}
	tests := []struct {
		// name 是测试场景名称。
		name string
		// method 是请求使用的 HTTP 方法。
		method string
		// rangeHeader 是请求携带的 Range 头。
		rangeHeader string
		// ifNoneMatch 是请求携带的 If-None-Match 头。
		ifNoneMatch string
		// ifModifiedSince 是请求携带的 If-Modified-Since 头。
		ifModifiedSince string
		// ifRange 是请求携带的 If-Range 头。
		ifRange string
		// status 是期望的 HTTP 状态码。
		status int
		// bodyLength 是期望的响应体长度。
		bodyLength int
		// contentRange 是期望的 Content-Range 头。
		contentRange string
	}{
		{name: "完整内容", method: http.MethodGet, status: http.StatusOK, bodyLength: 12},
		{name: "Range", method: http.MethodGet, rangeHeader: "bytes=2-6", status: http.StatusPartialContent, bodyLength: 5, contentRange: "bytes 2-6/12"},
		{name: "后缀 Range", method: http.MethodGet, rangeHeader: "bytes=-4", status: http.StatusPartialContent, bodyLength: 4, contentRange: "bytes 8-11/12"},
		{name: "HEAD", method: http.MethodHead, status: http.StatusOK},
		{name: "ETag", method: http.MethodGet, ifNoneMatch: `W/"c-3b9aca00"`, status: http.StatusNotModified},
		{name: "修改时间", method: http.MethodGet, ifModifiedSince: "Thu, 01 Jan 1970 00:00:01 GMT", status: http.StatusNotModified},
		{name: "If-Range 日期匹配", method: http.MethodGet, rangeHeader: "bytes=0-3", ifRange: "Thu, 01 Jan 1970 00:00:01 GMT", status: http.StatusPartialContent, bodyLength: 4, contentRange: "bytes 0-3/12"},
		{name: "If-Range 弱 ETag", method: http.MethodGet, rangeHeader: "bytes=0-3", ifRange: `W/"c-3b9aca00"`, status: http.StatusOK, bodyLength: 12},
		{name: "If-Range 不匹配", method: http.MethodGet, rangeHeader: "bytes=0-3", ifRange: `W/"other"`, status: http.StatusOK, bodyLength: 12},
		{name: "越界 Range", method: http.MethodGet, rangeHeader: "bytes=20-30", status: http.StatusRequestedRangeNotSatisfiable, bodyLength: -1, contentRange: "bytes */12"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(test.method, "/api/v1/media/media_test/stream", nil)
			request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
			request.Header.Set("Range", test.rangeHeader)
			request.Header.Set("If-None-Match", test.ifNoneMatch)
			request.Header.Set("If-Modified-Since", test.ifModifiedSince)
			request.Header.Set("If-Range", test.ifRange)
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			if recorder.Code != test.status || (test.bodyLength >= 0 && recorder.Body.Len() != test.bodyLength) {
				t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
			}
			if got := recorder.Header().Get("Content-Range"); got != test.contentRange {
				t.Fatalf("content-range=%q, want %q", got, test.contentRange)
			}
			if recorder.Header().Get("Accept-Ranges") != "bytes" && test.status != http.StatusNotModified && test.status != http.StatusRequestedRangeNotSatisfiable {
				t.Fatalf("accept-ranges=%q", recorder.Header().Get("Accept-Ranges"))
			}
			if recorder.Header().Get("Cache-Control") != "private, max-age=0, must-revalidate" && test.status != http.StatusRequestedRangeNotSatisfiable {
				t.Fatalf("cache-control=%q", recorder.Header().Get("Cache-Control"))
			}
		})
	}
}

func TestOriginalRouteSupportsAuthenticatedRangeAndHead(t *testing.T) {
	router := testRouter(t)
	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/media/media_test/original", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status=%d", unauthorized.Code)
	}
	tests := []struct {
		name         string
		method       string
		rangeHeader  string
		ifNoneMatch  string
		status       int
		body         string
		contentRange string
	}{
		{name: "完整原图", method: http.MethodGet, status: http.StatusOK, body: "image-data"},
		{name: "Range", method: http.MethodGet, rangeHeader: "bytes=1-4", status: http.StatusPartialContent, body: "mage", contentRange: "bytes 1-4/10"},
		{name: "HEAD", method: http.MethodHead, status: http.StatusOK},
		{name: "ETag", method: http.MethodGet, ifNoneMatch: `W/"a-3b9aca00"`, status: http.StatusNotModified},
		{name: "越界 Range", method: http.MethodGet, rangeHeader: "bytes=20-30", status: http.StatusRequestedRangeNotSatisfiable, contentRange: "bytes */10"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(test.method, "/api/v1/media/media_test/original", nil)
			request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
			request.Header.Set("Range", test.rangeHeader)
			request.Header.Set("If-None-Match", test.ifNoneMatch)
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			if recorder.Code != test.status || ((test.status == http.StatusOK || test.status == http.StatusPartialContent) && recorder.Body.String() != test.body) {
				t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
			}
			if got := recorder.Header().Get("Content-Range"); got != test.contentRange {
				t.Fatalf("content-range=%q, want %q", got, test.contentRange)
			}
			if test.status != http.StatusRequestedRangeNotSatisfiable && recorder.Header().Get("X-Content-Type-Options") != "nosniff" {
				t.Fatalf("x-content-type-options=%q", recorder.Header().Get("X-Content-Type-Options"))
			}
		})
	}
}

// TestHealthDoesNotRequireAuthentication 验证健康检查不要求认证。
func TestHealthDoesNotRequireAuthentication(t *testing.T) {
	recorder := httptest.NewRecorder()
	testRouter(t).ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/health", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d", recorder.Code)
	}
	var body map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["status"] != "ok" || body["version"] != "0.1.0" {
		t.Fatalf("unexpected body: %#v", body)
	}
}

// TestAPIRequiresValidToken 验证业务 API 拒绝缺失或错误的 Token。
func TestAPIRequiresValidToken(t *testing.T) {
	router := testRouter(t)
	for name, authorization := range map[string]struct {
		// header 是请求携带的认证头。
		header string
		// status 是期望的 HTTP 状态码。
		status int
	}{
		"missing": {"", http.StatusUnauthorized},
		"wrong":   {"Bearer wrong", http.StatusUnauthorized},
		"valid":   {"Bearer abcdefghijklmnopqrstuvwxyz123456", http.StatusOK},
	} {
		t.Run(name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/system/info", nil)
			req.Header.Set("Authorization", authorization.header)
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, req)
			if recorder.Code != authorization.status {
				t.Fatalf("status = %d, want %d", recorder.Code, authorization.status)
			}
		})
	}
}

// TestUnknownAPIRouteIsStillProtected 验证未知 API 路由同样受认证保护。
func TestUnknownAPIRouteIsStillProtected(t *testing.T) {
	recorder := httptest.NewRecorder()
	testRouter(t).ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/v1/not-implemented", nil))
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusUnauthorized)
	}
}

// TestSourceAPIRejectsUnknownFieldsAndHidesRootPath 验证严格 JSON 和路径脱敏响应。
func TestSourceAPIRejectsUnknownFieldsAndHidesRootPath(t *testing.T) {
	router := testRouter(t)
	for name, body := range map[string]struct {
		// body 是请求使用的 JSON 内容。
		body string
		// status 是期望的 HTTP 状态码。
		status int
	}{
		"未知字段": {`{"name":"媒体","root_path":"C:\\Media","extra":true}`, http.StatusBadRequest},
		"正常请求": {`{"name":"媒体","root_path":"C:\\Media"}`, http.StatusCreated},
	} {
		t.Run(name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/api/v1/sources", strings.NewReader(body.body))
			request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			if recorder.Code != body.status {
				t.Fatalf("状态码 = %d，期望 %d，响应=%s", recorder.Code, body.status, recorder.Body.String())
			}
			if strings.Contains(recorder.Body.String(), "root_path") {
				t.Fatal("响应不得返回真实媒体源路径")
			}
		})
	}
}

func TestAdminMediaRootsAreListedForAdministrators(t *testing.T) {
	router := testRouter(t)
	request := httptest.NewRequest(http.MethodGet, "/api/v1/admin/media-roots", nil)
	request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	var body struct {
		Items []string `json:"items"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(body.Items, []string{"/media/family", "/media/movies"}) {
		t.Fatalf("items=%#v", body.Items)
	}
}

// TestMediaRoutesRequireAuthAndSupportThumbnailRevalidation 验证媒体路由认证及缩略图 304。
func TestMediaRoutesRequireAuthAndSupportThumbnailRevalidation(t *testing.T) {
	router := testRouter(t)
	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/media", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d", unauthorized.Code)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v1/media/media_test/thumbnail", nil)
	request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
	request.Header.Set("If-None-Match", `"etag"`)
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusNotModified || recorder.Body.Len() != 0 {
		t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
	}
	if recorder.Header().Get("Cache-Control") != "private, max-age=604800, must-revalidate" {
		t.Fatalf("cache-control = %q", recorder.Header().Get("Cache-Control"))
	}
}

// TestMediaListRejectsInvalidLimitAndDoesNotExposePaths 验证列表参数校验和响应脱敏。
func TestMediaListRejectsInvalidLimitAndDoesNotExposePaths(t *testing.T) {
	router := testRouter(t)
	for _, test := range []struct {
		// url 是待请求的媒体列表地址。
		url string
		// status 是期望的 HTTP 状态码。
		status int
	}{
		{url: "/api/v1/media?limit=invalid", status: http.StatusBadRequest},
		{url: "/api/v1/media", status: http.StatusOK},
	} {
		request := httptest.NewRequest(http.MethodGet, test.url, nil)
		request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, request)
		if recorder.Code != test.status {
			t.Fatalf("url=%s status=%d body=%s", test.url, recorder.Code, recorder.Body.String())
		}
		if strings.Contains(recorder.Body.String(), "root_path") || strings.Contains(recorder.Body.String(), "relative_path") || strings.Contains(recorder.Body.String(), "storage_key") {
			t.Fatalf("response exposes internal path: %s", recorder.Body.String())
		}
	}
}

func TestCatalogRoutesRequireAuthAndExposeStableShapes(t *testing.T) {
	router := testRouter(t)
	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/catalog", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized catalog status=%d", unauthorized.Code)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v1/catalog/catalog_test", nil)
	request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
	responseRecorder := httptest.NewRecorder()
	router.ServeHTTP(responseRecorder, request)
	if responseRecorder.Code != http.StatusOK {
		t.Fatalf("catalog detail status=%d body=%s", responseRecorder.Code, responseRecorder.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(responseRecorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["kind"] != domain.CatalogKindMovie || body["playable_media_id"] == nil || body["thumbnail_url"] == nil {
		t.Fatalf("unexpected catalog payload: %#v", body)
	}

	update := httptest.NewRequest(http.MethodPatch, "/api/v1/catalog/media/media_test", strings.NewReader(`{"ignored":true}`))
	update.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
	update.Header.Set("Content-Type", "application/json")
	updated := httptest.NewRecorder()
	router.ServeHTTP(updated, update)
	if updated.Code != http.StatusNoContent {
		t.Fatalf("catalog update status=%d body=%s", updated.Code, updated.Body.String())
	}
}

func TestStage6RoutesRequireAuthAndValidateWrites(t *testing.T) {
	router := testRouter(t)
	for _, path := range []string{
		"/api/v1/media/continue-watching", "/api/v1/media/media_test/user-data",
		"/api/v1/tags",
	} {
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, path, nil))
		if recorder.Code != http.StatusUnauthorized {
			t.Fatalf("path=%s status=%d", path, recorder.Code)
		}
	}
	tests := []struct {
		name   string
		method string
		path   string
		body   string
		status int
	}{
		{name: "继续观看", method: http.MethodGet, path: "/api/v1/media/continue-watching", status: http.StatusOK},
		{name: "读取用户数据", method: http.MethodGet, path: "/api/v1/media/media_test/user-data", status: http.StatusOK},
		{name: "更新用户数据", method: http.MethodPatch, path: "/api/v1/media/media_test/user-data", body: `{"base_revision":0,"favorite":true,"tag_ids":[]}`, status: http.StatusOK},
		{name: "缺少 revision", method: http.MethodPatch, path: "/api/v1/media/media_test/user-data", body: `{"favorite":true}`, status: http.StatusBadRequest},
		{name: "保存进度", method: http.MethodPut, path: "/api/v1/media/media_test/progress", body: `{"position_ms":0,"base_revision":0}`, status: http.StatusOK},
		{name: "进度字段缺失", method: http.MethodPut, path: "/api/v1/media/media_test/progress", body: `{}`, status: http.StatusBadRequest},
		{name: "标签列表", method: http.MethodGet, path: "/api/v1/tags", status: http.StatusOK},
		{name: "创建标签", method: http.MethodPost, path: "/api/v1/tags", body: `{"name":"旅行"}`, status: http.StatusCreated},
		{name: "更新标签", method: http.MethodPatch, path: "/api/v1/tags/tag_test", body: `{"name":"出游","base_revision":1}`, status: http.StatusOK},
		{name: "删除标签", method: http.MethodDelete, path: "/api/v1/tags/tag_test", status: http.StatusNoContent},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(test.method, test.path, strings.NewReader(test.body))
			request.Header.Set("Authorization", "Bearer abcdefghijklmnopqrstuvwxyz123456")
			if test.body != "" {
				request.Header.Set("Content-Type", "application/json")
			}
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			if recorder.Code != test.status {
				t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
			}
		})
	}
}
