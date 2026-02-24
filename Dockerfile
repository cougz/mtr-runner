# syntax=docker/dockerfile:1
# ── Stage 1: builder ─────────────────────────────────────────────────────────
FROM debian:trixie-slim AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends mtr-tiny && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /collect/usr/bin /collect/lib/$(uname -m)-linux-gnu
RUN cp /usr/bin/mtr /collect/usr/bin/mtr
RUN ldd /usr/bin/mtr | awk '/=>/ {print $3}' | xargs -I{} cp --parents {} /collect && \
    ldd /usr/bin/mtr | awk '/ld-linux/ {print $1}' | xargs -I{} cp --parents {} /collect || true

# Pre-create output dir with correct ownership for nonroot uid
RUN mkdir -p /data/mtr && chown 65532:65532 /data/mtr

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM gcr.io/distroless/python3-debian12:nonroot

COPY --from=builder /collect/ /
COPY --from=builder /data/mtr /data/mtr   # brings in 65532-owned dir
COPY runner.py /app/runner.py

# VOLUME after directory exists with correct ownership
VOLUME ["/data/mtr"]

ENV MTR_BIN=/usr/bin/mtr \
    MTR_INTERVAL=300 \
    MTR_COUNT=10 \
    MTR_OUTPUT_PATH=/data/mtr \
    MTR_DESTINATIONS=1.1.1.1

ENTRYPOINT ["python3", "/app/runner.py"]
