#!/bin/bash
set -euo pipefail

# Defaults
INTERVAL="${MTR_INTERVAL:-300}"
COUNT="${MTR_COUNT:-10}"
OUTPUT_PATH="${MTR_OUTPUT_PATH:-/data/mtr}"
DESTINATIONS="${MTR_DESTINATIONS:-1.1.1.1}"

mkdir -p "$OUTPUT_PATH"

echo "[mtr-runner] Starting. Interval=${INTERVAL}s, Count=${COUNT}, Destinations=${DESTINATIONS}"

while true; do
    TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")

    IFS=',' read -ra DEST_LIST <<< "$DESTINATIONS"
    for DEST in "${DEST_LIST[@]}"; do
        DEST=$(echo "$DEST" | xargs)  # trim whitespace
        SAFE_DEST=$(echo "$DEST" | tr '.' '-' | tr ':' '-')
        OUTFILE="${OUTPUT_PATH}/${TIMESTAMP}_${SAFE_DEST}.json"

        echo "[mtr-runner] Running mtr to ${DEST} -> ${OUTFILE}"
        mtr -j -c "$COUNT" "$DEST" > "$OUTFILE" 2>&1 || {
            echo "[mtr-runner] WARNING: mtr to ${DEST} failed"
        }
    done

    echo "[mtr-runner] Cycle done. Sleeping ${INTERVAL}s..."
    sleep "$INTERVAL"
done
