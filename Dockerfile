# syntax=docker/dockerfile:1
# Hardened nats-server-config-reloader 0.25.0.
# The scanned image was Alpine, and every layer contained zlib 1.3.2-r0.
# This image is one scratch layer. The reloader command does not import
# nats-server. The build fails if v2.15.1 still shows up in the binary.

FROM golang:1.27.3-alpine3.24 AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .

ENV CGO_ENABLED=0
RUN go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X main.Version=0.25.0" \
        -o /tmp/nats-server-config-reloader ./cmd/nats-server-config-reloader \
    && if go version -m /tmp/nats-server-config-reloader | grep 'nats-server/v2' | grep -q 'v2.15.1'; then \
         echo "binary still links nats-server v2.15.1" >&2; exit 1; \
       fi \
    && mkdir -p /out/usr/local/bin \
    && cp /tmp/nats-server-config-reloader /out/usr/local/bin/nats-server-config-reloader

FROM scratch

COPY --from=build /out/ /

ENV PATH="/usr/local/bin"

ENTRYPOINT ["nats-server-config-reloader"]

LABEL org.opencontainers.image.title="nats-server-config-reloader" \
      org.opencontainers.image.source="https://github.com/nats-io/nack" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="0.25.0"
