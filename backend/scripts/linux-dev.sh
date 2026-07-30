#!/usr/bin/env sh
# 本脚本在 Linux 上通过 Air 启动后端热重载；它依赖 Go 与 .air.toml，并在前台进程结束时退出。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
AIR_CONFIG_PATH="$PROJECT_DIR/.air.toml"
AIR_VERSION="v1.62.0"

[ "$(uname -s)" = 'Linux' ] || {
    echo 'luma linux dev: this script supports Linux only' >&2
    exit 1
}

cd "$PROJECT_DIR"

# 优先使用已安装的 Air，避免每次启动都经过 go run 的工具解析过程。
if command -v air >/dev/null 2>&1; then
    exec air -c "$AIR_CONFIG_PATH" -- "$@"
fi

echo "未检测到 Air，正在通过 go run 使用 Air $AIR_VERSION。"
exec go run "github.com/air-verse/air@$AIR_VERSION" -c "$AIR_CONFIG_PATH" -- "$@"
