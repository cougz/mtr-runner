# syntax=docker/dockerfile:1

# ── Stage 1: builder ─────────────────────────────────────────────────────────
FROM debian:trixie-slim AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mtr-tiny \
    && rm -rf /var/lib/apt/lists/*

# Collect mtr binary and all shared libs it needs into /collect
RUN mkdir -p /collect/usr/bin /collect/lib/$(uname -m)-linux-gnu

RUN cp /usr/bin/mtr /collect/usr/bin/mtr

# Copy all shared libraries mtr depends on
RUN ldd /usr/bin/mtr | awk '/=>/ {print $3}' | xargs -I{} cp --parents {} /collect && \
    ldd /usr/bin/mtr | awk '/ld-linux/ {print $1}' | xargs -I{} cp --parents {} /collect || true

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
# gcr.io/distroless/python3-debian12 is rootless by default (nonroot tag = uid 65532)
FROM gcr.io/distroless/python3-debian12:nonroot

# Copy mtr binary and its libs from builder
COPY --from=builder /collect/ /

# Copy our runner script
COPY runner.py /app/runner.py

# Output volume — mount your host path here
VOLUME ["/data/mtr"]

# nonroot user (uid 65532) is the default in the :nonroot tag
# No USER directive needed — distroless:nonroot already sets this

ENV MTR_BIN=/usr/bin/mtr \
    MTR_INTERVAL=300 \
    MTR_COUNT=10 \
    MTR_OUTPUT_PATH=/data/mtr \
    MTR_DESTINATIONS=1.1.1.1

ENTRYPOINT ["python3", "/app/runner.py"]
