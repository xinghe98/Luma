//go:build !windows

package media

import "os/exec"

func configureCancellation(_ *exec.Cmd) {}
