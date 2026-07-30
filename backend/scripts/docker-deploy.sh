#!/usr/bin/env sh
# 本脚本统一处理 Linux 宿主机的 Docker Compose 部署和容器启动；它依赖 .env、Compose 与 Dockerfile，并会重建派生配置。
set -eu
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
    echo "luma docker: $*" >&2
    exit 1
}

# 将任意文本转成单引号包裹的 YAML 标量。
yaml_quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/''/g"
    printf "'"
}

# 容器启动时复制只读配置、校验运行依赖，再降权运行服务。
run_container() {
    source_config=/run/luma-config-source.yaml
    runtime_config=/run/luma/config.yaml
    shift

    [ -r "$source_config" ] || fail "missing readable configuration at $source_config"
    [ "$#" -gt 0 ] || fail 'missing container command'

    mkdir -p /run/luma
    cp "$source_config" "$runtime_config"
    chown luma:luma "$runtime_config"
    chmod 600 "$runtime_config"

    su-exec luma:luma luma-server -config "$runtime_config" -check-config
    exec su-exec luma:luma "$@"
}

if [ "${1:-}" = 'container-entrypoint' ]; then
    run_container "$@"
fi

ENV_FILE="$PROJECT_DIR/.env"
GENERATED_DIR="$PROJECT_DIR/.cache/docker"
GENERATED_CONFIG="$GENERATED_DIR/config.yaml"
GENERATED_COMPOSE="$GENERATED_DIR/docker-compose.generated.yaml"
ROOTS_FILE="$GENERATED_DIR/allowed-roots.yaml"
MEDIA_ENTRIES_FILE="$GENERATED_DIR/media-entries"

[ "$(uname -s)" = 'Linux' ] || fail 'Docker deployment is supported only on Linux'
[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE; copy .env.example to .env and configure it"
command -v docker >/dev/null 2>&1 || fail 'docker is not installed'

# .env 由部署管理员维护，只接受标准 shell 变量赋值，以便同时传给 Docker Compose。
set -a
. "$ENV_FILE"
set +a

: "${LUMA_PORT:=8080}"
: "${LUMA_VERSION:=dev}"
: "${LUMA_MEDIA_DIRS:?set LUMA_MEDIA_DIRS in .env}"
: "${LUMA_TMDB_ENABLED:=false}"
: "${LUMA_TMDB_ACCESS_TOKEN:=}"

case "$LUMA_TMDB_ENABLED" in
    true | false) ;;
    *) fail "LUMA_TMDB_ENABLED must be true or false" ;;
esac
[ "$LUMA_TMDB_ENABLED" = false ] || [ -n "$LUMA_TMDB_ACCESS_TOKEN" ] ||
    fail "LUMA_TMDB_ACCESS_TOKEN is required when LUMA_TMDB_ENABLED=true"

mkdir -p "$GENERATED_DIR"
: > "$ROOTS_FILE"
: > "$GENERATED_COMPOSE"
printf '%s\n' "$LUMA_MEDIA_DIRS" | tr ',' '\n' > "$MEDIA_ENTRIES_FILE"

{
    printf '%s\n' 'services:'
    printf '%s\n' '  luma-server:'
    printf '%s\n' '    volumes:'
    printf '%s' '      - '
    yaml_quote "$GENERATED_CONFIG:/run/luma-config-source.yaml:ro"
    printf '\n'
} > "$GENERATED_COMPOSE"

used_aliases=''
media_count=0
echo "Luma Docker configuration: version=$LUMA_VERSION port=$LUMA_PORT" >&2
while IFS= read -r entry || [ -n "$entry" ]; do
    [ -n "$entry" ] || fail 'LUMA_MEDIA_DIRS must not contain an empty entry'
    case "$entry" in
        *=*)
            host_path=${entry%%=*}
            alias=${entry#*=}
            ;;
        *) fail "invalid media entry $entry; expected /host/path=container-name" ;;
    esac
    [ -n "$host_path" ] && [ -n "$alias" ] || fail "invalid media entry $entry"
    case "$host_path" in
        /*) ;;
        *) fail "media directory must be absolute: $host_path" ;;
    esac
    case "$alias" in
        *[!A-Za-z0-9_-]* | '') fail "invalid container directory name: $alias" ;;
    esac
    case " $used_aliases " in
        *" $alias "*) fail "duplicate container directory name: $alias" ;;
    esac
    [ -d "$host_path" ] || fail "media directory does not exist: $host_path"
    used_aliases="$used_aliases $alias"
    container_path="/media/$alias"
    media_count=$((media_count + 1))

    printf '    - ' >> "$ROOTS_FILE"
    yaml_quote "$container_path" >> "$ROOTS_FILE"
    printf '\n' >> "$ROOTS_FILE"
    printf '      - ' >> "$GENERATED_COMPOSE"
    yaml_quote "$host_path:$container_path:ro" >> "$GENERATED_COMPOSE"
    printf '\n' >> "$GENERATED_COMPOSE"
    printf '  %s -> %s (read-only)\n' "$host_path" "$container_path" >&2
done < "$MEDIA_ENTRIES_FILE"
[ "$media_count" -gt 0 ] || fail 'LUMA_MEDIA_DIRS must contain at least one directory'

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        '  allowed_roots:'*)
            printf '%s\n' '  allowed_roots:'
            cat "$ROOTS_FILE"
            ;;
        '      enabled: __LUMA_TMDB_ENABLED__')
            printf '      enabled: %s\n' "$LUMA_TMDB_ENABLED"
            ;;
        '        access_token: __LUMA_TMDB_ACCESS_TOKEN__')
            printf '%s' '        access_token: '
            yaml_quote "$LUMA_TMDB_ACCESS_TOKEN"
            printf '\n'
            ;;
        *) printf '%s\n' "$line" ;;
    esac
done < "$PROJECT_DIR/configs/config.docker.yaml" > "$GENERATED_CONFIG"

exec docker compose --env-file "$ENV_FILE" \
    -f "$PROJECT_DIR/docker-compose.yml" \
    -f "$GENERATED_COMPOSE" \
    "$@"
