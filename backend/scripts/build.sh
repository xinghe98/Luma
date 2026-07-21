#!/usr/bin/env sh
# 本脚本构建带版本信息的 Linux/macOS 服务端二进制。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VERSION=${VERSION:-dev}

mkdir -p "$PROJECT_DIR/dist"
cd "$PROJECT_DIR"
CGO_ENABLED=${CGO_ENABLED:-0} go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$PROJECT_DIR/dist/luma-server" ./cmd/server
