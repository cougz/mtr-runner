# mtr-runner

A Dockerized MTR (network diagnostic) runner that periodically executes `mtr` against configurable destinations and saves JSON output.

## Features

- Periodic network diagnostics with configurable intervals
- JSON output for easy parsing and analysis
- Multiple destination support
- **Multi-stage build**: Debian 13 (trixie) builder → distroless runtime
- **Rootless**: Runs as non-root user (UID 65532)
- **Distroless**: No shell, no package manager, minimal attack surface
- Automated CI/CD via GitHub Actions

## Architecture

The image uses a multi-stage build:
1. **Builder stage**: `debian:trixie-slim` installs `mtr` and collects all required shared libraries
2. **Runtime stage**: `gcr.io/distroless/python3-debian12:nonroot` contains only `mtr`, its dependencies, and Python 3 for the runner script

## Configuration

Create a `.env` file from the example:

```bash
cp .env.example .env
mkdir -p data
chown 65532:65532 data  # Required for rootless distroless container
```

Edit `.env` with your preferences:

| Variable | Default | Description |
|----------|---------|-------------|
| `MTR_INTERVAL` | `300` | Seconds between full cycles |
| `MTR_COUNT` | `10` | Number of packets per mtr run |
| `MTR_OUTPUT_PATH` | `/data/mtr` | Output directory inside container |
| `MTR_DESTINATIONS` | `1.1.1.1` | Comma-separated list of destinations |

## Local Testing

Build the image:

```bash
docker build -t mtr-runner .
```

Prepare data directory:

```bash
mkdir -p data
chown 65532:65532 data
```

Run with `.env` file:

```bash
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

Verify it's running as nonroot:

```bash
docker run --rm --cap-add=NET_RAW mtr-runner id
# Expected: uid=65532(nonroot) gid=65532(nonroot)
```

> ⚠️ **Important:**
> - `mtr` requires `NET_RAW` capability. Always pass `--cap-add=NET_RAW` when running the container.
> - The container runs as non-root user (UID 65532). Ensure your mounted data directory is writable by this user: `chown 65532:65532 ./data`
> - This is a distroless image — no shell access for debugging

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
# Prepare data directory
sudo mkdir -p /your/host/path
sudo chown 65532:65532 /your/host/path

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
# Prepare data directory
mkdir -p data
chown 65532:65532 data

docker compose up -d
```

## Output Format

Output files are named: `{TIMESTAMP}_{SAFE_DESTINATION}.json`

Example: `20250224T143000Z_1-1-1-1.json`

The JSON output contains the full MTR report for analysis.
