package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// 本文件职责：上传 Handler 的 HTTP 边界测试。
// 覆盖 multipart 解析、201 响应形状、错误码映射与 file 字段约定。

type recordingUploadUseCase struct {
	sourceID string
	userID   string
	filename string
	result   domain.UploadResult
	err      error
}

func (u *recordingUploadUseCase) Upload(_ context.Context, sourceID, userID string, input domain.UploadedImage) (domain.UploadResult, error) {
	u.sourceID = sourceID
	u.userID = userID
	u.filename = input.Filename
	if input.Reader != nil {
		// io.Reader 无 Close；multipart.Part 由 net/http 管理
	}
	return u.result, u.err
}

func newUploadTestEngine(t *testing.T, useCase UploadUseCase) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	h, err := NewUploadHandler(useCase)
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.POST("/api/v1/sources/:id/images", func(c *gin.Context) {
		c.Set("user_id", "user_a")
		h.Create(c)
	})
	return engine
}

func multipartUploadRequest(t *testing.T, filename string, content []byte) *http.Request {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", `form-data; name="file"; filename="`+filename+`"`)
	header.Set("Content-Type", "image/png")
	part, err := writer.CreatePart(header)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(content); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/sources/source_a/images", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	return request
}

func TestUploadHandlerReturnsCreatedShape(t *testing.T) {
	useCase := &recordingUploadUseCase{result: domain.UploadResult{MediaID: "media_x", Filename: "a.png"}}
	engine := newUploadTestEngine(t, useCase)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, multipartUploadRequest(t, "a.png", []byte("png")))
	if recorder.Code != http.StatusCreated {
		t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
	}
	var payload map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["media_id"] != "media_x" || payload["filename"] != "a.png" {
		t.Fatalf("payload=%#v", payload)
	}
	if useCase.sourceID != "source_a" || useCase.userID != "user_a" || useCase.filename != "a.png" {
		t.Fatalf("use case args=%#v", useCase)
	}
}

func TestUploadHandlerRejectsNonMultipart(t *testing.T) {
	useCase := &recordingUploadUseCase{}
	engine := newUploadTestEngine(t, useCase)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/sources/source_a/images", bytes.NewReader([]byte("{}")))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
	}
	var envelope struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	if envelope.Error.Code != "INVALID_REQUEST" {
		t.Fatalf("code=%q", envelope.Error.Code)
	}
}

func TestUploadHandlerRejectsMissingFilePart(t *testing.T) {
	useCase := &recordingUploadUseCase{}
	engine := newUploadTestEngine(t, useCase)
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	if err := writer.WriteField("other", "x"); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/sources/source_a/images", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
	}
}

func TestUploadHandlerMapsErrorCodes(t *testing.T) {
	tests := []struct {
		err    error
		status int
		code   string
	}{
		{domain.ErrSourceNotFound, http.StatusNotFound, "SOURCE_NOT_FOUND"},
		{domain.ErrUploadTooLarge, http.StatusRequestEntityTooLarge, "UPLOAD_TOO_LARGE"},
		{domain.ErrUploadUnsupportedImage, http.StatusBadRequest, "UNSUPPORTED_IMAGE"},
		{domain.ErrSourceOffline, http.StatusServiceUnavailable, "SOURCE_OFFLINE"},
		{domain.ErrUnauthorized, http.StatusUnauthorized, "UNAUTHORIZED"},
	}
	for _, test := range tests {
		useCase := &recordingUploadUseCase{err: test.err}
		engine := newUploadTestEngine(t, useCase)
		recorder := httptest.NewRecorder()
		engine.ServeHTTP(recorder, multipartUploadRequest(t, "a.png", []byte("png")))
		if recorder.Code != test.status {
			t.Fatalf("%v: status=%d body=%q", test.err, recorder.Code, recorder.Body.String())
		}
		var envelope struct {
			Error struct {
				Code string `json:"code"`
			} `json:"error"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &envelope); err != nil {
			t.Fatal(err)
		}
		if envelope.Error.Code != test.code {
			t.Fatalf("%v: code=%q want %q", test.err, envelope.Error.Code, test.code)
		}
	}
}

func TestUploadHandlerPropagatesGenericError(t *testing.T) {
	useCase := &recordingUploadUseCase{err: errors.New("disk gone")}
	engine := newUploadTestEngine(t, useCase)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, multipartUploadRequest(t, "a.png", []byte("png")))
	if recorder.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
	}
	var envelope struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	_ = json.Unmarshal(recorder.Body.Bytes(), &envelope)
	if envelope.Error.Code != "INTERNAL_ERROR" {
		t.Fatalf("code=%q", envelope.Error.Code)
	}
}

// capturingUploadUseCase 捕获业务用例收到的 UploadedImage，用于验证 CommitCheck 语义。
type capturingUploadUseCase struct {
	capture *domain.UploadedImage
	result  domain.UploadResult
	err     error
}

func (u *capturingUploadUseCase) Upload(_ context.Context, _, _ string, input domain.UploadedImage) (domain.UploadResult, error) {
	*u.capture = input
	return u.result, u.err
}

func TestUploadHandlerCommitCheckRejectsExtraPart(t *testing.T) {
	// 真实语义：服务的 CommitCheck 在 file 部件读完后检测到多余部件时中止上传。
	var captured domain.UploadedImage
	useCase := &capturingUploadUseCase{capture: &captured, result: domain.UploadResult{MediaID: "m", Filename: "a.png"}}
	engine := newUploadTestEngine(t, useCase)
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("file", "a.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write([]byte("png")); err != nil {
		t.Fatal(err)
	}
	if err := writer.WriteField("extra", "junk"); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/sources/source_a/images", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, request)
	if captured.CommitCheck == nil {
		t.Fatal("CommitCheck not passed to use case")
	}
	// 先把 file 部件读到 EOF，multipart 边界才对齐；随后 CommitCheck 应发现多余部件。
	if _, err := io.Copy(io.Discard, captured.Reader); err != nil {
		t.Fatal(err)
	}
	if err := captured.CommitCheck(); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("CommitCheck = %v, want INVALID_REQUEST", err)
	}
}

func TestUploadHandlerCommitCheckAcceptsExactEnd(t *testing.T) {
	// 正文恰好结束时 CommitCheck 返回 nil，允许发布。
	var captured domain.UploadedImage
	useCase := &capturingUploadUseCase{capture: &captured, result: domain.UploadResult{MediaID: "m", Filename: "a.png"}}
	engine := newUploadTestEngine(t, useCase)
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, multipartUploadRequest(t, "a.png", []byte("png")))
	if captured.CommitCheck == nil {
		t.Fatal("CommitCheck not passed to use case")
	}
	if _, err := io.Copy(io.Discard, captured.Reader); err != nil {
		t.Fatal(err)
	}
	if err := captured.CommitCheck(); err != nil {
		t.Fatalf("CommitCheck = %v, want nil", err)
	}
}

func TestUploadHandlerRejectsOversizedBody(t *testing.T) {
	// Content-Length 超过 64MiB+余量直接 413，不读正文。
	useCase := &recordingUploadUseCase{}
	engine := newUploadTestEngine(t, useCase)
	body := io.LimitReader(&zeroReader{}, domain.MaxUploadImageBytes+(1<<20)+1)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/sources/source_a/images", body)
	request.ContentLength = domain.MaxUploadImageBytes + (1 << 20) + 1
	request.Header.Set("Content-Type", "multipart/form-data; boundary=x")
	recorder := httptest.NewRecorder()
	engine.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
	}
}

type zeroReader struct{}

func (*zeroReader) Read(p []byte) (int, error) { return len(p), nil }
