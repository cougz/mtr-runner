# mtr-runner

A Dockerized MTR (network diagnostic) runner that periodically executes `mtr` against configurable destinations and saves JSON output.

## Features

- Periodic network diagnostics with configurable intervals
- **Native JSON output** from mtr for easy parsing and analysis
- Multiple destination support
- **Multi-stage build**: Alpine 3.20 (mtr with JSON support) + Go (runner static) → Alpine runtime
- **Minimal footprint**: Alpine-based (~10-15MB) with mtr built from source including jansson library
- Automated CI/CD via GitHub Actions

## Architecture

The image uses a three-stage build:

1. **mtr-builder**: `alpine:3.20` with Alpine SDK installs build tooling and compiles
   `mtr` from source with jansson support for JSON output
2. **runner-builder**: `golang:1.22-bookworm` compiles the Go runner with
   `CGO_ENABLED=0` producing a fully static binary
3. **Runtime**: `FROM alpine:3.20` — contains mtr binaries, runner,
   and required libraries (musl, jansson)

Final image contains:
- `/usr/bin/mtr` — mtr compiled from source with JSON support
- `/usr/bin/mtr-packet` — packet helper binary
- `/runner` — statically compiled Go runner
- `/lib/libc.musl-x86_64.so.1` — musl C library
- `/lib/ld-musl-x86_64.so.1` — musl dynamic linker
- `/usr/lib/libjansson.so.4` — jansson library for JSON support

## Configuration

Create a `.env` file from the example:

```bash
cp .env.example .env
```

Edit `.env` with your preferences:

| Variable | Default | Description |
|----------|---------|-------------|
| `MTR_INTERVAL` | `300` | Seconds between full cycles |
| `MTR_COUNT` | `10` | Number of packets per mtr run |
| `MTR_OUTPUT_PATH` | `/data/mtr` | Output directory inside container |
| `MTR_DESTINATIONS` | `1.1.1.1` | Comma-separated list of destinations |

## Local Testing

Build the image (takes a few minutes, compiles mtr from source):

```bash
docker build -t mtr-runner .
```

Run with `.env` file (bind mount):

```bash
mkdir -p data

docker run --rm \
  --cap-add=NET_RAW \
  --env-file .env \
  -v $(pwd)/data:/data/mtr \
  mtr-runner
```

Run with inline env vars:

```bash
docker run --rm \
  --cap-add=NET_RAW \
  -e MTR_INTERVAL=60 \
  -e MTR_COUNT=10 \
  -e MTR_DESTINATIONS="1.1.1.1,8.8.8.8,custom-t0.speed.cloudflare.com" \
  -e MTR_OUTPUT_PATH=/data/mtr \
  -v $(pwd)/data:/data/mtr \
  mtr-runner
```

## Building Locally and Pushing to GHCR

```bash
# Login
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# Build (expect several minutes — compiling mtr from source)
docker build -t ghcr.io/cougz/mtr-runner:latest .

# Push
docker push ghcr.io/cougz/mtr-runner:latest

# Tag and push a version
docker tag ghcr.io/cougz/mtr-runner:latest ghcr.io/cougz/mtr-runner:v2.0.0
docker push ghcr.io/cougz/mtr-runner:v2.0.0
```

> ⚠️ **Important:**
> - `mtr` requires `NET_RAW` capability. Always pass `--cap-add=NET_RAW` when running the container.

## GitHub Actions CI/CD

The workflow automatically builds and publishes Docker images to GitHub Container Registry (ghcr.io) on:
- Push to `main` branch
- Tags matching `v*`
- Manual workflow dispatch

### Pull from GHCR

After the workflow completes, pull the image:

```bash
docker pull ghcr.io/YOUR_USERNAME/mtr-runner:latest
```

Run the published image:

```bash
# With named volume
docker run -d \
  --name mtr-runner \
  --cap-add=NET_RAW \
  --restart unless-stopped \
  --env-file .env \
  -v mtr-data:/data/mtr \
  ghcr.io/YOUR_USERNAME/mtr-runner:latest

# Or with bind mount
mkdir -p /your/host/path
docker run -d \
  --name mtr-runner \
  --cap-add=NET_RAW \
  --restart unless-stopped \
  --env-file .env \
  -v /your/host/path:/data/mtr \
  ghcr.io/YOUR_USERNAME/mtr-runner:latest
```

### Docker Compose

```bash
docker compose up -d
```

## Output Format

Output files are named: `{TIMESTAMP}_{SAFE_DESTINATION}.json`

Example: `20250224T143000Z_1-1-1-1.json`

The JSON output contains the full MTR report including:
- Source and destination information
- Packet statistics (count, loss%, best/worst/avg latency)
- All hops with individual statistics
