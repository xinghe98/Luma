package media

import (
	"bytes"
	"testing"
	"time"
)

func TestParseProbeJSONVideo(t *testing.T) {
	raw := []byte(`{"streams":[{"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"avg_frame_rate":"30000/1001","tags":{"rotate":"90"},"side_data_list":[{"rotation":-90}]},{"codec_type":"audio","codec_name":"aac"},{"codec_type":"audio","codec_name":"opus"}],"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"12.345","bit_rate":"456789","tags":{"title":"Stage 3","creation_time":"2025-06-07T08:09:10Z"}}}`)

	got, err := parseProbeJSON(raw)
	if err != nil {
		t.Fatalf("parseProbeJSON() error = %v", err)
	}
	if got.Title != "Stage 3" || got.Container != "mov,mp4,m4a,3gp,3g2,mj2" {
		t.Fatalf("title/container = %q/%q", got.Title, got.Container)
	}
	assertInt64Pointer(t, "duration", got.DurationMS, 12345)
	assertInt64Pointer(t, "bitrate", got.Bitrate, 456789)
	assertIntPointer(t, "width", got.Width, 1920)
	assertIntPointer(t, "height", got.Height, 1080)
	assertIntPointer(t, "frame rate numerator", got.FrameRateNum, 30000)
	assertIntPointer(t, "frame rate denominator", got.FrameRateDen, 1001)
	assertIntPointer(t, "rotation", got.Orientation, -90)
	if got.VideoCodec != "h264" || got.AudioCodec != "aac" || got.AudioTrackCount != 2 {
		t.Fatalf("codecs/audio = %q/%q/%d", got.VideoCodec, got.AudioCodec, got.AudioTrackCount)
	}
	wantCaptured := time.Date(2025, 6, 7, 8, 9, 10, 0, time.UTC)
	if got.CapturedAt == nil || !got.CapturedAt.Equal(wantCaptured) {
		t.Fatalf("capturedAt = %v, want %v", got.CapturedAt, wantCaptured)
	}
	if !bytes.Equal(got.RawJSON, raw) || got.Version != 1 {
		t.Fatalf("raw/version = %q/%d", got.RawJSON, got.Version)
	}
}

func TestParseProbeJSONImageAndMissingFields(t *testing.T) {
	t.Run("image", func(t *testing.T) {
		got, err := parseProbeJSON([]byte(`{"streams":[{"codec_type":"video","codec_name":"png","width":800,"height":600}],"format":{"format_name":"png_pipe"}}`))
		if err != nil {
			t.Fatal(err)
		}
		if got.VideoCodec != "png" || got.Container != "png_pipe" {
			t.Fatalf("codec/container = %q/%q", got.VideoCodec, got.Container)
		}
		assertIntPointer(t, "width", got.Width, 800)
		assertIntPointer(t, "height", got.Height, 600)
		if got.DurationMS != nil || got.Bitrate != nil || got.FrameRateNum != nil || got.CapturedAt != nil {
			t.Fatalf("optional image fields should be nil: %+v", got)
		}
	})

	t.Run("missing fields", func(t *testing.T) {
		got, err := parseProbeJSON([]byte(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		if got.Title != "" || got.VideoCodec != "" || got.AudioTrackCount != 0 || got.DurationMS != nil || got.Width != nil {
			t.Fatalf("unexpected metadata: %+v", got)
		}
		if got.Version != 1 || string(got.RawJSON) != `{}` {
			t.Fatalf("raw/version = %q/%d", got.RawJSON, got.Version)
		}
	})
}

func TestParseProbeJSONRejectsInvalidJSON(t *testing.T) {
	if _, err := parseProbeJSON([]byte(`{"streams":`)); err == nil {
		t.Fatal("parseProbeJSON() error = nil, want invalid JSON error")
	}
}

func TestParseProbeJSONPrefersVideoStreamDuration(t *testing.T) {
	raw := []byte(`{"streams":[{"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"duration":"20.530000","avg_frame_rate":"30/1"},{"codec_type":"audio","codec_name":"aac"}],"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"2898.175000"}}`)
	got, err := parseProbeJSON(raw)
	if err != nil {
		t.Fatal(err)
	}
	assertInt64Pointer(t, "duration", got.DurationMS, 20530)
}

func TestParseProbeJSONSkipsAttachedPicture(t *testing.T) {
	raw := []byte(`{"streams":[
		{"codec_type":"video","codec_name":"mjpeg","width":600,"height":600,"disposition":{"attached_pic":1}},
		{"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"avg_frame_rate":"24/1"},
		{"codec_type":"audio","codec_name":"aac"}
	],"format":{"format_name":"matroska,webm","duration":"10"}}`)
	got, err := parseProbeJSON(raw)
	if err != nil {
		t.Fatal(err)
	}
	if got.VideoCodec != "h264" {
		t.Fatalf("VideoCodec = %q, want h264", got.VideoCodec)
	}
	assertIntPointer(t, "width", got.Width, 1920)
	assertIntPointer(t, "height", got.Height, 1080)
}

func assertIntPointer(t *testing.T, name string, got *int, want int) {
	t.Helper()
	if got == nil || *got != want {
		t.Fatalf("%s = %v, want %d", name, got, want)
	}
}

func assertInt64Pointer(t *testing.T, name string, got *int64, want int64) {
	t.Helper()
	if got == nil || *got != want {
		t.Fatalf("%s = %v, want %d", name, got, want)
	}
}
