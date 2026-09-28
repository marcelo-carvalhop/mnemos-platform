#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PORT="$(python3 tools/find_mnemos_usb.py)"
ENV_NAME="lilygo-t5-47-s3-touch-bench-ota-source"

echo "[ota-test] fonte OTA: $ENV_NAME"
echo "[ota-test] porta: $PORT"

echo "[ota-test] compilando..."
pio run -e "$ENV_NAME"

echo "[ota-test] gravando fonte por USB..."
pio run -e "$ENV_NAME" -t upload --upload-port "$PORT"

echo
echo "[OK] Fonte OTA 70402 gravada por USB."
echo "[OK] Ela mantem sleep OFF e OTA automatica ON."
echo "[PROXIMO] Gere o alvo com: ./tools/build-ota-target.sh"
