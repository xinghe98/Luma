package config

import (
	"net"
	"strconv"
)

// netJoinHostPort 按平台无关方式组合主机和端口。
func netJoinHostPort(host string, port int) string {
	return net.JoinHostPort(host, strconv.Itoa(port))
}
