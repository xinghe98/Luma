package service

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type fakeMediaRepository struct {
	// media 是详情查询返回的媒体。
	media domain.Media
	// items 是列表查询返回的媒体条目。
	items []domain.Media
	// count 是总数查询返回的媒体条目数量。
	count int
	// query 记录最近一次列表查询参数。
	query domain.MediaListQuery
	// asset 是缩略图查询返回的资源。
	asset domain.ThumbnailAsset
	// assetErr 是缩略图查询返回的错误。
	assetErr error
	// readCalls 指向缩略图读取次数计数器。
	readCalls *int
	variant   string
}

func (r *fakeMediaRepository) List(_ context.Context, query domain.MediaListQuery) ([]domain.Media, error) {
	r.query = query
	return r.items, nil
}
func (r *fakeMediaRepository) Count(_ context.Context, query domain.MediaListQuery) (int, error) {
	r.query = query
	return r.count, nil
}
func (r *fakeMediaRepository) Get(context.Context, string, string) (domain.Media, error) {
	if r.media.ID != "" {
		return r.media, nil
	}
	return domain.Media{}, domain.ErrMediaNotFound
}

func TestMediaServiceContinueWatchingCursorBindsUserAndFilters(t *testing.T) {
	played := time.UnixMilli(2000)
	repository := &fakeMediaRepository{items: []domain.Media{
		{ID: "b", LastPlayedAt: &played}, {ID: "a", LastPlayedAt: &played},
	}}
	service, err := NewMediaService(repository, countingThumbnailReader{})
	if err != nil {
		t.Fatal(err)
	}
	page, err := service.List(context.Background(), domain.MediaListRequest{ContinueWatching: true, Limit: 1}, "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if page.NextCursor == "" || repository.query.Sort != domain.MediaSortLastPlayedAt || repository.query.Order != domain.SortDescending || repository.query.MediaType != domain.MediaTypeVideo {
		t.Fatalf("page=%#v query=%#v", page, repository.query)
	}
	if _, err := service.List(context.Background(), domain.MediaListRequest{ContinueWatching: true, Limit: 1, Cursor: page.NextCursor}, "other_user"); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("cross-user cursor error=%v", err)
	}
	favorite := true
	if _, err := service.List(context.Background(), domain.MediaListRequest{ContinueWatching: true, Favorite: &favorite, Limit: 1, Cursor: page.NextCursor}, "user_local"); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("cross-filter cursor error=%v", err)
	}
}

func TestMediaServiceCountUsesVisibleQueryWithoutCursor(t *testing.T) {
	repository := &fakeMediaRepository{count: 42}
	service, err := NewMediaService(repository, countingThumbnailReader{})
	if err != nil {
		t.Fatal(err)
	}
	count, err := service.Count(context.Background(), domain.MediaListRequest{MediaType: domain.MediaTypeImage, Cursor: "ignored"}, "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if count != 42 || repository.query.After != nil || repository.query.MediaType != domain.MediaTypeImage {
		t.Fatalf("count=%d query=%#v", count, repository.query)
	}
}
func (r *fakeMediaRepository) GetThumbnail(_ context.Context, _, variant, _ string) (domain.ThumbnailAsset, error) {
	r.variant = variant
	if r.assetErr != nil {
		return domain.ThumbnailAsset{}, r.assetErr
	}
	if r.asset.StorageKey != "" || r.asset.ContentSHA256 != "" {
		return r.asset, nil
	}
	return domain.ThumbnailAsset{StorageKey: "thumbnails/media/cover.jpg", MIMEType: "image/jpeg"}, nil
}

func TestMediaServiceThumbnailValidatesAndForwardsVariant(t *testing.T) {
	repository := &fakeMediaRepository{}
	service, err := NewMediaService(repository, countingThumbnailReader{data: []byte("jpeg")})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Thumbnail(context.Background(), "media", "wide", "", "user_local"); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("invalid variant error=%v", err)
	}
	if _, err := service.Thumbnail(context.Background(), "media", domain.ThumbnailVariantCard, "", "user_local"); err != nil {
		t.Fatal(err)
	}
	if repository.variant != domain.ThumbnailVariantCard {
		t.Fatalf("variant=%q", repository.variant)
	}
}

type countingThumbnailReader struct {
	// data 是读取时返回的缩略图数据。
	data []byte
	// calls 指向读取次数计数器。
	calls *int
	// err 是读取时返回的错误。
	err error
}

func (r countingThumbnailReader) Read(string) ([]byte, error) {
	if r.calls != nil {
		*r.calls++
	}
	if r.err != nil {
		return nil, r.err
	}
	return r.data, nil
}

func TestMediaServiceCursorCannotBeReusedAcrossFilters(t *testing.T) {
	repository := &fakeMediaRepository{items: []domain.Media{
		{ID: "c", Filename: "c.mp4", DiscoveredAt: time.UnixMilli(3)},
		{ID: "b", Filename: "b.mp4", DiscoveredAt: time.UnixMilli(2)},
		{ID: "a", Filename: "a.mp4", DiscoveredAt: time.UnixMilli(1)},
	}}
	service, err := NewMediaService(repository, countingThumbnailReader{})
	if err != nil {
		t.Fatal(err)
	}
	page, err := service.List(context.Background(), domain.MediaListRequest{Limit: 2}, "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 2 || page.NextCursor == "" || repository.query.Limit != 3 {
		t.Fatalf("unexpected page: %#v query=%#v", page, repository.query)
	}
	if _, err := service.List(context.Background(), domain.MediaListRequest{Limit: 2, Cursor: page.NextCursor}, "user_local"); err != nil {
		t.Fatal(err)
	}
	if repository.query.After == nil || repository.query.After.ID != "b" {
		t.Fatalf("decoded cursor = %#v", repository.query.After)
	}
	_, err = service.List(context.Background(), domain.MediaListRequest{Limit: 2, MediaType: domain.MediaTypeVideo, Cursor: page.NextCursor}, "user_local")
	if !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("error = %v", err)
	}
	_, err = service.List(context.Background(), domain.MediaListRequest{Limit: 2, WatchStatus: domain.WatchStatusUnwatched, Cursor: page.NextCursor}, "user_local")
	if !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("watch status cursor error = %v", err)
	}
}

func TestMediaServiceValidatesWatchStatusAndUsesCursorV3(t *testing.T) {
	repository := &fakeMediaRepository{}
	service, err := NewMediaService(repository, countingThumbnailReader{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.List(context.Background(), domain.MediaListRequest{WatchStatus: "unknown"}, "user_local"); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("invalid watch status error = %v", err)
	}
	if _, err := service.List(context.Background(), domain.MediaListRequest{WatchStatus: " watching "}, "user_local"); err != nil {
		t.Fatal(err)
	}
	if repository.query.WatchStatus != domain.WatchStatusWatching {
		t.Fatalf("watch status = %q", repository.query.WatchStatus)
	}
	cursor, err := encodeMediaCursor(repository.query, domain.Media{ID: "media", DiscoveredAt: time.UnixMilli(1)})
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		t.Fatal(err)
	}
	var payload mediaCursor
	if err := json.Unmarshal(decoded, &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Version != 3 {
		t.Fatalf("cursor version = %d", payload.Version)
	}
}

func TestMediaServiceValidatesQueryAndBuildsStrongETag(t *testing.T) {
	repository := &fakeMediaRepository{}
	service, err := NewMediaService(repository, countingThumbnailReader{data: []byte("image")})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.List(context.Background(), domain.MediaListRequest{Limit: 101}, "user_local"); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("error = %v", err)
	}
	if _, err := service.List(context.Background(), domain.MediaListRequest{Sort: domain.MediaSortLastPlayedAt}, "user_local"); !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("internal sort error = %v", err)
	}
	content, err := service.Thumbnail(context.Background(), "media", "", "", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if content.ETag == "" || content.MIMEType != "image/jpeg" || string(content.Data) != "image" || content.NotModified {
		t.Fatalf("unexpected content: %#v", content)
	}
}

func TestMediaServiceThumbnailNotModifiedSkipsRead(t *testing.T) {
	var reads int
	hash := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	repository := &fakeMediaRepository{asset: domain.ThumbnailAsset{
		StorageKey: "thumbnails/media/cover.jpg", MIMEType: "image/jpeg", ContentSHA256: hash,
	}}
	service, err := NewMediaService(repository, countingThumbnailReader{data: []byte("image"), calls: &reads})
	if err != nil {
		t.Fatal(err)
	}
	content, err := service.Thumbnail(context.Background(), "media", "", `"`+hash+`"`, "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if !content.NotModified || content.ETag != `"`+hash+`"` || reads != 0 {
		t.Fatalf("content=%#v reads=%d", content, reads)
	}
}
