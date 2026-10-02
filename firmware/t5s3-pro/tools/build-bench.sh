#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
MODE="${1:-bench}"
case "$MODE" in
  bench) ENV_NAME="lilygo-t5-47-s3-touch-bench" ;;
  demo|bench-demo) ENV_NAME="lilygo-t5-47-s3-touch-bench-demo" ;;
  product) ENV_NAME="lilygo-t5-47-s3-touch" ;;
  *) echo "Uso: $0 [bench|demo|product]" >&2; exit 2 ;;
esac
echo "[build] ambiente: $ENV_NAME"
exec pio run -e "$ENV_NAME"
