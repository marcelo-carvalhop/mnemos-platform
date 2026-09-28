#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PORT="$(python3 tools/find_mnemos_usb.py)"
echo "[bench] porta: $PORT"
echo "[bench] ambiente: lilygo-t5-47-s3-touch-bench"
exec pio run -e lilygo-t5-47-s3-touch-bench -t upload --upload-port "$PORT"
