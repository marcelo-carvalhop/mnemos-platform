#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_NAME="t5s3-pro-bench-ota-source"
GENERATION="$(python3 tools/firmware_meta.py --env "$ENV_NAME" --field generation)"
PORT="$(python3 tools/find_mnemos_usb.py)"

echo "[ota-test] fonte OTA: $ENV_NAME (geracao $GENERATION)"
echo "[ota-test] porta: $PORT"

echo "[ota-test] compilando..."
pio run -e "$ENV_NAME"

echo "[ota-test] gravando fonte por USB..."
pio run -e "$ENV_NAME" -t upload --upload-port "$PORT"

echo
echo "[OK] Fonte OTA $GENERATION gravada por USB."
echo "[OK] Ela mantem sleep OFF e OTA automatica ON."
echo "[PROXIMO] Gere o alvo com: ./tools/build-ota-target.sh"
