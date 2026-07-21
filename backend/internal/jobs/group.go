package jobs

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"
)

// Runner 定义由应用生命周期托管的后台组件。
type Runner interface {
	// Run 阻塞运行，直到上下文取消或发生致命基础设施错误。
	Run(context.Context) error
}

type scanRecoveryRepository interface {
	InterruptRunningJobs(context.Context, time.Time) error
}

type recoveryRunner interface {
	Runner
	Prepare(context.Context) error
}

// Group 将恢复器和多个后台 Worker 作为一个应用生命周期组件运行。
type Group struct {
	// scans 在 Worker 启动前结束异常退出遗留的运行中扫描。
	scans scanRecoveryRepository
	// clock 提供扫描恢复使用的统一 UTC 时间。
	clock WorkerClock
	// recovery 在 Worker 启动前恢复持久化任务。
	recovery recoveryRunner
	// runners 是由任务组并发托管的后台组件。
	runners []Runner
	// prepareOnce 保证多个扫描 Worker 共享一次启动恢复。
	prepareOnce sync.Once
	// prepareErr 保存唯一一次启动恢复的结果。
	prepareErr error
}

// NewGroup 创建先恢复持久化状态、再并发运行所有 Worker 的任务组。
func NewGroup(scans scanRecoveryRepository, clock WorkerClock, recovery recoveryRunner, runners ...Runner) (*Group, error) {
	if scans == nil || clock == nil || recovery == nil || len(runners) == 0 {
		return nil, errors.New("后台任务组依赖不能为空")
	}
	for _, item := range runners {
		if item == nil {
			return nil, errors.New("后台 Worker 不能为空")
		}
	}
	return &Group{scans: scans, clock: clock, recovery: recovery, runners: runners}, nil
}

// Add 在 Run 之前追加后台组件（例如依赖 ScanService 的自动扫描调度器）。
func (g *Group) Add(runners ...Runner) error {
	if g == nil {
		return errors.New("后台任务组不能为空")
	}
	for _, item := range runners {
		if item == nil {
			return errors.New("后台 Worker 不能为空")
		}
		g.runners = append(g.runners, item)
	}
	return nil
}

// Prepare 在任何 Worker 或 HTTP 服务启动前只恢复一次持久化任务。
func (g *Group) Prepare(ctx context.Context) error {
	g.prepareOnce.Do(func() {
		if err := g.scans.InterruptRunningJobs(ctx, g.clock.Now()); err != nil {
			g.prepareErr = fmt.Errorf("恢复遗留扫描任务: %w", err)
			return
		}
		g.prepareErr = g.recovery.Prepare(ctx)
	})
	return g.prepareErr
}

// Run 在任一组件发生致命错误时取消并等待其余组件退出。
func (g *Group) Run(ctx context.Context) error {
	if err := g.Prepare(ctx); err != nil {
		return err
	}
	runCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	all := append([]Runner{g.recovery}, g.runners...)
	errorsCh := make(chan error, len(all))
	for _, item := range all {
		go func(item Runner) { errorsCh <- item.Run(runCtx) }(item)
	}
	var result error
	for range all {
		err := <-errorsCh
		if err != nil && result == nil {
			result = err
			cancel()
		}
	}
	return result
}
