// MP4 顶层 box 探测：判断 moov 是否在 mdat 之后，供播放前缓存 remux 使用。
// 只读文件头，不改写媒体源。
package media

import (
	"encoding/binary"
	"io"
)

// NeedsFastStart 在 ReadSeeker 上扫描顶层 box。mdat 出现在 moov 之前时返回 true。
// 非 ISO-BMFF 或 moov 已在文件前部时返回 false。调用后把读位置留在检测结束处，调用方负责 Seek(0)。
func NeedsFastStart(reader io.ReadSeeker) (bool, error) {
	if _, err := reader.Seek(0, io.SeekStart); err != nil {
		return false, err
	}
	var sawFtyp, sawMdat bool
	for {
		var header [8]byte
		if _, err := io.ReadFull(reader, header[:]); err != nil {
			if err == io.EOF || err == io.ErrUnexpectedEOF {
				return false, nil
			}
			return false, err
		}
		size := uint64(binary.BigEndian.Uint32(header[0:4]))
		typ := string(header[4:8])
		headerLen := int64(8)
		if size == 1 {
			var ext [8]byte
			if _, err := io.ReadFull(reader, ext[:]); err != nil {
				return false, nil
			}
			size = binary.BigEndian.Uint64(ext[:])
			headerLen = 16
		} else if size == 0 {
			return sawFtyp && sawMdat, nil
		}
		if size < uint64(headerLen) {
			return false, nil
		}
		switch typ {
		case "ftyp":
			sawFtyp = true
		case "mdat":
			sawMdat = true
		case "moov":
			return sawFtyp && sawMdat, nil
		}
		skip := int64(size) - headerLen
		if skip > 0 {
			if _, err := reader.Seek(skip, io.SeekCurrent); err != nil {
				return false, nil
			}
		}
	}
}
