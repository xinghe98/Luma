//go:build windows

package media

import (
	"os"
	"os/exec"
	"strconv"
)

// configureCancellation 终止 Scoop shim 等启动的完整子进程树。
func configureCancellation(command *exec.Cmd) {
	command.Cancel = func() error {
		if command.Process == nil {
			return os.ErrProcessDone
		}
		kill := exec.Command("TASKKILL", "/T", "/F", "/PID", strconv.Itoa(command.Process.Pid))
		if err := kill.Run(); err != nil {
			// 进程可能已经自行退出；避免与 exec.Cmd.Wait 并发读取 ProcessState。
			return os.ErrProcessDone
		}
		return nil
	}
}
