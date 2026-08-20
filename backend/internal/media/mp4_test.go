package media

import (
	"bytes"
	"encoding/binary"
	"io"
	"testing"
)

func TestNeedsFastStartDetectsMoovAfterMdat(t *testing.T) {
	mdatFirst := concatBoxes(
		box("ftyp", []byte("isom")),
		box("mdat", bytes.Repeat([]byte{1}, 32)),
		box("moov", []byte("mvhd")),
	)
	needed, err := NeedsFastStart(bytes.NewReader(mdatFirst))
	if err != nil || !needed {
		t.Fatalf("mdat-first needed=%v err=%v", needed, err)
	}

	faststart := concatBoxes(
		box("ftyp", []byte("isom")),
		box("moov", []byte("mvhd")),
		box("mdat", bytes.Repeat([]byte{1}, 32)),
	)
	needed, err = NeedsFastStart(bytes.NewReader(faststart))
	if err != nil || needed {
		t.Fatalf("faststart needed=%v err=%v", needed, err)
	}
}

func TestNeedsFastStartIgnoresNonMP4(t *testing.T) {
	needed, err := NeedsFastStart(bytes.NewReader([]byte("not an mp4")))
	if err != nil || needed {
		t.Fatalf("needed=%v err=%v", needed, err)
	}
}

func TestNeedsFastStartRewindIsCallerDuty(t *testing.T) {
	payload := concatBoxes(
		box("ftyp", []byte("isom")),
		box("moov", []byte("mvhd")),
		box("mdat", []byte{1, 2, 3, 4}),
	)
	reader := bytes.NewReader(payload)
	if _, err := NeedsFastStart(reader); err != nil {
		t.Fatal(err)
	}
	if reader.Len() == len(payload) {
		t.Fatal("探测器不应替调用方 Seek(0)")
	}
	if _, err := reader.Seek(0, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	if reader.Len() != len(payload) {
		t.Fatalf("rewind len=%d want %d", reader.Len(), len(payload))
	}
}

func concatBoxes(parts ...[]byte) []byte {
	return bytes.Join(parts, nil)
}

func box(typ string, payload []byte) []byte {
	size := 8 + len(payload)
	buf := make([]byte, size)
	binary.BigEndian.PutUint32(buf, uint32(size))
	copy(buf[4:8], typ)
	copy(buf[8:], payload)
	return buf
}
