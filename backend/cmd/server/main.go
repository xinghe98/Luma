// Package main 提供 Luma 服务端可执行程序入口。
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/xinghe98/Luma/backend/internal/app"
	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/platform"
)

// version 是构建阶段通过链接参数注入的服务版本。
var version = "dev"

// main 是服务端进程入口，负责输出不可恢复错误并设置退出码。
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "luma-server:", err)
		os.Exit(1)
	}
}

// run 解析启动参数、组装应用并管理操作系统退出信号。
func run() error {
	configPath := flag.String("config", "configs/config.yaml", "path to YAML configuration")
	checkConfig := flag.Bool("check-config", false, "validate configuration and runtime dependencies, then exit")
	logFormat := flag.String("log-format", "json", "log format: json or text")
	serviceName := flag.String("service-name", "LumaServer", "Windows service name")
	flag.Parse()

	logger, err := newLogger(*logFormat)
	if err != nil {
		return err
	}
	cfg, err := config.Load(*configPath)
	if err != nil {
		return err
	}
	if *checkConfig {
		if err := config.CheckEnvironment(context.Background(), cfg); err != nil {
			return err
		}
		logger.Info("configuration check passed")
		return nil
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	application, err := app.New(ctx, cfg, *configPath, version, logger)
	if err != nil {
		return err
	}
	defer application.Close()
	if handled, err := platform.RunWindowsService(*serviceName, application.Run); handled {
		return err
	} else if err != nil {
		return fmt.Errorf("detect Windows service: %w", err)
	}
	return application.Run(ctx)
}

// newLogger 根据命令行格式创建 JSON 或文本结构化日志器。
func newLogger(format string) (*slog.Logger, error) {
	options := &slog.HandlerOptions{Level: slog.LevelInfo}
	switch format {
	case "json":
		return slog.New(slog.NewJSONHandler(os.Stdout, options)), nil
	case "text":
		return slog.New(slog.NewTextHandler(os.Stdout, options)), nil
	default:
		return nil, fmt.Errorf("invalid log format %q: use json or text", format)
	}
}
