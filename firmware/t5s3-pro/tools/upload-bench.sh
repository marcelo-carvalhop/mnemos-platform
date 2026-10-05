#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
MODE="${1:-bench}"
case "$MODE" in
  bench) ENV_NAME="t5s3-pro-bench" ;;
  demo|bench-demo) ENV_NAME="t5s3-pro-bench-demo" ;;
  product) ENV_NAME="t5s3-pro" ;;
  *) echo "Uso: $0 [bench|demo|product]" >&2; exit 2 ;;
esac
PORT="$(python3 tools/find_mnemos_usb.py)"
echo "[bench] porta: $PORT"
echo "[bench] ambiente: $ENV_NAME"
exec pio run -e "$ENV_NAME" -t upload --upload-port "$PORT"
