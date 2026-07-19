package app

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	dbrepo "github.com/xinghe98/Luma/backend/internal/repository/sqlite"
)

// authenticatedJSONRequest 创建携带测试 Token 和可选 JSON 请求体的 HTTP 请求。
func authenticatedJSONRequest(t *testing.T, method, url, token string, body []byte) *http.Request {
	t.Helper()
	request, err := http.NewRequest(method, url, bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	return request
}

// TestAppStartsServesHealthAndShutsDown 验证应用完整注入链、启动和优雅关闭。
func TestAppStartsServesHealthAndShutsDown(t *testing.T) {
	base := t.TempDir()
	mediaRoot := filepath.Join(base, "media")
	if err := os.Mkdir(mediaRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{
		"示例 视频.mp4": "video", "封面.jpg": "image", "忽略.txt": "text",
	} {
		if err := os.WriteFile(filepath.Join(mediaRoot, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cfg := config.Config{
		Server: config.ServerConfig{
			Host: "127.0.0.1", Port: 0, ReadHeaderTimeout: time.Second,
			IdleTimeout: time.Second, ShutdownTimeout: 5 * time.Second,
		},
		Security: config.SecurityConfig{
			APITokenFile: filepath.Join(base, "secrets", "token"),
			AllowedRoots: []string{mediaRoot},
		},
		Database: config.DatabaseConfig{
			Path: filepath.Join(base, "media.db"), BusyTimeoutMS: 1000, WAL: true,
		},
		Storage: config.StorageConfig{
			ThumbnailDir: filepath.Join(base, "thumbnails"), CacheDir: filepath.Join(base, "cache"),
		},
		Media: config.MediaConfig{
			FFmpegPath: "ffmpeg", FFprobePath: "ffprobe", ThumbnailWidth: 640,
			ScanExtensions: []string{"mp4", "jpg"},
		},
		Workers: config.WorkersConfig{Scan: 1, Probe: 1, Thumbnail: 1, LockTimeout: time.Minute},
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	application, err := New(context.Background(), cfg, "test", logger)
	if err != nil {
		t.Fatal(err)
	}
	defer application.Close()

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- application.Serve(ctx, listener) }()

	response, err := http.Get("http://" + listener.Addr().String() + "/health")
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusOK {
		cancel()
		t.Fatalf("health status = %d", response.StatusCode)
	}
	token, err := os.ReadFile(cfg.Security.APITokenFile)
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	request, err := http.NewRequest(http.MethodGet, "http://"+listener.Addr().String()+"/api/v1/system/info", nil)
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	request.Header.Set("Authorization", "Bearer "+string(bytes.TrimSpace(token)))
	response, err = http.DefaultClient.Do(request)
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	var systemInfo map[string]string
	if err := json.NewDecoder(response.Body).Decode(&systemInfo); err != nil {
		_ = response.Body.Close()
		cancel()
		t.Fatal(err)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusOK || systemInfo["database"] != "ok" {
		cancel()
		t.Fatalf("system info status = %d, body = %#v", response.StatusCode, systemInfo)
	}
	baseURL := "http://" + listener.Addr().String()
	tokenText := string(bytes.TrimSpace(token))
	forbiddenBody, err := json.Marshal(map[string]string{"name": "越界目录", "root_path": base})
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	response, err = http.DefaultClient.Do(authenticatedJSONRequest(t, http.MethodPost, baseURL+"/api/v1/sources", tokenText, forbiddenBody))
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusForbidden {
		cancel()
		t.Fatalf("白名单外媒体源状态 = %d，期望 403", response.StatusCode)
	}
	createBody, err := json.Marshal(map[string]string{"name": "测试媒体", "root_path": mediaRoot})
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	response, err = http.DefaultClient.Do(authenticatedJSONRequest(t, http.MethodPost, baseURL+"/api/v1/sources", tokenText, createBody))
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	var createdSource map[string]any
	if err := json.NewDecoder(response.Body).Decode(&createdSource); err != nil {
		_ = response.Body.Close()
		cancel()
		t.Fatal(err)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusCreated || createdSource["root_path"] != nil {
		cancel()
		t.Fatalf("创建媒体源响应不符合预期: status=%d body=%#v", response.StatusCode, createdSource)
	}
	sourceID, _ := createdSource["id"].(string)
	response, err = http.DefaultClient.Do(authenticatedJSONRequest(t, http.MethodPost, baseURL+"/api/v1/sources/"+sourceID+"/scan", tokenText, nil))
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	var createdScan map[string]any
	if err := json.NewDecoder(response.Body).Decode(&createdScan); err != nil {
		_ = response.Body.Close()
		cancel()
		t.Fatal(err)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusAccepted {
		cancel()
		t.Fatalf("创建扫描任务状态 = %d", response.StatusCode)
	}
	scanID, _ := createdScan["id"].(string)
	deadline := time.Now().Add(5 * time.Second)
	for {
		response, err = http.DefaultClient.Do(authenticatedJSONRequest(t, http.MethodGet, baseURL+"/api/v1/scan-jobs/"+scanID, tokenText, nil))
		if err != nil {
			cancel()
			t.Fatal(err)
		}
		var current map[string]any
		if err := json.NewDecoder(response.Body).Decode(&current); err != nil {
			_ = response.Body.Close()
			cancel()
			t.Fatal(err)
		}
		_ = response.Body.Close()
		if current["status"] == "completed" {
			if current["processed_count"] != float64(2) {
				cancel()
				t.Fatalf("处理文件数 = %v，期望 2", current["processed_count"])
			}
			break
		}
		if current["status"] == "failed" {
			cancel()
			t.Fatalf("扫描任务失败: %#v", current)
		}
		if time.Now().After(deadline) {
			cancel()
			t.Fatal("等待扫描任务完成超时")
		}
		time.Sleep(20 * time.Millisecond)
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("application did not shut down")
	}
	if err := application.Close(); err != nil {
		t.Fatal(err)
	}
	database, err := dbrepo.Open(context.Background(), cfg.Database)
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	var mediaCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM media_items").Scan(&mediaCount); err != nil {
		t.Fatal(err)
	}
	if mediaCount != 2 {
		t.Fatalf("媒体索引数量 = %d，期望 2", mediaCount)
	}
}
