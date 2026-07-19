package platform

import "time"

// RealClock 使用系统 UTC 时钟提供当前时间。
type RealClock struct{}

// Now 返回当前 UTC 时间。
func (RealClock) Now() time.Time {
	return time.Now().UTC()
}
