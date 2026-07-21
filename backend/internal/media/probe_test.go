package media

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
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

	got, err := resolveInputPath(domain.MediaInput{RootPath: root, RelativePath: "nested/clip.mp4"})
	if err != nil {
		t.Fatalf("resolveInputPath() error = %v", err)
	}
	want, err := filepath.EvalSymlinks(file)
	if err != nil {
		t.Fatal(err)
	}
	if got != filepath.Clean(want) {
		t.Fatalf("resolveInputPath() = %q, want %q", got, want)
	}
}

func TestResolveInputPathRejectsParentEscape(t *testing.T) {
	root := t.TempDir()
	if _, err := resolveInputPath(domain.MediaInput{RootPath: root, RelativePath: "../outside.mp4"}); err == nil {
		t.Fatal("resolveInputPath() error = nil, want parent escape error")
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
