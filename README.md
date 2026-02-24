# mtr-runner

A Dockerized MTR (network diagnostic) runner that periodically executes `mtr` against configurable destinations and saves JSON output.

## Features

- Periodic network diagnostics with configurable intervals
- JSON output for easy parsing and analysis
- Multiple destination support
- Small Docker image (~60MB) based on Debian Bookworm
- Automated CI/CD via GitHub Actions

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

Build the image:

```bash
docker build -t mtr-runner .
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

> ⚠️ **Important:** `mtr` requires `NET_RAW` capability. Always pass `--cap-add=NET_RAW` when running the container.

## GitHub Actions CI/CD

The workflow automatically builds and publishes Docker images to GitHub Container Registry (ghcr.io) on:
- Push to `main` branch
- Tags matching `v*`
- Manual workflow dispatch

### Initial Git Setup

```bash
git init
git add .
git commit -m "feat: initial mtr-runner with GitHub Actions CI"

# Add your GitHub remote (replace with your actual repo)
git remote add origin https://github.com/YOUR_USERNAME/mtr-runner.git

# Push to main — this triggers the workflow automatically
git push -u origin main
```

### Pull from GHCR

After the workflow completes, pull the image:

```bash
docker pull ghcr.io/YOUR_USERNAME/mtr-runner:latest
```

Run the published image:

```bash
docker run -d \
  --name mtr-runner \
  --cap-add=NET_RAW \
  --restart unless-stopped \
  --env-file .env \
  -v /your/host/path:/data/mtr \
  ghcr.io/YOUR_USERNAME/mtr-runner:latest
```

## Output Format

Output files are named: `{TIMESTAMP}_{SAFE_DESTINATION}.json`

Example: `20250224T143000Z_1-1-1-1.json`

The JSON output contains the full MTR report for analysis.
