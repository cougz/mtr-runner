# syntax=docker/dockerfile:1

# ── Stage 1: Build mtr statically ────────────────────────────────────────────
FROM alpine:3.20 AS mtr-builder

RUN apk add --no-cache \
    alpine-sdk \
    automake \
    autoconf \
    jansson-dev \
    musl-dev \
    linux-headers \
    git

RUN git clone --depth=1 https://github.com/traviscross/mtr.git /mtr-src

WORKDIR /mtr-src

RUN autoreconf -i && \
    ./configure \
        --without-gtk \
        --without-cap && \
    make -j$(nproc) && \
    strip mtr mtr-packet

# Verify mtr binary exists and has JSON support
RUN /mtr-src/mtr --help 2>&1 | grep -q json && echo "SUCCESS: mtr has JSON support" || exit 1

# ── Stage 2: Build Go runner statically ──────────────────────────────────────
FROM golang:1.22-bookworm AS runner-builder

WORKDIR /src
COPY go.mod runner.go ./

RUN apt-get update && apt-get install -y --no-install-recommends file && \
    rm -rf /var/lib/apt/lists/*

RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -o runner .

# Confirm static
RUN file /src/runner && \
    ldd /src/runner 2>&1 | grep -q "not a dynamic" && \
    echo "SUCCESS: runner is fully static" || \
    (echo "FAIL: runner is not static" && exit 1)

# ── Stage 3: Scratch runtime ──────────────────────────────────────────────────
FROM alpine:3.20

# Copy libraries needed by mtr
COPY --from=mtr-builder /lib/ld-musl-x86_64.so.1 /lib/
COPY --from=mtr-builder /lib/libc.musl-x86_64.so.1 /lib/
COPY --from=mtr-builder /usr/lib/libjansson.so.4 /usr/lib/

# Copy mtr binaries
COPY --from=mtr-builder /mtr-src/mtr /usr/bin/mtr
COPY --from=mtr-builder /mtr-src/mtr-packet /usr/bin/mtr-packet

# Static Go runner binary
COPY --from=runner-builder /src/runner /runner

VOLUME ["/data/mtr"]

ENV MTR_BIN=/usr/bin/mtr \
    MTR_INTERVAL=300 \
    MTR_COUNT=10 \
    MTR_OUTPUT_PATH=/data/mtr \
    MTR_DESTINATIONS=1.1.1.1

ENTRYPOINT ["/runner"]
