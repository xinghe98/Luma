package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"

	"github.com/xinghe98/Luma/backend/internal/config"
)

// Open 创建 SQLite 连接、应用运行参数并执行全部数据库迁移。
func Open(ctx context.Context, cfg config.DatabaseConfig) (*sql.DB, error) {
	if err := os.MkdirAll(filepath.Dir(cfg.Path), 0o750); err != nil {
		return nil, fmt.Errorf("create database directory: %w", err)
	}
	query := url.Values{}
	query.Add("_pragma", "foreign_keys(1)")
	query.Add("_pragma", "busy_timeout("+strconv.Itoa(cfg.BusyTimeoutMS)+")")
	dsn := "file:" + escapeSQLitePath(cfg.Path) + "?" + query.Encode()
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open SQLite: %w", err)
	}
	// One long-lived connection makes connection-scoped PRAGMAs deterministic.
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(0)
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping SQLite: %w", err)
	}
	if cfg.WAL {
		var mode string
		if err := db.QueryRowContext(ctx, "PRAGMA journal_mode = WAL").Scan(&mode); err != nil {
			_ = db.Close()
			return nil, fmt.Errorf("enable SQLite WAL: %w", err)
		}
	}
	if err := migrate(ctx, db, time.Now().UTC()); err != nil {
		_ = db.Close()
		return nil, err
	}
	return db, nil
}

// escapeSQLitePath 将本地路径安全编码为 SQLite URI 文件路径。
func escapeSQLitePath(path string) string {
	parts := strings.Split(filepath.ToSlash(path), "/")
	for i := range parts {
		parts[i] = url.PathEscape(parts[i])
	}
	return strings.Join(parts, "/")
}
