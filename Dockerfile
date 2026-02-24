# syntax=docker/dockerfile:1

# ── Stage 1: Build mtr statically ────────────────────────────────────────────
FROM debian:trixie-slim AS mtr-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    autoconf \
    automake \
    libcap-dev \
    libncurses-dev \
    libjansson-dev \
    musl-tools \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/traviscross/mtr.git /mtr-src

WORKDIR /mtr-src

RUN autoreconf -i && \
    CC=musl-gcc LDFLAGS="-static" ./configure \
        --without-gtk \
        --disable-shared \
        --enable-static && \
    make -j$(nproc)

# Confirm it is truly static — ldd should say "not a dynamic executable"
RUN file /mtr-src/mtr && \
    ldd /mtr-src/mtr 2>&1 | grep -q "not a dynamic" && \
    echo "SUCCESS: mtr is fully static" || \
    (echo "FAIL: mtr is not static" && exit 1)

# ── Stage 2: Build Go runner statically ──────────────────────────────────────
FROM golang:1.22-bookworm AS runner-builder

WORKDIR /src
COPY go.mod runner.go ./

RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -o runner .

# Confirm static
RUN file /src/runner && \
    ldd /src/runner 2>&1 | grep -q "not a dynamic" && \
    echo "SUCCESS: runner is fully static" || \
    (echo "FAIL: runner is not static" && exit 1)

# ── Stage 3: Scratch runtime ──────────────────────────────────────────────────
FROM scratch

# CA certificates for DNS resolution
COPY --from=mtr-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Static mtr binary
COPY --from=mtr-builder /mtr-src/mtr /usr/bin/mtr

# Static Go runner binary
COPY --from=runner-builder /src/runner /runner

# /etc/passwd so nonroot uid is resolvable
COPY --from=mtr-builder /etc/passwd /etc/passwd

VOLUME ["/data/mtr"]

USER 65532

ENV MTR_BIN=/usr/bin/mtr \
    MTR_INTERVAL=300 \
    MTR_COUNT=10 \
    MTR_OUTPUT_PATH=/data/mtr \
    MTR_DESTINATIONS=1.1.1.1

ENTRYPOINT ["/runner"]
