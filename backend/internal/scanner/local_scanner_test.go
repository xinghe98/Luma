package scanner

import (
	"context"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// memorySource 为 Scanner 测试提供内存文件条目和内容。
type memorySource struct {
	// entries 是 Walk 返回的文件列表。
	entries []storage.FileEntry
	// content 是 Open 返回的文件内容。
	content map[string]string
}

// Walk 依次访问全部内存文件条目。
func (s memorySource) Walk(ctx context.Context, visit func(storage.FileEntry) error) error {
	for _, entry := range s.entries {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := visit(entry); err != nil {
			return err
		}
	}
	return nil
}

// Open 返回支持读取和定位的内存文件。
func (s memorySource) Open(_ context.Context, path string) (storage.ReadSeekCloser, error) {
	return &memoryFile{Reader: *strings.NewReader(s.content[path])}, nil
}

// Health 返回固定在线状态。
func (memorySource) Health(context.Context) (storage.SourceHealth, error) {
	return storage.SourceHealth{Online: true}, nil
}

// memoryFile 为 strings.Reader 补充空关闭方法。
type memoryFile struct {
	// Reader 提供内存文件的读取和定位能力。
	strings.Reader
}

// Close 模拟关闭内存文件。
func (*memoryFile) Close() error { return nil }

// TestLocalScannerFiltersAndClassifiesMedia 验证扩展名过滤和媒体类型识别。
func TestLocalScannerFiltersAndClassifiesMedia(t *testing.T) {
	scanner, err := NewLocalScanner([]string{"mp4", "jpg"})
	if err != nil {
		t.Fatal(err)
	}
	source := memorySource{entries: []storage.FileEntry{
		{RelativePath: "视频.MP4", Filename: "视频.MP4", ModifiedAt: time.Unix(1, 0)},
		{RelativePath: "cover.jpg", Filename: "cover.jpg", ModifiedAt: time.Unix(1, 0)},
		{RelativePath: "._broken.mp4", Filename: "._broken.mp4", ModifiedAt: time.Unix(1, 0)},
		{RelativePath: "notes.txt", Filename: "notes.txt", ModifiedAt: time.Unix(1, 0)},
	}}
	var files []domain.DiscoveredFile
	if err := scanner.Scan(context.Background(), source, func(file domain.DiscoveredFile) error {
		files = append(files, file)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if len(files) != 2 || files[0].MediaType != domain.MediaTypeVideo || files[1].MediaType != domain.MediaTypeImage {
		t.Fatalf("扫描结果不符合预期: %#v", files)
	}
}

// TestSHA256QuickHasherUsesHeadAndTail 验证快速指纹能够区分尾部内容变化。
func TestSHA256QuickHasherUsesHeadAndTail(t *testing.T) {
	prefix := strings.Repeat("a", int(quickHashBlockSize))
	first := prefix + strings.Repeat("b", int(quickHashBlockSize))
	second := prefix + strings.Repeat("c", int(quickHashBlockSize))
	hasher := SHA256QuickHasher{}
	hashA, err := hasher.Hash(context.Background(), memorySource{content: map[string]string{"a": first}}, "a", int64(len(first)))
	if err != nil {
		t.Fatal(err)
	}
	hashB, err := hasher.Hash(context.Background(), memorySource{content: map[string]string{"b": second}}, "b", int64(len(second)))
	if err != nil {
		t.Fatal(err)
	}
	if hashA == hashB {
		t.Fatal("文件尾部变化后快速指纹不应相同")
	}
}

// TestMemoryFileImplementsReadSeekCloser 在编译期验证测试文件接口。
func TestMemoryFileImplementsReadSeekCloser(t *testing.T) {
	var _ storage.ReadSeekCloser = &memoryFile{}
	var _ io.ReadSeeker = &memoryFile{}
}
