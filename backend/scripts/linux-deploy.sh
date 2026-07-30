#!/usr/bin/env sh
# 本脚本构建并管理 Linux systemd 实体部署；它依赖 Go、systemd、生产配置与媒体工具，卸载时保留配置和数据。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ACTION=${1:-install}
VERSION=${2:-${VERSION:-dev}}
SERVICE_NAME=${LUMA_SERVICE_NAME:-luma}
SERVICE_USER=${LUMA_SERVICE_USER:-luma}
CONFIG_PATH=${LUMA_CONFIG_PATH:-/etc/luma/config.yaml}
INSTALL_DIR=${LUMA_INSTALL_DIR:-/opt/luma}
DATA_DIR=${LUMA_DATA_DIR:-/var/lib/luma}
UNIT_PATH="/etc/systemd/system/$SERVICE_NAME.service"

fail() {
    echo "luma linux deploy: $*" >&2
    exit 1
}

# 输出脚本支持的部署动作和覆盖变量。
usage() {
    cat <<'EOF'
用法：
  ./scripts/linux-deploy.sh build [version]
  sudo ./scripts/linux-deploy.sh install
  sudo ./scripts/linux-deploy.sh uninstall

可通过 LUMA_SERVICE_NAME、LUMA_SERVICE_USER、LUMA_CONFIG_PATH、
LUMA_INSTALL_DIR 和 LUMA_DATA_DIR 覆盖默认部署路径。
EOF
}

# 拒绝在非 Linux 系统或不安全的服务标识、相对路径下执行部署。
validate_environment() {
    [ "$(uname -s)" = 'Linux' ] || fail 'physical deployment is supported only on Linux'
    case "$SERVICE_NAME" in
        *[!A-Za-z0-9_.@-]* | '') fail "invalid service name: $SERVICE_NAME" ;;
    esac
    case "$SERVICE_USER" in
        *[!A-Za-z0-9_.@-]* | '') fail "invalid service user: $SERVICE_USER" ;;
    esac
    case "$CONFIG_PATH:$INSTALL_DIR:$DATA_DIR" in
        /*:/*:/*) ;;
        *) fail 'configuration, install, and data paths must be absolute' ;;
    esac
    [ "$INSTALL_DIR" != '/' ] || fail 'install directory must not be the filesystem root'
}

# systemd 安装和卸载会修改系统目录，因此必须由 root 执行。
require_root() {
    [ "$(id -u)" -eq 0 ] || fail 'run this action as root (for example with sudo)'
}

# 构建服务端和管理工具，并将版本写入服务端二进制。
build_binaries() {
    command -v go >/dev/null 2>&1 || fail 'go is not installed'
    mkdir -p "$PROJECT_DIR/dist"
    cd "$PROJECT_DIR"
    CGO_ENABLED=${CGO_ENABLED:-0} go build -trimpath \
        -ldflags "-s -w -X main.version=$VERSION" \
        -o "$PROJECT_DIR/dist/luma-server" ./cmd/server
    CGO_ENABLED=${CGO_ENABLED:-0} go build -trimpath \
        -ldflags "-s -w" \
        -o "$PROJECT_DIR/dist/luma-admin" ./cmd/admin
}

# 安装已构建二进制、校验生产配置并创建或更新 systemd 服务。
install_service() {
    require_root
    command -v systemctl >/dev/null 2>&1 || fail 'systemd is not available'
    command -v runuser >/dev/null 2>&1 || fail 'runuser is not installed'
    [ -x "$PROJECT_DIR/dist/luma-server" ] || fail 'missing dist/luma-server; run the build action first'
    [ -x "$PROJECT_DIR/dist/luma-admin" ] || fail 'missing dist/luma-admin; run the build action first'
    [ -f "$CONFIG_PATH" ] || fail "missing $CONFIG_PATH; create and edit it from configs/config.example.yaml"

    if ! id "$SERVICE_USER" >/dev/null 2>&1; then
        command -v useradd >/dev/null 2>&1 || fail 'useradd is not installed'
        nologin_shell=$(command -v nologin || true)
        [ -n "$nologin_shell" ] || fail 'nologin is not installed'
        useradd --system --user-group --home-dir "$DATA_DIR" --shell "$nologin_shell" "$SERVICE_USER"
    fi
    service_group=$(id -gn "$SERVICE_USER")
    install -d -m 0755 "$INSTALL_DIR"
    install -d -m 0750 -o "$SERVICE_USER" -g "$service_group" "$DATA_DIR"
    install -m 0755 "$PROJECT_DIR/dist/luma-server" "$INSTALL_DIR/luma-server"
    install -m 0755 "$PROJECT_DIR/dist/luma-admin" "$INSTALL_DIR/luma-admin"

    runuser -u "$SERVICE_USER" -- "$INSTALL_DIR/luma-server" \
        -config "$CONFIG_PATH" -check-config -log-format text

    {
        printf '%s\n' '[Unit]'
        printf '%s\n' 'Description=Luma Media Server'
        printf '%s\n' 'After=network-online.target'
        printf '%s\n\n' 'Wants=network-online.target'
        printf '%s\n' '[Service]'
        printf '%s\n' 'Type=simple'
        printf 'User=%s\n' "$SERVICE_USER"
        printf 'Group=%s\n' "$service_group"
        printf 'ExecStart="%s/luma-server" -config "%s"\n' "$INSTALL_DIR" "$CONFIG_PATH"
        printf '%s\n' 'Restart=on-failure'
        printf '%s\n' 'RestartSec=5s'
        printf '%s\n' 'TimeoutStopSec=40s'
        printf '%s\n\n' 'NoNewPrivileges=true'
        printf '%s\n' '[Install]'
        printf '%s\n' 'WantedBy=multi-user.target'
    } > "$UNIT_PATH"

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    systemctl --no-pager --full status "$SERVICE_NAME"
}

# 删除 systemd 注册和程序二进制，但保留配置、数据库及媒体数据。
uninstall_service() {
    require_root
    systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
    rm -f -- "$UNIT_PATH"
    rm -f -- "$INSTALL_DIR/luma-server" "$INSTALL_DIR/luma-admin"
    systemctl daemon-reload
    echo "Removed $SERVICE_NAME. Configuration and data were preserved."
}

validate_environment
case "$ACTION" in
    build) build_binaries ;;
    install) install_service ;;
    uninstall) uninstall_service ;;
    help | -h | --help) usage ;;
    *)
        usage >&2
        fail "unknown action: $ACTION"
        ;;
esac
