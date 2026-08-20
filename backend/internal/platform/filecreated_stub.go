//go:build !windows && !linux && !darwin

package platform

import (
	"os"
	"time"
)

// FileCreatedAt 在未实现出生时间的平台上返回 nil。
func FileCreatedAt(string, os.FileInfo) *time.Time {
	return nil
}
