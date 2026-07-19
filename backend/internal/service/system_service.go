package service

import (
	"context"
	"errors"
	"runtime"
	"strings"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// DatabasePinger 定义系统服务检查数据库连通性所需的最小接口。
type DatabasePinger interface {
	// PingContext 在指定上下文中检查数据库是否可用。
	PingContext(context.Context) error
}

// SystemService 提供服务存活信息和受保护的系统运行信息。
type SystemService struct {
	// version 是构建时注入的服务版本。
	version string
	// database 是注入的数据库连通性检查器。
	database DatabasePinger
}

// NewSystemService 使用版本和数据库依赖创建系统服务。
func NewSystemService(version string, database DatabasePinger) (*SystemService, error) {
	if strings.TrimSpace(version) == "" {
		return nil, errors.New("version is required")
	}
	if database == nil {
		return nil, errors.New("database pinger is required")
	}
	return &SystemService{version: version, database: database}, nil
}

// Health 返回不访问外部资源的进程存活信息。
func (s *SystemService) Health(context.Context) domain.Health {
	return domain.Health{Status: "ok", Version: s.version}
}

// Info 检查数据库后返回完整系统运行信息。
func (s *SystemService) Info(ctx context.Context) (domain.SystemInfo, error) {
	if err := s.database.PingContext(ctx); err != nil {
		return domain.SystemInfo{}, err
	}
	return domain.SystemInfo{
		Version: s.version, Platform: runtime.GOOS,
		Architecture: runtime.GOARCH, Database: "ok",
	}, nil
}
