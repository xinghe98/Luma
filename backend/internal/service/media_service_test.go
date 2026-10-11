package service

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
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

func (r *fakeMediaRepository) GetImageDeleteTarget(context.Context, string, string) (domain.DeleteImageTarget, error) {
	return domain.DeleteImageTarget{}, domain.ErrMediaNotFound
}

func (r *fakeMediaRepository) DeleteImageRecord(context.Context, domain.DeleteImageTarget, time.Time) error {
	return domain.ErrMediaNotFound
}

func TestMediaServiceContinueWatchingCursorBindsUserAndFilters(t *testing.T) {
	played := time.UnixMilli(2000)
	repository := &fakeMediaRepository{items: []domain.Media{
		{ID: "b", LastPlayedAt: &played}, {ID: "a", LastPlayedAt: &played},
	}}
	service, err := NewMediaService(repository, countingThumbnailReader{}, &fakeRemover{}, fakeClock{})
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
	service, err := NewMediaService(repository, countingThumbnailReader{}, &fakeRemover{}, fakeClock{})
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
	service, err := NewMediaService(repository, countingThumbnailReader{data: []byte("jpeg")}, &fakeRemover{}, fakeClock{})
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
	service, err := NewMediaService(repository, countingThumbnailReader{}, &fakeRemover{}, fakeClock{})
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

func TestMediaServiceValidatesWatchStatusAndUsesCursorV4(t *testing.T) {
	repository := &fakeMediaRepository{}
	service, err := NewMediaService(repository, countingThumbnailReader{}, &fakeRemover{}, fakeClock{})
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
	if payload.Version != 4 {
		t.Fatalf("cursor version = %d", payload.Version)
	}
}

func TestEncodeMediaCursorUsesFileCreatedAt(t *testing.T) {
	created := time.UnixMilli(90)
	query := domain.MediaListQuery{UserID: "user_local", Sort: domain.MediaSortCreatedAt, Order: domain.SortDescending}
	cursor, err := encodeMediaCursor(query, domain.Media{
		ID: "media", DiscoveredAt: time.UnixMilli(10), FileCreatedAt: &created,
	})
	if err != nil {
		t.Fatal(err)
	}
	key, err := decodeMediaCursor(cursor, query)
	if err != nil {
		t.Fatal(err)
	}
	if key.IntValue != 90 || key.ID != "media" {
		t.Fatalf("key=%#v", key)
	}
}

func TestMediaServiceValidatesQueryAndBuildsStrongETag(t *testing.T) {
	repository := &fakeMediaRepository{}
	service, err := NewMediaService(repository, countingThumbnailReader{data: []byte("image")}, &fakeRemover{}, fakeClock{})
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
	service, err := NewMediaService(repository, countingThumbnailReader{data: []byte("image"), calls: &reads}, &fakeRemover{}, fakeClock{})
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

// fakeDeleteRepository 是删除用例的最小假仓储：target 是固定返回的删除定位，
// markCalls 记录 DeleteImageRecord 被调用次数，repoErr 可选地注入查询失败。
type fakeDeleteRepository struct {
	fakeMediaRepository
	target    domain.DeleteImageTarget
	targetErr error
	markCalls int
}

func (r *fakeDeleteRepository) GetImageDeleteTarget(context.Context, string, string) (domain.DeleteImageTarget, error) {
	if r.targetErr != nil {
		return domain.DeleteImageTarget{}, r.targetErr
	}
	return r.target, nil
}

func (r *fakeDeleteRepository) DeleteImageRecord(context.Context, domain.DeleteImageTarget, time.Time) error {
	r.markCalls++
	return nil
}

// fakeRemover 是可预测的文件删除替身；err 非空时删除失败并记录调用次数。
type fakeRemover struct {
	err   error
	calls int
}

func (f *fakeRemover) RemoveSourceFile(context.Context, string, string) error {
	f.calls++
	return f.err
}

func newDeleteService(t *testing.T, repo *fakeDeleteRepository, remover *fakeRemover) *MediaService {
	t.Helper()
	service, err := NewMediaService(repo, countingThumbnailReader{}, remover, fakeClock{})
	if err != nil {
		t.Fatal(err)
	}
	return service
}

// TestDeleteImageRemovesFileThenIndex 验证成功删除先落盘再清索引。
func TestDeleteImageRemovesFileThenIndex(t *testing.T) {
	repo := &fakeDeleteRepository{target: domain.DeleteImageTarget{
		MediaID: "img1", SourceID: "src", RootPath: "/root", RelativePath: "a.png",
	}}
	remover := &fakeRemover{}
	service := newDeleteService(t, repo, remover)
	if err := service.DeleteImage(context.Background(), "img1", "user_local"); err != nil {
		t.Fatal(err)
	}
	if remover.calls != 1 || repo.markCalls != 1 {
		t.Fatalf("文件删除=%d 索引删除=%d，期望各一次", remover.calls, repo.markCalls)
	}
}

// TestDeleteImageFileFailureKeepsIndex 验证文件删除失败时索引不被触碰。
func TestDeleteImageFileFailureKeepsIndex(t *testing.T) {
	repo := &fakeDeleteRepository{target: domain.DeleteImageTarget{
		MediaID: "img1", SourceID: "src", RootPath: "/root", RelativePath: "a.png",
	}}
	remover := &fakeRemover{err: errors.New("disk full")}
	service := newDeleteService(t, repo, remover)
	err := service.DeleteImage(context.Background(), "img1", "user_local")
	if err == nil || repo.markCalls != 0 {
		t.Fatalf("应返回错误且不触碰索引: err=%v markCalls=%d", err, repo.markCalls)
	}
}

// TestDeleteImagePropagatesAuthorizationError 验证未授权错误原样上抛且不落盘。
func TestDeleteImagePropagatesAuthorizationError(t *testing.T) {
	repo := &fakeDeleteRepository{targetErr: domain.ErrMediaNotFound}
	remover := &fakeRemover{}
	service := newDeleteService(t, repo, remover)
	err := service.DeleteImage(context.Background(), "img1", "user_no_grant")
	if !errors.Is(err, domain.ErrMediaNotFound) || remover.calls != 0 || repo.markCalls != 0 {
		t.Fatalf("未授权应返回 notfound 且无任何删除: err=%v calls=%d mark=%d", err, remover.calls, repo.markCalls)
	}
}

// TestDeleteImageRejectsNonImage 验证非图片媒体错误冒泡且不删除。
func TestDeleteImageRejectsNonImage(t *testing.T) {
	repo := &fakeDeleteRepository{targetErr: fmt.Errorf("%w: 仅支持删除图片媒体", domain.ErrInvalidRequest)}
	service := newDeleteService(t, repo, &fakeRemover{})
	err := service.DeleteImage(context.Background(), "vid1", "user_local")
	if !errors.Is(err, domain.ErrInvalidRequest) {
		t.Fatalf("应返回 INVALID_REQUEST: %v", err)
	}
}

// TestDeleteImageRequiresAllDependencies 验证构造即拒绝缺失的删除依赖。
func TestDeleteImageRequiresAllDependencies(t *testing.T) {
	if _, err := NewMediaService(&fakeDeleteRepository{}, countingThumbnailReader{}, nil, fakeClock{}); err == nil {
		t.Fatal("缺少文件删除依赖应拒绝构造")
	}
}
