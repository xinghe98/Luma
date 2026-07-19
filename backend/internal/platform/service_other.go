//go:build !windows

package platform

import "context"

// RunWindowsService 在非 Windows 平台返回未进入服务模式。
func RunWindowsService(_ string, _ func(context.Context) error) (bool, error) {
	return false, nil
}
