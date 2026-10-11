package service

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/platform"
	dbrepo "github.com/xinghe98/Luma/backend/internal/repository/sqlite"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// 本文件职责：图片上传用例的回归测试。
// 使用真实迁移的临时 SQLite 与临时目录媒体源，覆盖授权、同名保留、
// 非法内容、超限、来源状态、取消与索引可见性。

type uploadFixture struct {
	sources    *dbrepo.SourceRepository
	access     *dbrepo.AccessRepository
	scans      *dbrepo.ScanRepository
	processing *dbrepo.ProcessingRepository
	factory    *storage.LocalFactory
	service    *UploadService
	notifier   *countingNotifier
	db         *sql.DB
	root       string
	now        time.Time
}

type countingNotifier struct{ count int }

func (n *countingNotifier) Notify() { n.count++ }

func newUploadFixture(t *testing.T) *uploadFixture {
	t.Helper()
	ctx := context.Background()
	dir := t.TempDir()
	db, err := dbrepo.Open(ctx, config.DatabaseConfig{Path: filepath.Join(dir, "media.db"), BusyTimeoutMS: 1000, WAL: true})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	sources, err := dbrepo.NewSourceRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	access, err := dbrepo.NewAccessRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	scans, err := dbrepo.NewScanRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	processing, err := dbrepo.NewProcessingRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	factory, err := storage.NewLocalFactory(platform.OSFileIdentifier{}, platform.RealClock{})
	if err != nil {
		t.Fatal(err)
	}
	notifier := &countingNotifier{}
	ids := platform.SecureIDGenerator{}
	clock := platform.RealClock{}
	service, err := NewUploadService(sources, factory, scans, notifier, ids, clock)
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(dir, "media-root")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	return &uploadFixture{
		sources: sources, access: access, scans: scans, processing: processing,
		factory: factory, service: service, notifier: notifier, root: root,
		db: db, now: time.Unix(200, 0).UTC(),
	}
}

// createUploadSource 在临时数据库创建媒体源并按需授权给指定用户。
func (f *uploadFixture) createUploadSource(t *testing.T, id, userID string, grant bool, enabled bool, status string) domain.Source {
	t.Helper()
	sourceRoot := filepath.Join(f.root, id)
	if err := os.MkdirAll(sourceRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	source := domain.Source{
		ID: id, Name: "上传测试", Type: domain.SourceTypeLocal, RootPath: filepath.Join(f.root, id),
		Enabled: enabled, Status: status, CreatedAt: f.now, UpdatedAt: f.now,
	}
	if err := f.sources.Create(context.Background(), source); err != nil {
		t.Fatal(err)
	}
	if grant {
		// 同一用户多来源时忽略已存在账号；CreateUser 对重复 username 返回唯一约束错误。
		if _, err := f.access.GetUser(context.Background(), userID); err != nil {
			if err := f.access.CreateUser(context.Background(), domain.User{
				ID: userID, Name: "测试用户", Username: userID, Role: domain.RoleMember, Enabled: true,
				CreatedAt: f.now, UpdatedAt: f.now,
			}); err != nil {
				t.Fatal(err)
			}
		}
		if err := f.access.GrantSource(context.Background(), userID, id, f.now); err != nil {
			t.Fatal(err)
		}
	}
	return source
}

// uploadImage 执行一次最小 PNG 上传。
func uploadImage(t *testing.T, f *uploadFixture, sourceID, userID, filename string) domain.UploadResult {
	t.Helper()
	png := append([]byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, make([]byte, 32)...)
	result, err := f.service.Upload(context.Background(), sourceID, userID, domain.UploadedImage{
		Reader: io.NopCloser(bytes.NewReader(png)), Filename: filename,
	})
	if err != nil {
		t.Fatal(err)
	}
	return result
}

// countMediaByFilename 统计媒体索引中指定文件名的可见行数。
func countMediaByFilename(t *testing.T, f *uploadFixture, sourceID, filename string) int {
	t.Helper()
	var count int
	if err := f.db.QueryRow(`SELECT COUNT(*) FROM media_items WHERE source_id = ? AND filename = ?`,
		sourceID, filename).Scan(&count); err != nil {
		t.Fatal(err)
	}
	return count
}

func TestUploadRequiresGrant(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", false, true, domain.SourceStatusOnline)
	png := append([]byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, make([]byte, 32)...)
	_, err := f.service.Upload(context.Background(), "source_a", "user_a", domain.UploadedImage{
		Reader: io.NopCloser(bytes.NewReader(png)), Filename: "a.png",
	})
	if !errors.Is(err, domain.ErrSourceNotFound) {
		t.Fatalf("ungranted upload error = %v", err)
	}
}

func TestUploadPersistsAndIndexesImage(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	result := uploadImage(t, f, "source_a", "user_a", "photo.png")
	if result.MediaID == "" || result.Filename != "photo.png" {
		t.Fatalf("result=%#v", result)
	}
	if _, err := os.Stat(filepath.Join(f.root, "source_a", "photo.png")); err != nil {
		t.Fatalf("saved file missing: %v", err)
	}
	if count := countMediaByFilename(t, f, "source_a", "photo.png"); count != 1 {
		t.Fatalf("indexed rows=%d", count)
	}
	if f.notifier.count == 0 {
		t.Fatal("probe signal not notified")
	}
	var pending int
	if err := f.db.QueryRow(`SELECT COUNT(*) FROM jobs WHERE job_type = 'probe_media' AND entity_id = ?`,
		result.MediaID).Scan(&pending); err != nil {
		t.Fatal(err)
	}
	if pending != 1 {
		t.Fatalf("probe jobs=%d", pending)
	}
}

func TestUploadKeepsBothFilesForSameName(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	first := uploadImage(t, f, "source_a", "user_a", "same.png")
	second := uploadImage(t, f, "source_a", "user_a", "same.png")
	if first.MediaID == second.MediaID || first.Filename == second.Filename {
		t.Fatalf("same-name results=%#v %#v", first, second)
	}
	for _, name := range []string{"same.png", second.Filename} {
		if _, err := os.Stat(filepath.Join(f.root, "source_a", name)); err != nil {
			t.Fatalf("%s missing: %v", name, err)
		}
	}
	if count := countMediaByFilename(t, f, "source_a", second.Filename); count != 1 {
		t.Fatalf("indexed rows=%d", count)
	}
}

func TestUploadRejectsInvalidBytesWithoutOrphans(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	garbage := bytes.Repeat([]byte("not-an-image"), 64)
	_, err := f.service.Upload(context.Background(), "source_a", "user_a", domain.UploadedImage{
		Reader: io.NopCloser(bytes.NewReader(garbage)), Filename: "bad.png",
	})
	if !errors.Is(err, domain.ErrUploadUnsupportedImage) {
		t.Fatalf("invalid bytes error = %v", err)
	}
	entries, err := os.ReadDir(filepath.Join(f.root, "source_a"))
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".luma-upload-") || entry.Name() == "bad.png" {
			t.Fatalf("orphan file left: %s", entry.Name())
		}
	}
}

func TestUploadRejectsOversizedBody(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	head := append([]byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, make([]byte, 24)...)
	body := io.MultiReader(bytes.NewReader(head), io.LimitReader(&infiniteZeros{}, domain.MaxUploadImageBytes))
	_, err := f.service.Upload(context.Background(), "source_a", "user_a", domain.UploadedImage{
		Reader: io.NopCloser(body), Filename: "big.png",
	})
	if !errors.Is(err, domain.ErrUploadTooLarge) {
		t.Fatalf("oversize error = %v", err)
	}
}

type infiniteZeros struct{}

func (*infiniteZeros) Read(p []byte) (int, error) { return len(p), nil }

func TestUploadRejectsDisabledAndOfflineSources(t *testing.T) {
	f := newUploadFixture(t)
	png := append([]byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, make([]byte, 32)...)
	f.createUploadSource(t, "source_off", "user_a", true, false, domain.SourceStatusDisabled)
	_, err := f.service.Upload(context.Background(), "source_off", "user_a", domain.UploadedImage{
		Reader: io.NopCloser(bytes.NewReader(png)), Filename: "a.png",
	})
	if !errors.Is(err, domain.ErrSourceOffline) {
		t.Fatalf("disabled error = %v", err)
	}
	f.createUploadSource(t, "source_offline", "user_a", true, true, domain.SourceStatusOffline)
	_, err = f.service.Upload(context.Background(), "source_offline", "user_a", domain.UploadedImage{
		Reader: io.NopCloser(bytes.NewReader(png)), Filename: "a.png",
	})
	if !errors.Is(err, domain.ErrSourceOffline) {
		t.Fatalf("offline error = %v", err)
	}
}

func TestUploadClientCancelLeavesNoPartialFile(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	ctx, cancel := context.WithCancel(context.Background())
	head := append([]byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}, make([]byte, 24)...)
	reader := &cancelAfter{reader: io.MultiReader(bytes.NewReader(head), io.LimitReader(&infiniteZeros{}, 1<<20)), cancel: cancel, after: len(head)}
	_, err := f.service.Upload(ctx, "source_a", "user_a", domain.UploadedImage{
		Reader: io.NopCloser(reader), Filename: "partial.png",
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("cancel error = %v", err)
	}
	entries, _ := os.ReadDir(filepath.Join(f.root, "source_a"))
	for _, entry := range entries {
		if entry.Name() == "partial.png" || strings.HasPrefix(entry.Name(), ".luma-upload-") {
			t.Fatalf("partial file left: %s", entry.Name())
		}
	}
}

type cancelAfter struct {
	reader io.Reader
	cancel context.CancelFunc
	after  int
	read   int
}

func (r *cancelAfter) Read(p []byte) (int, error) {
	if r.read >= r.after {
		r.cancel()
		return 0, fmt.Errorf("stopped")
	}
	n, err := r.reader.Read(p)
	r.read += n
	return n, err
}

func TestUploadMissingImageIsNotLeftInIndex(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	// 扩展名通过粗筛但内容与声明不符：webp 声明 png 扩展名会被拒绝。
	webp := append(append(append([]byte("RIFF"), 0, 0, 0, 0), []byte("WEBP")...), make([]byte, 20)...)
	_, err := f.service.Upload(context.Background(), "source_a", "user_a", domain.UploadedImage{
		Reader: io.NopCloser(bytes.NewReader(webp)), Filename: "fake.png",
	})
	if !errors.Is(err, domain.ErrUploadUnsupportedImage) {
		t.Fatalf("mismatched image error = %v", err)
	}
	entries, _ := os.ReadDir(filepath.Join(f.root, "source_a"))
	for _, entry := range entries {
		if entry.Name() == "fake.png" {
			t.Fatalf("rejected upload published file %s", entry.Name())
		}
	}
}

// TestUploadSurvivesConcurrentScanMissing 验证上传落在运行中扫描时不会被误标 missing。
// IndexUpload 在同一事务内读取运行中扫描 ID 并作为 last_seen_scan_id，
// CompleteJob 因此把它视为本轮扫描已见证；扫描结束后的下一轮完整扫描会正常 reconcile。
func TestUploadSurvivesConcurrentScanMissing(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	scanJob := domain.ScanJob{ID: "scan_real", SourceID: "source_a", CreatedAt: f.now, UpdatedAt: f.now}
	if err := f.scans.CreateJob(context.Background(), scanJob); err != nil {
		t.Fatal(err)
	}
	claimed, err := f.scans.ClaimNextJob(context.Background(), "worker_test", f.now)
	if err != nil {
		t.Fatal(err)
	}
	// 上传发生在扫描 running 期间：last_seen 记为当前扫描 ID。
	result := uploadImage(t, f, "source_a", "user_a", "upload.png")
	scannedFile := domain.DiscoveredFile{
		RelativePath: "scanned.mp4", Filename: "scanned.mp4", MediaType: domain.MediaTypeVideo,
		Size: 10, ModifiedAt: f.now,
	}
	if _, err := f.scans.ReconcileFile(context.Background(), claimed.ID, "source_a", "media_scan", scannedFile, f.now); err != nil {
		t.Fatal(err)
	}
	if err := f.scans.CompleteJob(context.Background(), claimed.ID, "source_a", f.now); err != nil {
		t.Fatal(err)
	}
	var status string
	if err := f.db.QueryRow(`SELECT status FROM media_items WHERE id = ?`, result.MediaID).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status == domain.MediaStatusMissing {
		t.Fatal("uploaded media marked missing after full scan")
	}
}

// TestUploadMarkedMissingWhenDeletedBeforeNextScan 验证扫描结束后上传、随后被删除的文件
// 会在下一轮完整扫描中正常标记 missing：last_seen 为 NULL 时与既有扫描水位一致。
func TestUploadMarkedMissingWhenDeletedBeforeNextScan(t *testing.T) {
	f := newUploadFixture(t)
	f.createUploadSource(t, "source_a", "user_a", true, true, domain.SourceStatusOnline)
	result := uploadImage(t, f, "source_a", "user_a", "upload.png")
	// 无运行中扫描：last_seen_scan_id 为 NULL；删除落盘文件后下一轮完整扫描应标 missing。
	if err := os.Remove(filepath.Join(f.root, "source_a", result.Filename)); err != nil {
		t.Fatal(err)
	}
	scanJob := domain.ScanJob{ID: "scan_next", SourceID: "source_a", CreatedAt: f.now, UpdatedAt: f.now}
	if err := f.scans.CreateJob(context.Background(), scanJob); err != nil {
		t.Fatal(err)
	}
	claimed, err := f.scans.ClaimNextJob(context.Background(), "worker_test", f.now)
	if err != nil {
		t.Fatal(err)
	}
	// 本轮扫描没有发现任何文件，正常收尾。
	if err := f.scans.CompleteJob(context.Background(), claimed.ID, "source_a", f.now); err != nil {
		t.Fatal(err)
	}
	var status string
	if err := f.db.QueryRow(`SELECT status FROM media_items WHERE id = ?`, result.MediaID).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != domain.MediaStatusMissing {
		t.Fatalf("deleted uploaded media status = %q, want missing", status)
	}
}
