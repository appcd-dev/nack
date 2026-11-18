# syntax=docker/dockerfile:1
# Hardened nats-server-config-reloader 0.25.0.
#
# XRAY-1162975 does not apply. This command does not import nats-server.
# The build fails if v2.15.1 still shows up in the binary.
#
# CVE-2026-4738: same base as the scanned image (Alpine 3.24.2). zlib is
# upgraded from 1.3.2-r0 to 1.4-r0, then the filesystem is copied onto
# scratch. Xray scans that copy, so the old zlib layer is not in the image.
# The shell stays.

FROM --platform=$BUILDPLATFORM golang:1.27.3-alpine3.24 AS build

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .

ENV CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH
RUN go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X main.Version=0.25.0" \
        -o /tmp/nats-server-config-reloader ./cmd/nats-server-config-reloader \
    && if go version -m /tmp/nats-server-config-reloader | grep 'nats-server/v2' | grep -q 'v2.15.1'; then \
         echo "binary still links nats-server v2.15.1" >&2; exit 1; \
       fi

FROM alpine:3.24.2 AS rootfs

RUN set -eux; \
    apk -U upgrade; \
    apk add --no-cache ca-certificates; \
    apk add --no-cache --upgrade 'zlib=1.4-r0'; \
    zlib_ver="$(apk list -I zlib)"; \
    echo "${zlib_ver}"; \
    echo "${zlib_ver}" | grep -q '^zlib-1.4-r0 '; \
    echo "${zlib_ver}" | grep -q '1.3' && exit 1 || true; \
    rm -rf /var/cache/apk; \
    mkdir -p /var/cache/apk /var/run/nats; \
    addgroup -g 1000 nats; \
    adduser -D -u 1000 -G nats nats; \
    chown nats:nats /var/run/nats

COPY --from=build /tmp/nats-server-config-reloader /usr/local/bin/nats-server-config-reloader

RUN ln -s /usr/local/bin/nats-server-config-reloader /nats-server-config-reloader \
    && printf '%s\n' '#!/bin/sh' 'exec "/${GO_APP}" "$@"' > /entrypoint.sh \
    && chmod 755 /entrypoint.sh /usr/local/bin/nats-server-config-reloader

FROM scratch

COPY --from=rootfs / /

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    GO_APP=nats-server-config-reloader

USER nats
ENTRYPOINT ["/entrypoint.sh"]

LABEL org.opencontainers.image.title="nats-server-config-reloader" \
      org.opencontainers.image.source="https://github.com/nats-io/nack" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="0.25.0"
