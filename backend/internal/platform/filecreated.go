package platform

import "time"

// unixMilliPointer 丢弃零值和 Unix epoch 之前的时间，避免把无效出生时间写入索引。
func unixMilliPointer(value time.Time) *time.Time {
	if value.IsZero() || value.Unix() <= 0 {
		return nil
	}
	utc := value.UTC()
	return &utc
}
