#!/usr/bin/env sh
# 创建或复用家庭成员，授予一个或多个媒体源，并签发仅显示一次的设备 Token。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SERVER="http://127.0.0.1:8080"
ADMIN_TOKEN_FILE="$PROJECT_DIR/data/secrets/api_token"
ADMIN_EXECUTABLE="$PROJECT_DIR/dist/luma-admin"
NAME=""
USER_ID=""
TOKEN_NAME="家庭设备"
EXPIRES_AT=""
SOURCE_IDS=""
ALLOW_INSECURE=0

usage() {
    cat <<'EOF'
用法：
  issue-family-token.sh --name NAME --source SOURCE_ID [--source SOURCE_ID ...] [选项]
  issue-family-token.sh --user-id USER_ID --source SOURCE_ID [--source SOURCE_ID ...] [选项]

选项：
  --token-name NAME           设备 Token 名称，默认“家庭设备”
  --expires RFC3339           可选过期时间，例如 2027-01-01T00:00:00Z
  --server URL                默认 http://127.0.0.1:8080
  --admin-token-file PATH     管理员根 Token 文件
  --admin-executable PATH     luma-admin 路径；不存在时自动构建
  --allow-insecure            允许向非回环 HTTP 地址发送管理请求
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) NAME=${2-}; shift 2 ;;
        --user-id) USER_ID=${2-}; shift 2 ;;
        --source)
            [ -n "${2-}" ] || { echo "--source 不能为空" >&2; exit 2; }
            SOURCE_IDS="$SOURCE_IDS ${2}"
            shift 2
            ;;
        --token-name) TOKEN_NAME=${2-}; shift 2 ;;
        --expires) EXPIRES_AT=${2-}; shift 2 ;;
        --server) SERVER=${2-}; shift 2 ;;
        --admin-token-file) ADMIN_TOKEN_FILE=${2-}; shift 2 ;;
        --admin-executable) ADMIN_EXECUTABLE=${2-}; shift 2 ;;
        --allow-insecure) ALLOW_INSECURE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
    esac
done

if { [ -z "$NAME" ] && [ -z "$USER_ID" ]; } || { [ -n "$NAME" ] && [ -n "$USER_ID" ]; }; then
    echo "必须且只能提供 --name 或 --user-id 其中一个" >&2
    exit 2
fi
if [ -z "${SOURCE_IDS# }" ]; then
    echo "至少提供一个 --source" >&2
    exit 2
fi
if [ -z "$TOKEN_NAME" ]; then
    echo "--token-name 不能为空" >&2
    exit 2
fi

if [ ! -x "$ADMIN_EXECUTABLE" ]; then
    mkdir -p "$(dirname -- "$ADMIN_EXECUTABLE")"
    echo "未找到 luma-admin，正在构建…" >&2
    (cd "$PROJECT_DIR" && go build -trimpath -o "$ADMIN_EXECUTABLE" ./cmd/admin)
fi

set -- "$ADMIN_EXECUTABLE" -server "$SERVER" -token-file "$ADMIN_TOKEN_FILE"
if [ "$ALLOW_INSECURE" -eq 1 ]; then
    set -- "$@" -allow-insecure
fi
set -- "$@" family issue
if [ -n "$USER_ID" ]; then
    set -- "$@" -user "$USER_ID"
else
    set -- "$@" -name "$NAME"
fi
for SOURCE_ID in $SOURCE_IDS; do
    set -- "$@" -source "$SOURCE_ID"
done
set -- "$@" -token-name "$TOKEN_NAME"
if [ -n "$EXPIRES_AT" ]; then
    set -- "$@" -expires "$EXPIRES_AT"
fi

echo "警告：响应中的 issued_token.token 明文只显示一次，请立即保存到目标设备的安全凭据存储。" >&2
exec "$@"
