package jobs

import (
	"context"
	"errors"
)

// Runner 定义由应用生命周期托管的后台组件。
type Runner interface {
	// Run 阻塞运行，直到上下文取消或发生致命基础设施错误。
	Run(context.Context) error
}

// Group 将恢复器和多个后台 Worker 作为一个应用生命周期组件运行。
type Group struct {
	// recovery 在 Worker 启动前恢复持久化任务。
	recovery *ProcessingRecovery
	// runners 是由任务组并发托管的后台组件。
	runners []Runner
}

// NewGroup 创建先恢复持久化状态、再并发运行所有 Worker 的任务组。
func NewGroup(recovery *ProcessingRecovery, runners ...Runner) (*Group, error) {
	if recovery == nil || len(runners) == 0 {
		return nil, errors.New("后台任务组依赖不能为空")
	}
	for _, item := range runners {
		if item == nil {
			return nil, errors.New("后台 Worker 不能为空")
		}
	}
	return &Group{recovery: recovery, runners: runners}, nil
}

// Run 在任一组件发生致命错误时取消并等待其余组件退出。
func (g *Group) Run(ctx context.Context) error {
	if err := g.recovery.Prepare(ctx); err != nil {
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
