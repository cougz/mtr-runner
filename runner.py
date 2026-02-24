#!/usr/bin/env python3
"""
mtr-runner: periodically runs mtr against configured destinations
and saves JSON output to a configurable path.
"""

import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


def get_env(key: str, default: str) -> str:
    return os.environ.get(key, default).strip()


def sanitize(dest: str) -> str:
    return dest.replace(".", "-").replace(":", "-").replace("/", "-")


def run_mtr(mtr_bin: str, dest: str, count: int, output_path: Path) -> None:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    outfile = output_path / f"{timestamp}_{sanitize(dest)}.json"

    print(f"[mtr-runner] Running mtr to {dest} -> {outfile}", flush=True)

    try:
        result = subprocess.run(
            [mtr_bin, "-j", "-c", str(count), dest],
            capture_output=True,
            text=True,
            timeout=count * 5 + 30,  # generous timeout
        )

        if result.returncode != 0:
            print(f"[mtr-runner] WARNING: mtr exited {result.returncode} for {dest}", flush=True)

        # Try to parse as JSON to validate, fall back to raw output
        raw = result.stdout.strip() if result.stdout.strip() else result.stderr.strip()
        try:
            data = json.loads(raw)
            outfile.write_text(json.dumps(data, indent=2))
        except json.JSONDecodeError:
            outfile.write_text(raw)
            print(f"[mtr-runner] WARNING: Output for {dest} was not valid JSON", flush=True)

    except subprocess.TimeoutExpired:
        print(f"[mtr-runner] ERROR: mtr timed out for {dest}", flush=True)
    except Exception as e:
        print(f"[mtr-runner] ERROR: {e}", flush=True)


def main() -> None:
    interval = int(get_env("MTR_INTERVAL", "300"))
    count = int(get_env("MTR_COUNT", "10"))
    output_path = Path(get_env("MTR_OUTPUT_PATH", "/data/mtr"))
    destinations_raw = get_env("MTR_DESTINATIONS", "1.1.1.1")
    mtr_bin = get_env("MTR_BIN", "/usr/sbin/mtr")

    destinations = [d.strip() for d in destinations_raw.split(",") if d.strip()]

    output_path.mkdir(parents=True, exist_ok=True)

    print(f"[mtr-runner] Starting.", flush=True)
    print(f"  Interval : {interval}s", flush=True)
    print(f"  Count    : {count} packets", flush=True)
    print(f"  Output   : {output_path}", flush=True)
    print(f"  Targets  : {destinations}", flush=True)

    while True:
        for dest in destinations:
            run_mtr(mtr_bin, dest, count, output_path)

        print(f"[mtr-runner] Cycle complete. Sleeping {interval}s...", flush=True)
        time.sleep(interval)


if __name__ == "__main__":
    main()
