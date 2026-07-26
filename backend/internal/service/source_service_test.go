package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// fakeRootValidator 为媒体源服务测试提供可控的路径校验结果。
type fakeRootValidator struct {
	// result 是测试替身返回的规范路径。
	result string
	// err 是测试替身返回的错误。
	err error
}

// ValidateSourceRoot 返回预设的路径校验结果。
func (v fakeRootValidator) ValidateSourceRoot(string) (string, error) {
	return v.result, v.err
}

// fakeSourceRepository 为媒体源服务测试提供最小内存持久化替身。
type fakeSourceRepository struct{}

// List 返回空媒体源集合。
func (fakeSourceRepository) List(context.Context) ([]domain.Source, error) { return nil, nil }

// Get 返回媒体源不存在错误。
func (fakeSourceRepository) Get(context.Context, string) (domain.Source, error) {
	return domain.Source{}, domain.ErrSourceNotFound
}

// Create 模拟创建媒体源成功。
func (fakeSourceRepository) Create(context.Context, domain.Source) error { return nil }

// Update 模拟更新媒体源成功。
func (fakeSourceRepository) Update(context.Context, domain.Source) error { return nil }

// SetStatus 模拟更新媒体源状态成功。
func (fakeSourceRepository) SetStatus(context.Context, string, string, time.Time) error { return nil }

// SoftDelete 模拟软删除媒体源成功。
func (fakeSourceRepository) SoftDelete(context.Context, string, time.Time) error { return nil }

// fakeActiveScanChecker 为测试提供可控的活跃扫描检查结果。
type fakeActiveScanChecker struct {
	// active 表示是否存在活跃扫描。
	active bool
	// err 是检查返回的错误。
	err error
}

// fakeIndexedMediaChecker 为根目录变更测试返回可控的索引状态。
type fakeIndexedMediaChecker struct {
	hasMedia bool
	err      error
}

// HasIndexedMedia 返回预设的来源索引状态。
func (c fakeIndexedMediaChecker) HasIndexedMedia(context.Context, string) (bool, error) {
	return c.hasMedia, c.err
}

// HasActiveJob 返回预设的活跃扫描检查结果。
func (c fakeActiveScanChecker) HasActiveJob(context.Context, string) (bool, error) {
	return c.active, c.err
}

// fakeIDGenerator 返回固定业务标识。
type fakeIDGenerator struct{}

// New 返回带测试前缀的固定标识。
func (fakeIDGenerator) New(prefix string) (string, error) { return prefix + "_test", nil }

// fakeClock 返回固定 UTC 时间。
type fakeClock struct{}

// Now 返回 Unix Epoch。
func (fakeClock) Now() time.Time { return time.Unix(0, 0).UTC() }

// newTestSourceService 创建注入全部测试替身的媒体源服务。
func newTestSourceService(t *testing.T, validator SourceRootValidator) *SourceService {
	t.Helper()
	service, err := NewSourceService(
		fakeSourceRepository{}, validator, fakeActiveScanChecker{}, fakeIndexedMediaChecker{}, fakeIDGenerator{}, fakeClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	return service
}

// TestSourceServiceRejectsRootChangeWithIndexedMedia 验证旧媒体 ID 不会因来源换根而指向新目录。
func TestSourceServiceRejectsRootChangeWithIndexedMedia(t *testing.T) {
	repository := &updatableSourceRepository{source: domain.Source{ID: "source_test", RootPath: "/old"}}
	service, err := NewSourceService(
		repository,
		fakeRootValidator{result: "/new"},
		fakeActiveScanChecker{},
		fakeIndexedMediaChecker{hasMedia: true},
		fakeIDGenerator{},
		fakeClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	root := "/new"
	_, err = service.Update(context.Background(), domain.UpdateSourceCommand{ID: "source_test", RootPath: &root})
	if !errors.Is(err, domain.ErrSourceConflict) {
		t.Fatalf("error = %v, want source conflict", err)
	}
	if repository.updated {
		t.Fatal("已有媒体索引时不应保存新根目录")
	}
}

// updatableSourceRepository 保存单个来源并记录是否执行更新。
type updatableSourceRepository struct {
	source  domain.Source
	updated bool
}

// List 返回测试来源。
func (r *updatableSourceRepository) List(context.Context) ([]domain.Source, error) {
	return []domain.Source{r.source}, nil
}

// Get 返回测试来源。
func (r *updatableSourceRepository) Get(context.Context, string) (domain.Source, error) {
	return r.source, nil
}

// Create 模拟创建成功。
func (r *updatableSourceRepository) Create(context.Context, domain.Source) error { return nil }

// Update 记录测试更新。
func (r *updatableSourceRepository) Update(_ context.Context, source domain.Source) error {
	r.source = source
	r.updated = true
	return nil
}

// SetStatus 模拟状态更新成功。
func (r *updatableSourceRepository) SetStatus(context.Context, string, string, time.Time) error {
	return nil
}

// SoftDelete 模拟软删除成功。
func (r *updatableSourceRepository) SoftDelete(context.Context, string, time.Time) error { return nil }

// TestSourceServiceUsesInjectedRootValidator 验证媒体源服务使用注入的路径校验器。
func TestSourceServiceUsesInjectedRootValidator(t *testing.T) {
	service := newTestSourceService(t, fakeRootValidator{result: "/canonical/media"})
	root, err := service.ValidateRoot(context.Background(), "/input/media")
	if err != nil {
		t.Fatal(err)
	}
	if root != "/canonical/media" {
		t.Fatalf("root = %q", root)
	}
}

// TestSourceServiceHonorsCancellationBeforeFilesystemWork 验证取消后不再执行路径检查。
func TestSourceServiceHonorsCancellationBeforeFilesystemWork(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	service := newTestSourceService(t, fakeRootValidator{err: errors.New("must not be called")})
	if _, err := service.ValidateRoot(ctx, "/media"); !errors.Is(err, context.Canceled) {
		t.Fatalf("error = %v, want context cancellation", err)
	}
}
