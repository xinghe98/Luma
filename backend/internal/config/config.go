package config

import "time"

// Config 表示服务端运行所需的完整配置。
type Config struct {
	// Server 保存 HTTP 服务配置。
	Server ServerConfig `yaml:"server"`
	// Security 保存认证、跨域和目录白名单配置。
	Security SecurityConfig `yaml:"security"`
	// Database 保存 SQLite 配置。
	Database DatabaseConfig `yaml:"database"`
	// Storage 保存衍生资源目录配置。
	Storage StorageConfig `yaml:"storage"`
	// Media 保存媒体处理工具和文件类型配置。
	Media MediaConfig `yaml:"media"`
	// Workers 保存后台任务并发配置。
	Workers WorkersConfig `yaml:"workers"`
}

// ServerConfig 表示 HTTP 服务监听地址和超时配置。
type ServerConfig struct {
	// Host 是 HTTP 服务监听主机。
	Host string `yaml:"host"`
	// Port 是 HTTP 服务监听端口。
	Port int `yaml:"port"`
	// ReadHeaderTimeout 是读取请求头的最长时间。
	ReadHeaderTimeout time.Duration `yaml:"read_header_timeout"`
	// IdleTimeout 是空闲连接的最长保留时间。
	IdleTimeout time.Duration `yaml:"idle_timeout"`
	// ShutdownTimeout 是优雅关闭的最长等待时间。
	ShutdownTimeout time.Duration `yaml:"shutdown_timeout"`
}

// Address 返回可供 net/http 使用的监听地址。
func (c ServerConfig) Address() string {
	return netJoinHostPort(c.Host, c.Port)
}

// SecurityConfig 表示 API 认证和本地路径访问边界配置。
type SecurityConfig struct {
	// APITokenFile 是 API Token 的安全存储文件。
	APITokenFile string `yaml:"api_token_file"`
	// AllowedOrigins 是允许访问 API 的浏览器来源列表。
	AllowedOrigins []string `yaml:"allowed_origins"`
	// AllowedRoots 是可以添加为媒体源的根目录白名单。
	AllowedRoots []string `yaml:"allowed_roots"`
}

// DatabaseConfig 表示 SQLite 数据库连接和运行参数。
type DatabaseConfig struct {
	// Path 是 SQLite 数据库文件路径。
	Path string `yaml:"path"`
	// BusyTimeoutMS 是 SQLite 锁冲突的等待毫秒数。
	BusyTimeoutMS int `yaml:"busy_timeout_ms"`
	// WAL 表示是否启用预写日志模式。
	WAL bool `yaml:"wal"`
}

// StorageConfig 表示缩略图和缓存的可写目录配置。
type StorageConfig struct {
	// ThumbnailDir 是缩略图存储目录。
	ThumbnailDir string `yaml:"thumbnail_dir"`
	// CacheDir 是临时缓存目录。
	CacheDir string `yaml:"cache_dir"`
}

// MediaConfig 表示媒体工具和扫描策略配置。
type MediaConfig struct {
	// FFmpegPath 是 ffmpeg 可执行文件路径。
	FFmpegPath string `yaml:"ffmpeg_path"`
	// FFprobePath 是 ffprobe 可执行文件路径。
	FFprobePath string `yaml:"ffprobe_path"`
	// ThumbnailWidth 是默认缩略图宽度。
	ThumbnailWidth int `yaml:"thumbnail_width"`
	// ScanExtensions 是扫描器识别的文件扩展名列表。
	ScanExtensions []string `yaml:"scan_extensions"`
}

// WorkersConfig 表示各类后台任务的并发和锁配置。
type WorkersConfig struct {
	// Scan 是扫描任务并发数。
	Scan int `yaml:"scan"`
	// Probe 是媒体探测任务并发数。
	Probe int `yaml:"probe"`
	// Thumbnail 是缩略图任务并发数。
	Thumbnail int `yaml:"thumbnail"`
	// LockTimeout 是任务锁失效时间。
	LockTimeout time.Duration `yaml:"lock_timeout"`
}
