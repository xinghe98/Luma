package app

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/xinghe98/Luma/backend/internal/api"
	"github.com/xinghe98/Luma/backend/internal/api/handler"
	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/jobs"
	"github.com/xinghe98/Luma/backend/internal/platform"
	dbrepo "github.com/xinghe98/Luma/backend/internal/repository/sqlite"
	"github.com/xinghe98/Luma/backend/internal/security"
	"github.com/xinghe98/Luma/backend/internal/service"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// bootstrap 是应用唯一的 Composition Root，负责创建具体基础设施并向内注入接口。
type bootstrap struct {
	// config 是用于组装组件的只读配置。
	config config.Config
	// version 是构建时注入的服务版本。
	version string
	// logger 是应用共享日志器。
	logger *slog.Logger
	// cleanups 记录已成功创建资源的清理动作。
	cleanups *cleanupStack
}

// New 按依赖顺序组装完整应用，并在任一步失败时回滚已创建资源。
func New(ctx context.Context, cfg config.Config, version string, logger *slog.Logger) (_ *App, err error) {
	if logger == nil {
		return nil, errors.New("logger is required")
	}
	b := &bootstrap{
		config: cfg, version: version, logger: logger,
		cleanups: &cleanupStack{},
	}
	defer func() {
		if err != nil {
			err = errors.Join(err, b.cleanups.Close())
		}
	}()
	return b.build(ctx)
}

// build 创建基础设施、服务、Handler、Router 和 HTTP Server。
func (b *bootstrap) build(ctx context.Context) (*App, error) {
	if err := config.PrepareDataDirectories(b.config); err != nil {
		return nil, err
	}

	pathPolicy, err := platform.NewPathPolicy(b.config.Security.AllowedRoots)
	if err != nil {
		return nil, fmt.Errorf("initialize path policy: %w", err)
	}
	database, err := dbrepo.Open(ctx, b.config.Database)
	if err != nil {
		return nil, err
	}
	b.cleanups.Push("database", database.Close)

	token, created, err := security.LoadOrCreateToken(b.config.Security.APITokenFile)
	if err != nil {
		return nil, err
	}
	if created {
		b.logger.Info("API token file created", "path", b.config.Security.APITokenFile)
	}
	authenticator, err := security.NewTokenAuthenticator(token)
	if err != nil {
		return nil, fmt.Errorf("create API authenticator: %w", err)
	}

	systemService, err := service.NewSystemService(b.version, database)
	if err != nil {
		return nil, fmt.Errorf("create system service: %w", err)
	}
	sourceRepository, err := dbrepo.NewSourceRepository(database)
	if err != nil {
		return nil, fmt.Errorf("创建媒体源 Repository: %w", err)
	}
	scanRepository, err := dbrepo.NewScanRepository(database)
	if err != nil {
		return nil, fmt.Errorf("创建扫描 Repository: %w", err)
	}
	mediaRepository, err := dbrepo.NewMediaRepository(database)
	if err != nil {
		return nil, fmt.Errorf("创建媒体 Repository: %w", err)
	}
	userDataRepository, err := dbrepo.NewUserDataRepository(database)
	if err != nil {
		return nil, fmt.Errorf("创建用户数据 Repository: %w", err)
	}
	tagRepository, err := dbrepo.NewTagRepository(database)
	if err != nil {
		return nil, fmt.Errorf("创建标签 Repository: %w", err)
	}
	thumbnailStore, err := storage.NewThumbnailStore(b.config.Storage.ThumbnailDir)
	if err != nil {
		return nil, fmt.Errorf("创建缩略图存储: %w", err)
	}
	ids := platform.SecureIDGenerator{}
	clock := platform.RealClock{}
	localFactory, err := storage.NewLocalFactory(platform.OSFileIdentifier{}, clock)
	if err != nil {
		return nil, fmt.Errorf("创建本地媒体源工厂: %w", err)
	}
	workerGroup, scanSignal, err := b.buildWorkers(database, sourceRepository, scanRepository, localFactory, ids, clock)
	if err != nil {
		return nil, err
	}
	sourceService, err := service.NewSourceService(sourceRepository, pathPolicy, scanRepository, ids, clock)
	if err != nil {
		return nil, fmt.Errorf("create source service: %w", err)
	}
	scanService, err := service.NewScanService(sourceRepository, scanRepository, ids, clock, scanSignal)
	if err != nil {
		return nil, fmt.Errorf("创建扫描服务: %w", err)
	}
	// 自动扫描依赖 ScanService，故在 Worker 组创建后再挂接调度器。
	if b.config.Media.AutoScan.Enabled {
		autoScan, err := jobs.NewAutoScanScheduler(
			sourceRepository, scanService, b.config.Media.AutoScan, clock, b.logger,
		)
		if err != nil {
			return nil, fmt.Errorf("创建自动扫描调度器: %w", err)
		}
		if err := workerGroup.Add(autoScan); err != nil {
			return nil, fmt.Errorf("注册自动扫描调度器: %w", err)
		}
	}
	mediaService, err := service.NewMediaService(mediaRepository, thumbnailStore)
	if err != nil {
		return nil, fmt.Errorf("创建媒体服务: %w", err)
	}
	streamService, err := service.NewStreamService(mediaRepository, localFactory)
	if err != nil {
		return nil, fmt.Errorf("创建原始媒体服务: %w", err)
	}
	userDataService, err := service.NewUserDataService(userDataRepository, clock)
	if err != nil {
		return nil, fmt.Errorf("创建用户数据服务: %w", err)
	}
	tagService, err := service.NewTagService(tagRepository, ids, clock)
	if err != nil {
		return nil, fmt.Errorf("创建标签服务: %w", err)
	}
	healthHandler, err := handler.NewHealthHandler(systemService)
	if err != nil {
		return nil, fmt.Errorf("create health handler: %w", err)
	}
	systemHandler, err := handler.NewSystemHandler(systemService)
	if err != nil {
		return nil, fmt.Errorf("create system handler: %w", err)
	}
	sourceHandler, err := handler.NewSourceHandler(sourceService)
	if err != nil {
		return nil, fmt.Errorf("创建媒体源 Handler: %w", err)
	}
	scanHandler, err := handler.NewScanHandler(scanService)
	if err != nil {
		return nil, fmt.Errorf("创建扫描 Handler: %w", err)
	}
	mediaHandler, err := handler.NewMediaHandler(mediaService)
	if err != nil {
		return nil, fmt.Errorf("创建媒体 Handler: %w", err)
	}
	streamHandler, err := handler.NewStreamHandler(streamService)
	if err != nil {
		return nil, fmt.Errorf("创建原始媒体 Handler: %w", err)
	}
	userDataHandler, err := handler.NewUserDataHandler(userDataService)
	if err != nil {
		return nil, fmt.Errorf("创建用户数据 Handler: %w", err)
	}
	tagHandler, err := handler.NewTagHandler(tagService)
	if err != nil {
		return nil, fmt.Errorf("创建标签 Handler: %w", err)
	}
	router, err := api.NewRouter(api.RouterParams{
		Logger: b.logger, AllowedOrigins: b.config.Security.AllowedOrigins,
		Health: healthHandler, System: systemHandler, Sources: sourceHandler,
		Scans: scanHandler, Media: mediaHandler, Stream: streamHandler,
		UserData: userDataHandler, Tags: tagHandler, Authenticator: authenticator,
	})
	if err != nil {
		return nil, fmt.Errorf("create router: %w", err)
	}
	server := &http.Server{
		Addr: b.config.Server.Address(), Handler: router,
		ReadHeaderTimeout: b.config.Server.ReadHeaderTimeout,
		IdleTimeout:       b.config.Server.IdleTimeout,
	}
	return &App{
		config: b.config, logger: b.logger, router: router, server: server,
		cleanups: b.cleanups, worker: workerGroup,
	}, nil
}
