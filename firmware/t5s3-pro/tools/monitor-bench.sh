#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PORT="$(python3 tools/find_mnemos_usb.py)"
echo "[bench] monitor: $PORT"
exec pio device monitor --port "$PORT" --baud 115200
