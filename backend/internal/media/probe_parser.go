package media

import (
	"encoding/json"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type probeDocument struct {
	// Streams 是媒体流列表。
	Streams []probeStream `json:"streams"`
	// Format 是媒体容器信息。
	Format probeFormat `json:"format"`
}

type probeStream struct {
	// CodecType 是流的媒体类型。
	CodecType string `json:"codec_type"`
	// CodecName 是流的编解码器名称。
	CodecName string `json:"codec_name"`
	// Duration 是流时长的秒数字符串。
	Duration string `json:"duration"`
	// BitRate 是流码率的字符串表示。
	BitRate string `json:"bit_rate"`
	// FrameRate 是平均帧率的分数字符串。
	FrameRate string `json:"avg_frame_rate"`
	// Fallback 是备用帧率的分数字符串。
	Fallback string `json:"r_frame_rate"`
	// Width 是视频流的像素宽度。
	Width int `json:"width"`
	// Height 是视频流的像素高度。
	Height int `json:"height"`
	// Tags 保存流级元数据标签。
	Tags map[string]string `json:"tags"`
	// Disposition 保存流的用途标记。
	Disposition probeDisposition `json:"disposition"`
	// SideData 保存流的附加数据。
	SideData []struct {
		// Rotation 是附加数据声明的旋转角度。
		Rotation int `json:"rotation"`
	} `json:"side_data_list"`
}

type probeDisposition struct {
	// AttachedPic 表示该视频流是否为内嵌封面。
	AttachedPic int `json:"attached_pic"`
}

type probeFormat struct {
	// Name 是媒体容器格式名称。
	Name string `json:"format_name"`
	// Duration 是容器时长的秒数字符串。
	Duration string `json:"duration"`
	// BitRate 是容器码率的字符串表示。
	BitRate string `json:"bit_rate"`
	// Tags 保存容器级元数据标签。
	Tags map[string]string `json:"tags"`
}

// parseProbeJSON 将 ffprobe 文档转换为稳定的领域结果版本。
func parseProbeJSON(data []byte) (domain.ProbeResult, error) {
	var document probeDocument
	if err := json.Unmarshal(data, &document); err != nil {
		return domain.ProbeResult{}, err
	}
	result := domain.ProbeResult{RawJSON: append([]byte(nil), data...), Version: 1, Container: document.Format.Name}
	result.Title = document.Format.Tags["title"]
	if captured, err := time.Parse(time.RFC3339, document.Format.Tags["creation_time"]); err == nil {
		result.CapturedAt = &captured
	}
	result.DurationMS = milliseconds(document.Format.Duration)
	result.Bitrate = integer64(document.Format.BitRate)
	for i := range document.Streams {
		applyStream(&result, &document.Streams[i])
	}
	return result, nil
}

func applyStream(result *domain.ProbeResult, stream *probeStream) {
	if result.DurationMS == nil {
		result.DurationMS = milliseconds(stream.Duration)
	}
	if result.Bitrate == nil {
		result.Bitrate = integer64(stream.BitRate)
	}
	if stream.CodecType == "audio" {
		result.AudioTrackCount++
		if result.AudioCodec == "" {
			result.AudioCodec = stream.CodecName
		}
		return
	}
	if stream.CodecType != "video" || stream.Disposition.AttachedPic == 1 || result.VideoCodec != "" {
		return
	}
	result.VideoCodec = stream.CodecName
	if streamDuration := milliseconds(stream.Duration); streamDuration != nil {
		result.DurationMS = streamDuration
	}
	if stream.Width > 0 {
		result.Width = pointer(stream.Width)
	}
	if stream.Height > 0 {
		result.Height = pointer(stream.Height)
	}
	frameRate := stream.FrameRate
	if frameRate == "" || frameRate == "0/0" {
		frameRate = stream.Fallback
	}
	result.FrameRateNum, result.FrameRateDen = fraction(frameRate)
	if rotation, ok := stream.Tags["rotate"]; ok {
		if value, err := strconv.Atoi(rotation); err == nil {
			result.Orientation = pointer(value)
		}
	}
	if len(stream.SideData) > 0 {
		result.Orientation = pointer(stream.SideData[0].Rotation)
	}
}

func milliseconds(value string) *int64 {
	seconds, err := strconv.ParseFloat(value, 64)
	if err != nil || seconds < 0 {
		return nil
	}
	result := int64(math.Round(seconds * 1000))
	return &result
}

func integer64(value string) *int64 {
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return nil
	}
	return &parsed
}
func pointer(value int) *int { return &value }
func fraction(value string) (*int, *int) {
	parts := strings.Split(value, "/")
	if len(parts) != 2 {
		return nil, nil
	}
	num, e1 := strconv.Atoi(parts[0])
	den, e2 := strconv.Atoi(parts[1])
	if e1 != nil || e2 != nil || den <= 0 {
		return nil, nil
	}
	return pointer(num), pointer(den)
}
