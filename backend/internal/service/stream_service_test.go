package service

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

type fakeStreamRepository struct {
	// location 是仓储返回的流位置。
	location domain.StreamLocation
	// err 是仓储返回的错误。
	err error
}

func (r fakeStreamRepository) GetStreamLocation(context.Context, string, string) (domain.StreamLocation, error) {
	return r.location, r.err
}

type testStreamReader struct {
	// Reader 提供测试流的读取和定位能力。
	*bytes.Reader
	// closed 记录测试流是否已关闭。
	closed bool
}

func (r *testStreamReader) Close() error { r.closed = true; return nil }

type fakeContentOpener struct {
	// content 是打开后返回的测试内容。
	content domain.OpenedContent
	// err 是打开内容时返回的错误。
	err error
}

func (o fakeContentOpener) OpenContent(context.Context, string, string) (domain.OpenedContent, error) {
	return o.content, o.err
}

func TestStreamServiceOpensVideoAndBuildsMetadata(t *testing.T) {
	reader := &testStreamReader{Reader: bytes.NewReader([]byte("video"))}
	modified := time.Unix(123, 456).UTC()
	service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
		ID: "media", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo, MIMEType: "video/mp4",
		SourceType: domain.SourceTypeLocal, RootPath: "/media", RelativePath: "clip.mp4",
	}}, fakeContentOpener{content: domain.OpenedContent{Reader: reader, Size: 5, ModifiedAt: modified}})
	if err != nil {
		t.Fatal(err)
	}
	content, err := service.OpenSource(context.Background(), "media", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	wantModified := modified.Truncate(time.Second)
	if content.MIMEType != "video/mp4" || content.ETag != `W/"5-7b"` || !content.ModifiedAt.Equal(wantModified) || content.Size != 5 {
		t.Fatalf("content = %#v", content)
	}
	end, err := content.Reader.Seek(0, io.SeekEnd)
	if err != nil || end != 5 {
		t.Fatalf("seek end = %d err=%v", end, err)
	}
	if reader.closed {
		t.Fatal("Service 成功返回前不应关闭 Reader")
	}
	_ = content.Reader.Close()
}

func TestStreamServiceRejectsImagesAndUnavailableContent(t *testing.T) {
	tests := []struct {
		// name 是测试场景名称。
		name string
		// location 是仓储返回的流位置。
		location domain.StreamLocation
		// opener 提供场景使用的内容打开结果。
		opener fakeContentOpener
		// want 是期望错误。
		want error
	}{
		{name: "图片", location: domain.StreamLocation{MediaType: domain.MediaTypeImage, SourceType: domain.SourceTypeLocal}, want: domain.ErrMediaNotFound},
		{name: "内容不存在", location: domain.StreamLocation{MediaType: domain.MediaTypeVideo, SourceType: domain.SourceTypeLocal}, opener: fakeContentOpener{err: domain.ErrContentNotFound}, want: domain.ErrMediaNotFound},
		{name: "来源离线", location: domain.StreamLocation{MediaType: domain.MediaTypeVideo, SourceType: domain.SourceTypeLocal}, opener: fakeContentOpener{err: domain.ErrSourceOffline}, want: domain.ErrSourceOffline},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service, err := NewStreamService(fakeStreamRepository{location: test.location}, test.opener)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := service.OpenSource(context.Background(), "media", "user_local"); !errors.Is(err, test.want) {
				t.Fatalf("error = %v, want %v", err, test.want)
			}
		})
	}
}

func TestStreamServiceOpensOriginalImageAndRejectsVideo(t *testing.T) {
	reader := &testStreamReader{Reader: bytes.NewReader([]byte("image"))}
	service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
		ID: "image", Filename: "photo.webp", MediaType: domain.MediaTypeImage, MIMEType: "image/webp",
		SourceType: domain.SourceTypeLocal, RootPath: "/media", RelativePath: "photo.webp",
	}}, fakeContentOpener{content: domain.OpenedContent{Reader: reader, Size: 5, ModifiedAt: time.Unix(123, 0)}})
	if err != nil {
		t.Fatal(err)
	}
	content, err := service.OpenOriginal(context.Background(), "image", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	defer content.Reader.Close()
	if content.MIMEType != "image/webp" || content.Size != 5 || content.ETag != `W/"5-7b"` {
		t.Fatalf("content = %#v", content)
	}

	videoService, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
		MediaType: domain.MediaTypeVideo, SourceType: domain.SourceTypeLocal,
	}}, fakeContentOpener{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := videoService.OpenOriginal(context.Background(), "video", "user_local"); !errors.Is(err, domain.ErrMediaNotFound) {
		t.Fatalf("error = %v, want %v", err, domain.ErrMediaNotFound)
	}
}

func TestStreamServiceUsesSupportedImageMIMETypes(t *testing.T) {
	tests := map[string]string{
		"photo.jpg": "image/jpeg", "photo.jpeg": "image/jpeg", "photo.png": "image/png",
		"photo.webp": "image/webp", "photo.gif": "image/gif", "photo.bmp": "image/bmp",
	}
	for filename, expected := range tests {
		t.Run(filename, func(t *testing.T) {
			reader := &testStreamReader{Reader: bytes.NewReader([]byte("image"))}
			service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
				Filename: filename, MediaType: domain.MediaTypeImage, SourceType: domain.SourceTypeLocal,
			}}, fakeContentOpener{content: domain.OpenedContent{Reader: reader, Size: 5, ModifiedAt: time.Unix(1, 0)}})
			if err != nil {
				t.Fatal(err)
			}
			content, err := service.OpenOriginal(context.Background(), "image", "user_local")
			if err != nil {
				t.Fatal(err)
			}
			defer content.Reader.Close()
			if content.MIMEType != expected {
				t.Fatalf("mime=%q, want %q", content.MIMEType, expected)
			}
		})
	}
}

func TestStreamServiceDetectsMIMEAndRewindsReader(t *testing.T) {
	reader := &testStreamReader{Reader: bytes.NewReader([]byte("plain content"))}
	service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
		Filename: "clip.unknown", MediaType: domain.MediaTypeVideo, SourceType: domain.SourceTypeLocal,
	}}, fakeContentOpener{content: domain.OpenedContent{Reader: reader, Size: 13, ModifiedAt: time.Unix(1, 0)}})
	if err != nil {
		t.Fatal(err)
	}
	content, err := service.OpenSource(context.Background(), "media", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if content.MIMEType != "text/plain; charset=utf-8" {
		t.Fatalf("mime = %q", content.MIMEType)
	}
	position, err := content.Reader.Seek(0, io.SeekCurrent)
	if err != nil || position != 0 {
		t.Fatalf("reader position=%d err=%v", position, err)
	}
	_ = content.Reader.Close()
}

func TestStreamServiceUsesStableContainerMIMETypes(t *testing.T) {
	tests := map[string]string{
		"clip.mkv": "video/x-matroska", "clip.mov": "video/quicktime",
		"clip.avi": "video/x-msvideo", "clip.webm": "video/webm", "clip.ts": "video/mp2t",
	}
	for filename, expected := range tests {
		t.Run(filename, func(t *testing.T) {
			reader := &testStreamReader{Reader: bytes.NewReader([]byte("video"))}
			service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
				Filename: filename, MediaType: domain.MediaTypeVideo, SourceType: domain.SourceTypeLocal,
			}}, fakeContentOpener{content: domain.OpenedContent{Reader: reader, Size: 5, ModifiedAt: time.Unix(1, 0)}})
			if err != nil {
				t.Fatal(err)
			}
			content, err := service.OpenSource(context.Background(), "media", "user_local")
			if err != nil {
				t.Fatal(err)
			}
			defer content.Reader.Close()
			if content.MIMEType != expected {
				t.Fatalf("mime=%q, want %q", content.MIMEType, expected)
			}
		})
	}
}

func TestSizedReaderFreezesLengthForServeContent(t *testing.T) {
	inner := &testStreamReader{Reader: bytes.NewReader([]byte("0123456789"))}
	reader := newSizedReader(inner, 5)
	end, err := reader.Seek(0, io.SeekEnd)
	if err != nil || end != 5 {
		t.Fatalf("seek end = %d err=%v", end, err)
	}
	if _, err := reader.Seek(0, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	data, err := io.ReadAll(reader)
	if err != nil || string(data) != "01234" {
		t.Fatalf("data=%q err=%v", data, err)
	}
	_ = reader.Close()
}

type realFileStreamRepository struct {
	// root 是临时媒体源根目录。
	root string
}

func (r realFileStreamRepository) GetStreamLocation(context.Context, string, string) (domain.StreamLocation, error) {
	return domain.StreamLocation{
		ID: "media_real", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo, MIMEType: "video/mp4",
		SourceType: domain.SourceTypeLocal, RootPath: r.root, RelativePath: "clip.mp4",
	}, nil
}

// TestStreamServiceRealFileRangeMatchesSnapshot 验证真实文件打开后 Range 长度与快照一致。
func TestStreamServiceRealFileRangeMatchesSnapshot(t *testing.T) {
	root := t.TempDir()
	payload := []byte("0123456789abcdef")
	if err := os.WriteFile(filepath.Join(root, "clip.mp4"), payload, 0o644); err != nil {
		t.Fatal(err)
	}
	modified := time.Unix(1700000000, 0).UTC()
	if err := os.Chtimes(filepath.Join(root, "clip.mp4"), modified, modified); err != nil {
		t.Fatal(err)
	}
	factory, err := storage.NewLocalFactory(storageFileID{}, storageClock{})
	if err != nil {
		t.Fatal(err)
	}
	service, err := NewStreamService(realFileStreamRepository{root: root}, factory)
	if err != nil {
		t.Fatal(err)
	}
	content, err := service.OpenSource(context.Background(), "media_real", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	defer content.Reader.Close()
	wantETag := fmt.Sprintf(`W/"%x-%x"`, len(payload), content.ModifiedAt.Unix())
	if content.Size != int64(len(payload)) || content.ETag != wantETag {
		t.Fatalf("content=%#v wantETag=%s", content, wantETag)
	}
	request := httptest.NewRequest(http.MethodGet, "/stream", nil)
	request.Header.Set("Range", "bytes=2-5")
	recorder := httptest.NewRecorder()
	http.ServeContent(recorder, request, content.Name, content.ModifiedAt, content.Reader)
	if recorder.Code != http.StatusPartialContent || recorder.Body.String() != "2345" {
		t.Fatalf("status=%d body=%q", recorder.Code, recorder.Body.String())
	}
	if got := recorder.Header().Get("Content-Range"); got != "bytes 2-5/16" {
		t.Fatalf("content-range=%q", got)
	}
}

type storageFileID struct{}

func (storageFileID) Identify(string) (string, error) { return "file:test", nil }

type storageClock struct{}

func (storageClock) Now() time.Time { return time.Unix(0, 0).UTC() }

// stubFaststartCache 为 Service 测试提供可控的表示决策与副本打开结果。
type stubFaststartCache struct {
	// target 是 Plan 返回的固定表示。
	target domain.StreamTarget
	// opened 是 OpenFaststart 返回的副本内容。
	opened domain.OpenedContent
	// err 是 OpenFaststart 返回的错误。
	err error
	// selectCalls 记录表示决策次数。
	selectCalls int
	// openedFingerprint 记录最近一次请求打开的指纹。
	openedFingerprint string
}

func (c *stubFaststartCache) SelectRepresentation(domain.StreamLocation, domain.OpenedContent) domain.StreamTarget {
	c.selectCalls++
	return c.target
}

func (c *stubFaststartCache) OpenFaststart(_ domain.StreamLocation, _ domain.OpenedContent, fingerprint string) (domain.OpenedContent, error) {
	c.openedFingerprint = fingerprint
	if c.err != nil {
		return domain.OpenedContent{}, c.err
	}
	return c.opened, nil
}

// TestStreamServicePlanPinsRepresentation 验证入口只决策一次并立即释放源文件句柄。
func TestStreamServicePlanPinsRepresentation(t *testing.T) {
	for _, test := range []struct {
		// name 是测试场景名称。
		name string
		// target 是缓存协作器返回的固定表示。
		target domain.StreamTarget
	}{
		{name: "原始文件", target: domain.StreamTarget{Representation: domain.StreamRepresentationSource}},
		{name: "faststart 副本", target: domain.StreamTarget{Representation: domain.StreamRepresentationFaststart, Fingerprint: "8-1000"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			source := &testStreamReader{Reader: bytes.NewReader([]byte("original"))}
			service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
				ID: "media", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo, MIMEType: "video/mp4",
				SourceType: domain.SourceTypeLocal, RootPath: "/media", RelativePath: "clip.mp4",
			}}, fakeContentOpener{content: domain.OpenedContent{Reader: source, Size: 8, ModifiedAt: time.Unix(1, 0)}})
			if err != nil {
				t.Fatal(err)
			}
			cache := &stubFaststartCache{target: test.target}
			service.SetFaststartCache(cache)
			target, err := service.Plan(context.Background(), "media", "user_local")
			if err != nil {
				t.Fatal(err)
			}
			if target != test.target || cache.selectCalls != 1 {
				t.Fatalf("target=%#v calls=%d, want %#v", target, cache.selectCalls, test.target)
			}
			if !source.closed {
				t.Fatal("入口决策后必须立即关闭源文件句柄")
			}
		})
	}
}

// TestStreamServiceKeepsPinnedSourceBytesAfterWarmup 验证已固定的 source 表示在预热完成后仍返回原始文件字节。
func TestStreamServiceKeepsPinnedSourceBytesAfterWarmup(t *testing.T) {
	original := &testStreamReader{Reader: bytes.NewReader([]byte("original"))}
	service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
		ID: "media", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo, MIMEType: "video/mp4",
		SourceType: domain.SourceTypeLocal, RootPath: "/media", RelativePath: "clip.mp4",
	}}, fakeContentOpener{content: domain.OpenedContent{Reader: original, Size: 8, ModifiedAt: time.Unix(1, 0)}})
	if err != nil {
		t.Fatal(err)
	}
	// 缓存已经就绪也不影响已经固定的原始文件表示。
	service.SetFaststartCache(&stubFaststartCache{
		target: domain.StreamTarget{Representation: domain.StreamRepresentationFaststart, Fingerprint: "8-1000"},
		opened: domain.OpenedContent{
			Reader: &testStreamReader{Reader: bytes.NewReader([]byte("faststart-copy"))},
			Size:   14, ModifiedAt: time.Unix(50, 0),
		},
	})
	content, err := service.OpenSource(context.Background(), "media", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	defer content.Reader.Close()
	body, err := io.ReadAll(content.Reader)
	if err != nil || string(body) != "original" || content.Size != 8 {
		t.Fatalf("body=%q size=%d err=%v", body, content.Size, err)
	}
}

// TestStreamServiceFaststartMetadataFollowsOpenedRepresentation 验证两种表示各自使用自己的打开快照。
func TestStreamServiceFaststartMetadataFollowsOpenedRepresentation(t *testing.T) {
	sourceModified := time.Unix(1700000000, int64(987*time.Millisecond)).UTC()
	fingerprint := "8-1700000000987"
	newSnapshotService := func(t *testing.T) (*StreamService, *stubFaststartCache, *testStreamReader) {
		t.Helper()
		source := &testStreamReader{Reader: bytes.NewReader(bytes.Repeat([]byte{'o'}, 8))}
		service, err := NewStreamService(fakeStreamRepository{location: domain.StreamLocation{
			ID: "media_snapshot", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo, MIMEType: "video/mp4",
			SourceType: domain.SourceTypeLocal, RootPath: "/media", RelativePath: "clip.mp4",
		}}, fakeContentOpener{content: domain.OpenedContent{
			Reader: source, Size: 8, ModifiedAt: sourceModified,
		}})
		if err != nil {
			t.Fatal(err)
		}
		cache := &stubFaststartCache{opened: domain.OpenedContent{
			Reader: &testStreamReader{Reader: bytes.NewReader(bytes.Repeat([]byte{'c'}, 14))},
			Size:   14, ModifiedAt: sourceModified,
		}}
		service.SetFaststartCache(cache)
		return service, cache, source
	}
	wantModified := sourceModified.Truncate(time.Second)

	t.Run("原始文件", func(t *testing.T) {
		service, _, _ := newSnapshotService(t)
		content, err := service.OpenSource(context.Background(), "media_snapshot", "user_local")
		if err != nil {
			t.Fatal(err)
		}
		defer content.Reader.Close()
		wantETag := fmt.Sprintf(`W/"%x-%x"`, int64(8), wantModified.Unix())
		if content.Size != 8 || !content.ModifiedAt.Equal(wantModified) || content.ETag != wantETag {
			t.Fatalf("content=%#v want size=8 modified=%v etag=%s", content, wantModified, wantETag)
		}
	})

	t.Run("faststart 副本", func(t *testing.T) {
		service, cache, source := newSnapshotService(t)
		content, err := service.OpenFaststart(context.Background(), "media_snapshot", "user_local", fingerprint)
		if err != nil {
			t.Fatal(err)
		}
		defer content.Reader.Close()
		if !source.closed {
			t.Fatal("打开副本后必须释放核对指纹用的源文件句柄")
		}
		if cache.openedFingerprint != fingerprint {
			t.Fatalf("fingerprint=%q, want %q", cache.openedFingerprint, fingerprint)
		}
		wantETag := fmt.Sprintf(`W/"%x-%x"`, int64(14), wantModified.Unix())
		if content.Size != 14 || !content.ModifiedAt.Equal(wantModified) || content.ETag != wantETag {
			t.Fatalf("content=%#v want size=14 modified=%v etag=%s", content, wantModified, wantETag)
		}
		body, err := io.ReadAll(content.Reader)
		if err != nil || string(body) != strings.Repeat("c", 14) {
			t.Fatalf("body=%q err=%v", body, err)
		}
	})

	t.Run("副本缺失不回退原始文件", func(t *testing.T) {
		service, _, _ := newSnapshotService(t)
		service.SetFaststartCache(&stubFaststartCache{err: domain.ErrStreamCacheMiss})
		content, err := service.OpenFaststart(context.Background(), "media_snapshot", "user_local", fingerprint)
		if !errors.Is(err, domain.ErrStreamCacheMiss) {
			t.Fatalf("error = %v, want %v", err, domain.ErrStreamCacheMiss)
		}
		if content.Reader != nil {
			t.Fatalf("cache miss returned content = %#v", content)
		}
	})
}
