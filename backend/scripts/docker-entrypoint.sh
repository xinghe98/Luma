#!/bin/sh
# 将 Compose 生成的只读配置安全复制到容器运行目录，校验后降权启动 Luma 服务。
# 本脚本依赖 su-exec 与 luma 用户；每次容器启动都会重新生成临时配置副本。
set -eu

source_config=/run/luma-config-source.yaml
runtime_config=/run/luma/config.yaml

if [ ! -r "$source_config" ]; then
    echo "luma docker: missing readable configuration at $source_config" >&2
    exit 1
fi

mkdir -p /run/luma
cp "$source_config" "$runtime_config"
chown luma:luma "$runtime_config"
chmod 600 "$runtime_config"

su-exec luma:luma luma-server -config "$runtime_config" -check-config
exec su-exec luma:luma "$@"
