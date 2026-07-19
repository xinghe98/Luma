package media

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"time"
)

const (
	stderrLimit = 4096
	stdoutLimit = 8 << 20
)

type commandRunner interface {
	Run(context.Context, string, ...string) ([]byte, error)
}

type execRunner struct{}

// Run 直接执行外部程序，不经过 shell，并限制错误输出长度。
func (execRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	command := exec.CommandContext(ctx, name, args...)
	configureCancellation(command)
	command.WaitDelay = 2 * time.Second
	stdout := &limitedBuffer{remaining: stdoutLimit}
	stderr := &limitedBuffer{remaining: stderrLimit}
	command.Stdout = stdout
	command.Stderr = stderr
	if err := command.Run(); err != nil {
		message := stderr.String()
		if message == "" {
			message = "无错误输出"
		}
		return nil, fmt.Errorf("执行 %s 失败: %w: %s", name, err, message)
	}
	if stdout.truncated {
		return nil, fmt.Errorf("执行 %s 的标准输出超过限制", name)
	}
	return []byte(stdout.data.String()), nil
}

type limitedBuffer struct {
	// data 保存限制范围内的输出。
	data bytes.Buffer
	// remaining 是尚可写入的字节数。
	remaining int
	// truncated 表示输入已超过容量限制。
	truncated bool
}

func (b *limitedBuffer) Write(data []byte) (int, error) {
	written := len(data)
	if len(data) > b.remaining {
		data = data[:b.remaining]
		b.truncated = true
	}
	_, _ = b.data.Write(data)
	b.remaining -= len(data)
	return written, nil
}

func (b *limitedBuffer) String() string {
	if b.truncated {
		return b.data.String() + "...(已截断)"
	}
	return b.data.String()
}
