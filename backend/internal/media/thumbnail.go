package media

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"image"
	_ "image/jpeg"
	"io"
	"os"
	"path/filepath"
	"strconv"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// Thumbnailer 为后台任务提供可替换的默认缩略图生成能力。
type Thumbnailer interface {
	// Generate 生成并原子落盘默认缩略图。
	Generate(context.Context, domain.MediaInput, int64) (domain.ThumbnailResult, error)
}

type ffmpegThumbnailer struct {
	// executable 是 ffmpeg 可执行文件路径。
	executable string
	// root 是缩略图存储根目录。
	root string
	// width 是缩略图目标宽度。
	width int
	// runner 执行 ffmpeg 命令。
	runner commandRunner
}

// NewFFmpegThumbnailer 创建输出 JPEG 到缩略图目录的生成器。
func NewFFmpegThumbnailer(executable, thumbnailRoot string, width int) (Thumbnailer, error) {
	return newFFmpegThumbnailer(executable, thumbnailRoot, width, execRunner{})
}

func newFFmpegThumbnailer(executable, root string, width int, runner commandRunner) (Thumbnailer, error) {
	if executable == "" || root == "" || width <= 0 || runner == nil {
		return nil, fmt.Errorf("ffmpeg 路径、缩略图目录、宽度和命令执行器必须有效")
	}
	if !filepath.IsAbs(root) {
		return nil, fmt.Errorf("缩略图目录必须是绝对路径")
	}
	return &ffmpegThumbnailer{executable: executable, root: filepath.Clean(root), width: width, runner: runner}, nil
}

// Generate 先写同目录临时文件，成功后再原子替换默认封面。
func (t *ffmpegThumbnailer) Generate(ctx context.Context, input domain.MediaInput, durationMS int64) (domain.ThumbnailResult, error) {
	source, err := resolveInputPath(input)
	if err != nil {
		return domain.ThumbnailResult{}, err
	}
	if input.ID == "" || filepath.Base(input.ID) != input.ID || input.ID == "." || input.ID == ".." {
		return domain.ThumbnailResult{}, fmt.Errorf("媒体 ID 不适合作为存储键")
	}
	directory := filepath.Join(t.root, input.ID)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return domain.ThumbnailResult{}, fmt.Errorf("创建缩略图目录: %w", err)
	}
	temporary, err := os.CreateTemp(directory, ".cover-*.jpg")
	if err != nil {
		return domain.ThumbnailResult{}, fmt.Errorf("创建缩略图临时文件: %w", err)
	}
	temporaryPath := temporary.Name()
	_ = temporary.Close()
	defer os.Remove(temporaryPath)
	args := thumbnailArgs(input.MediaType, source, temporaryPath, t.width, durationMS)
	if _, err := t.runner.Run(ctx, t.executable, args...); err != nil {
		return domain.ThumbnailResult{}, err
	}
	file, err := os.Open(temporaryPath)
	if err != nil {
		return domain.ThumbnailResult{}, fmt.Errorf("打开缩略图: %w", err)
	}
	config, _, decodeErr := image.DecodeConfig(file)
	_ = file.Close()
	if decodeErr != nil {
		return domain.ThumbnailResult{}, fmt.Errorf("读取缩略图尺寸: %w", decodeErr)
	}
	name := ThumbnailFileName(t.width)
	finalPath := filepath.Join(directory, name)
	if err := atomicReplace(temporaryPath, finalPath); err != nil {
		return domain.ThumbnailResult{}, fmt.Errorf("替换缩略图: %w", err)
	}
	sum, err := fileSHA256(finalPath)
	if err != nil {
		return domain.ThumbnailResult{}, err
	}
	return domain.ThumbnailResult{
		StorageKey:    ThumbnailStorageKey(input.ID, t.width),
		MIMEType:      "image/jpeg",
		ContentSHA256: sum,
		Width:         config.Width,
		Height:        config.Height,
	}, nil
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("打开缩略图计算哈希: %w", err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", fmt.Errorf("计算缩略图哈希: %w", err)
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func thumbnailArgs(mediaType, source, output string, width int, durationMS int64) []string {
	args := []string{"-v", "error", "-nostdin", "-y"}
	if mediaType == domain.MediaTypeVideo {
		args = append(args, "-ss", strconv.FormatFloat(seekSeconds(durationMS), 'f', 3, 64))
	}
	filter := fmt.Sprintf("scale=%d:-2,format=yuvj420p", width)
	args = append(args, "-i", source, "-frames:v", "1", "-vf", filter, "-q:v", "3", "-c:v", "mjpeg", "-f", "image2", output)
	return args
}

func seekSeconds(durationMS int64) float64 {
	seconds := float64(durationMS) / 1000
	if seconds <= 0 {
		return 0
	}
	if seconds < 30 {
		return seconds * .2
	}
	if seconds <= 1200 {
		return seconds * .1
	}
	if seconds*.1 < 60 {
		return 60
	}
	if seconds*.1 > 120 {
		return 120
	}
	return seconds * .1
}
