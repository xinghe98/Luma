package media

import (
	"context"
	"fmt"
	"mime"
	"path/filepath"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// Prober 为后台任务提供可替换的媒体探测能力。
type Prober interface {
	// Probe 安全读取指定媒体并返回标准化元数据。
	Probe(context.Context, domain.MediaInput) (domain.ProbeResult, error)
}

type ffprobeProber struct {
	// executable 是 ffprobe 可执行文件路径。
	executable string
	// runner 执行 ffprobe 命令。
	runner commandRunner
}

// NewFFprobeProber 创建直接调用 ffprobe 的媒体探测器。
func NewFFprobeProber(executable string) (Prober, error) {
	return newFFprobeProber(executable, execRunner{})
}

func newFFprobeProber(executable string, runner commandRunner) (Prober, error) {
	if executable == "" || runner == nil {
		return nil, fmt.Errorf("ffprobe 路径和命令执行器不能为空")
	}
	return &ffprobeProber{executable: executable, runner: runner}, nil
}

// Probe 安全定位文件，执行 ffprobe 并保留原始 JSON。
func (p *ffprobeProber) Probe(ctx context.Context, input domain.MediaInput) (domain.ProbeResult, error) {
	path, err := resolveInputPath(input)
	if err != nil {
		return domain.ProbeResult{}, err
	}
	output, err := p.runner.Run(ctx, p.executable,
		"-v", "error", "-nostdin", "-print_format", "json", "-show_format", "-show_streams", path)
	if err != nil {
		return domain.ProbeResult{}, err
	}
	result, err := parseProbeJSON(output)
	if err != nil {
		return domain.ProbeResult{}, fmt.Errorf("解析 ffprobe JSON: %w", err)
	}
	result.MIMEType = mime.TypeByExtension(filepath.Ext(path))
	return result, nil
}
