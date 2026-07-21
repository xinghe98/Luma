package app

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"

	"github.com/xinghe98/Luma/backend/internal/config"
)

// App 持有服务端顶层运行组件并负责生命周期管理。
type App struct {
	// config 是启动后只读的应用配置。
	config config.Config
	// logger 是应用共享的结构化日志器。
	logger *slog.Logger
	// router 是已完成依赖注入的 HTTP 路由。
	router http.Handler
	// server 是承载 Router 的标准 HTTP Server。
	server *http.Server

	// cleanups 保存需要按逆序释放的顶层资源。
	cleanups *cleanupStack
	// worker 是随应用生命周期启动和停止的扫描任务执行器。
	worker backgroundRunner
}

// backgroundRunner 定义应用托管后台组件所需的阻塞运行能力。
type backgroundRunner interface {
	// Prepare 在服务对外就绪前恢复持久化任务。
	Prepare(context.Context) error
	// Run 持续运行后台组件，直到上下文取消或发生致命错误。
	Run(context.Context) error
}

// Handler 返回应用使用的标准 HTTP Handler，供测试或外部监听器复用。
func (a *App) Handler() http.Handler { return a.router }

// Run 创建监听器并阻塞运行服务，直到退出或发生错误。
func (a *App) Run(ctx context.Context) error {
	listener, err := net.Listen("tcp", a.server.Addr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", a.server.Addr, err)
	}
	return a.Serve(ctx, listener)
}

// Serve 在已创建的监听器上运行服务，便于测试生命周期且无需固定端口。
func (a *App) Serve(ctx context.Context, listener net.Listener) error {
	if err := a.worker.Prepare(ctx); err != nil {
		_ = listener.Close()
		return fmt.Errorf("prepare background workers: %w", err)
	}
	runCtx, cancelRun := context.WithCancel(ctx)
	defer cancelRun()
	serveError := make(chan error, 1)
	workerError := make(chan error, 1)
	go func() {
		a.logger.Info("HTTP server starting", "address", listener.Addr().String())
		serveError <- a.server.Serve(listener)
	}()
	go func() {
		workerError <- a.worker.Run(runCtx)
	}()

	select {
	case err := <-serveError:
		cancelRun()
		workerErr := <-workerError
		if !errors.Is(err, http.ErrServerClosed) {
			return errors.Join(fmt.Errorf("serve HTTP: %w", err), workerErr)
		}
		return workerErr
	case err := <-workerError:
		cancelRun()
		shutdownErr := a.shutdownHTTP()
		serveErr := <-serveError
		if errors.Is(serveErr, http.ErrServerClosed) {
			serveErr = nil
		}
		if err == nil && ctx.Err() == nil {
			err = errors.New("扫描 Worker 意外停止")
		}
		return errors.Join(err, shutdownErr, serveErr)
	case <-ctx.Done():
		cancelRun()
		shutdownErr := a.shutdownHTTP()
		serveErr := <-serveError
		workerErr := <-workerError
		if errors.Is(serveErr, http.ErrServerClosed) {
			serveErr = nil
		}
		a.logger.Info("HTTP server stopped")
		return errors.Join(shutdownErr, serveErr, workerErr)
	}
}

// shutdownHTTP 在配置的超时时间内优雅关闭 HTTP Server。
func (a *App) shutdownHTTP() error {
	shutdownCtx, cancel := context.WithTimeout(context.Background(), a.config.Server.ShutdownTimeout)
	defer cancel()
	if err := a.server.Shutdown(shutdownCtx); err != nil {
		_ = a.server.Close()
		return fmt.Errorf("关闭 HTTP Server: %w", err)
	}
	return nil
}

// Close 以幂等方式逆序释放应用持有的顶层资源。
func (a *App) Close() error {
	return a.cleanups.Close()
}
