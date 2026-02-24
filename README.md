# mtr-runner

A Dockerized MTR (network diagnostic) runner that periodically executes `mtr` against configurable destinations and saves JSON output.

## Features

- Periodic network diagnostics with configurable intervals
- JSON output for easy parsing and analysis
- Multiple destination support
- **Multi-stage build**: Alpine (mtr static) + Go (runner static) → scratch
- **True minimalism**: Only two static binaries, no shell, no libc, no Python
- **Smallest possible footprint**: ~10MB total
- Automated CI/CD via GitHub Actions

## Architecture

The image uses a three-stage build targeting `FROM scratch`:

1. **mtr-builder**: `debian:trixie-slim` installs build tooling and compiles
   `mtr` from source as a fully static binary using `musl-gcc`
2. **runner-builder**: `golang:1.22-bookworm` compiles the Go runner with
   `CGO_ENABLED=0` producing a fully static binary
3. **Runtime**: `FROM scratch` — contains only two static binaries and
   CA certificates. No shell, no package manager, no libc, no runtime

Final image contains exactly:
- `/usr/bin/mtr` — statically compiled mtr
- `/runner` — statically compiled Go runner
- `/etc/ssl/certs/ca-certificates.crt` — for DNS/TLS
- `/etc/passwd` — for nonroot UID resolution

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
# Create data directory
mkdir -p data
sudo chown 0:0 data  # scratch runs as root (UID 0) inside container

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

Verify it's scratch-based:

```bash
docker run --rm mtr-runner ls /
# Should show only: data  etc  runner  usr
# No /bin/sh, no /usr/bin/python, etc.

docker run --rm mtr-runner sh
# Error: No such file or directory (no shell in scratch)
```

## Building Locally and Pushing to GHCR

```bash
# Login
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# Build (expect several minutes — compiling mtr from source)
docker build -t ghcr.io/cougz/mtr-runner:latest .

# Verify it is scratch-based
docker image inspect ghcr.io/cougz/mtr-runner:latest | grep Size
docker run --rm ghcr.io/cougz/mtr-runner:latest ls 2>&1 || echo "No shell — correct"

# Push
docker push ghcr.io/cougz/mtr-runner:latest

# Tag and push a version
docker tag ghcr.io/cougz/mtr-runner:latest ghcr.io/cougz/mtr-runner:v2.0.0
docker push ghcr.io/cougz/mtr-runner:v2.0.0
```

> ⚠️ **Important:**
> - `mtr` requires `NET_RAW` capability. Always pass `--cap-add=NET_RAW` when running the container.
> - Scratch runs as UID 0 inside the container namespace. Use rootless Docker or user namespaces on the host for security.
> - For bind mounts, the host directory must be writable by the container's UID (typically 0 or mapped to a non-root UID via user namespaces).
> - This is a scratch image — no shell access for debugging.

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
sudo mkdir -p /your/host/path
sudo chown 0:0 /your/host/path
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

The JSON output contains the full MTR report for analysis.
