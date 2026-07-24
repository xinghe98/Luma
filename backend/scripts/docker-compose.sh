#!/usr/bin/env sh
# 根据 .env 生成 Luma Docker 的媒体挂载与运行时配置，并将参数转交给 Docker Compose。
# 它与 docker-compose.yml、config.docker.yaml 协作；每次运行都会覆盖 backend/.cache/docker 中的派生文件。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE="$PROJECT_DIR/.env"
GENERATED_DIR="$PROJECT_DIR/.cache/docker"
GENERATED_CONFIG="$GENERATED_DIR/config.yaml"
GENERATED_COMPOSE="$GENERATED_DIR/docker-compose.generated.yaml"
ROOTS_FILE="$GENERATED_DIR/allowed-roots.yaml"
MEDIA_ENTRIES_FILE="$GENERATED_DIR/media-entries"

fail() {
    echo "luma docker: $*" >&2
    exit 1
}

yaml_quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/''/g"
    printf "'"
}

[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE; copy .env.example to .env and configure it"

# .env 由部署管理员维护，只接受标准 shell 变量赋值，以便同时传给 Docker Compose。
set -a
. "$ENV_FILE"
set +a

: "${LUMA_PORT:=8080}"
: "${LUMA_VERSION:=dev}"
: "${LUMA_MEDIA_DIRS:?set LUMA_MEDIA_DIRS in .env}"

mkdir -p "$GENERATED_DIR"
: > "$ROOTS_FILE"
: > "$GENERATED_COMPOSE"
printf '%s\n' "$LUMA_MEDIA_DIRS" | tr ',' '\n' > "$MEDIA_ENTRIES_FILE"

{
    printf '%s\n' 'services:'
    printf '%s\n' '  luma-server:'
    printf '%s\n' '    volumes:'
    printf '%s' '      - '
    yaml_quote "$GENERATED_CONFIG:/etc/luma/config.yaml:ro"
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
        *) printf '%s\n' "$line" ;;
    esac
done < "$PROJECT_DIR/configs/config.docker.yaml" > "$GENERATED_CONFIG"

exec docker compose --env-file "$ENV_FILE" \
    -f "$PROJECT_DIR/docker-compose.yml" \
    -f "$GENERATED_COMPOSE" \
    "$@"
