//go:build windows

package platform

import (
	"context"
	"sync"

	"golang.org/x/sys/windows/svc"
)

// serviceRunner 将应用运行函数适配为 Windows 服务处理器。
type serviceRunner struct {
	// run 是应用的阻塞运行函数。
	run func(context.Context) error
	// mu 保护跨 Goroutine 写入的运行错误。
	mu sync.Mutex
	// runErr 保存应用退出时返回的错误。
	runErr error
}

// RunWindowsService 检测当前进程是否由 SCM 启动，并在服务模式下托管应用。
func RunWindowsService(name string, run func(context.Context) error) (bool, error) {
	isService, err := svc.IsWindowsService()
	if err != nil {
		return false, err
	}
	if !isService {
		return false, nil
	}
	runner := &serviceRunner{run: run}
	if err := svc.Run(name, runner); err != nil {
		return true, err
	}
	runner.mu.Lock()
	defer runner.mu.Unlock()
	return true, runner.runErr
}

// Execute 响应 Windows 服务启动、查询、停止和关机控制命令。
func (r *serviceRunner) Execute(_ []string, requests <-chan svc.ChangeRequest, statuses chan<- svc.Status) (bool, uint32) {
	const accepted = svc.AcceptStop | svc.AcceptShutdown
	statuses <- svc.Status{State: svc.StartPending}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- r.run(ctx) }()
	statuses <- svc.Status{State: svc.Running, Accepts: accepted}

	for {
		select {
		case err := <-done:
			r.setError(err)
			statuses <- svc.Status{State: svc.StopPending}
			return false, 0
		case request := <-requests:
			switch request.Cmd {
			case svc.Interrogate:
				statuses <- request.CurrentStatus
			case svc.Stop, svc.Shutdown:
				statuses <- svc.Status{State: svc.StopPending}
				cancel()
				err := <-done
				r.setError(err)
				return false, 0
			}
		}
	}
}

// setError 以并发安全方式记录应用运行错误。
func (r *serviceRunner) setError(err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.runErr = err
}
