package media

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type fakeCommandRunner struct {
	// name 记录执行的命令名称。
	name string
	// args 记录执行命令时传入的参数。
	args []string
	// output 是命令返回的测试输出。
	output []byte
}

type replacingCommandRunner struct {
	path       string
	replaceErr error
}

// Run 在外部工具执行窗口内替换输入路径，以验证执行后身份复核。
func (r *replacingCommandRunner) Run(context.Context, string, ...string) ([]byte, error) {
	if err := os.Remove(r.path); err != nil {
		r.replaceErr = err
		return []byte(`{"format":{"format_name":"mp4"}}`), nil
	}
	r.replaceErr = os.WriteFile(r.path, []byte("replacement"), 0o600)
	return []byte(`{"format":{"format_name":"mp4"}}`), nil
}

func (r *fakeCommandRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	r.name = name
	r.args = append([]string(nil), args...)
	return append([]byte(nil), r.output...), nil
}

func TestResolveInputPath(t *testing.T) {
	root := t.TempDir()
	directory := filepath.Join(root, "nested")
	if err := os.Mkdir(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(directory, "clip.mp4")
	if err := os.WriteFile(file, []byte("media"), 0o600); err != nil {
		t.Fatal(err)
	}

	got, err := openInputPath(domain.MediaInput{RootPath: root, RelativePath: "nested/clip.mp4"})
	if err != nil {
		t.Fatalf("openInputPath() error = %v", err)
	}
	defer got.Close()
	want, err := filepath.EvalSymlinks(file)
	if err != nil {
		t.Fatal(err)
	}
	if got.path != filepath.Clean(want) {
		t.Fatalf("openInputPath() = %q, want %q", got.path, want)
	}
}

func TestResolveInputPathRejectsParentEscape(t *testing.T) {
	root := t.TempDir()
	if _, err := openInputPath(domain.MediaInput{RootPath: root, RelativePath: "../outside.mp4"}); err == nil {
		t.Fatal("openInputPath() error = nil, want parent escape error")
	}
}

func TestFFprobeProberUsesExpectedCommandAndMIME(t *testing.T) {
	root := t.TempDir()
	file := filepath.Join(root, "clip.mp4")
	if err := os.WriteFile(file, []byte("media"), 0o600); err != nil {
		t.Fatal(err)
	}
	runner := &fakeCommandRunner{output: []byte(`{"format":{"format_name":"mp4"}}`)}
	prober, err := newFFprobeProber("ffprobe-test", runner)
	if err != nil {
		t.Fatal(err)
	}

	got, err := prober.Probe(context.Background(), domain.MediaInput{RootPath: root, RelativePath: "clip.mp4"})
	if err != nil {
		t.Fatalf("Probe() error = %v", err)
	}
	resolved, err := filepath.EvalSymlinks(file)
	if err != nil {
		t.Fatal(err)
	}
	wantArgs := []string{"-v", "error", "-print_format", "json", "-show_format", "-show_streams", resolved}
	if runner.name != "ffprobe-test" || !reflect.DeepEqual(runner.args, wantArgs) {
		t.Fatalf("command = %q %#v, want %q %#v", runner.name, runner.args, "ffprobe-test", wantArgs)
	}
	if got.MIMEType != "video/mp4" {
		t.Fatalf("MIMEType = %q, want video/mp4", got.MIMEType)
	}
}

// TestFFprobeRejectsInputReplacedDuringExecution 验证命令运行期间换入的新文件不会被接受。
func TestFFprobeRejectsInputReplacedDuringExecution(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "clip.mp4")
	if err := os.WriteFile(path, []byte("original"), 0o600); err != nil {
		t.Fatal(err)
	}
	runner := &replacingCommandRunner{path: path}
	prober, err := newFFprobeProber("ffprobe-test", runner)
	if err != nil {
		t.Fatal(err)
	}
	_, probeErr := prober.Probe(context.Background(), domain.MediaInput{RootPath: root, RelativePath: "clip.mp4"})
	if runner.replaceErr != nil {
		t.Skipf("当前文件系统不能替换保持打开的文件: %v", runner.replaceErr)
	}
	if probeErr == nil {
		t.Fatal("执行期间被替换的媒体输入未被拒绝")
	}
	if !strings.Contains(probeErr.Error(), "替换") {
		t.Fatalf("替换错误 = %v", probeErr)
	}
}
