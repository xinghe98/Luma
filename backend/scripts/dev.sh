#!/usr/bin/env sh
# 本脚本从任意工作目录通过 Air 启动可热重载的本地开发服务器。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
AIR_CONFIG_PATH="$PROJECT_DIR/.air.toml"
AIR_VERSION="v1.62.0"

cd "$PROJECT_DIR"

# 优先使用已安装的 Air，避免每次启动都经过 go run 的工具解析过程。
if command -v air >/dev/null 2>&1; then
    exec air -c "$AIR_CONFIG_PATH" -- "$@"
fi

# 未安装 Air 时使用与 Go 1.24 兼容的固定版本，并由 Go 构建缓存复用工具产物。
echo "未检测到 Air，正在通过 go run 使用 Air $AIR_VERSION。"
exec go run "github.com/air-verse/air@$AIR_VERSION" -c "$AIR_CONFIG_PATH" -- "$@"
