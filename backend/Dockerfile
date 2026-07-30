# 构建阶段：使用纯 Go 方式生成不依赖 CGO 的服务端二进制。
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/server/ cmd/server/
COPY internal/ internal/
COPY migrations/ migrations/
COPY pkg/ pkg/
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/luma-server ./cmd/server

# 运行阶段：安装媒体工具并使用非特权用户运行服务。
FROM alpine:3.22
RUN apk add --no-cache ca-certificates ffmpeg su-exec \
    && addgroup -S luma \
    && adduser -S -G luma luma \
    && mkdir -p /data /media /run/luma \
    && chown -R luma:luma /data
COPY --from=build /out/luma-server /usr/local/bin/luma-server
COPY --chmod=0755 scripts/docker-deploy.sh /usr/local/bin/docker-deploy.sh
EXPOSE 8080
VOLUME ["/data"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["docker-deploy.sh", "container-entrypoint"]
CMD ["luma-server", "-config", "/run/luma/config.yaml"]
