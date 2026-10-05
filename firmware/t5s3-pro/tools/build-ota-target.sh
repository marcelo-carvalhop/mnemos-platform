#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_NAME="t5s3-pro-bench-ota-target"
GENERATION="$(python3 tools/firmware_meta.py --env "$ENV_NAME" --field generation)"
OUT="${MNEMOS_OTA_OUT:-/tmp/mnemos-ota-${GENERATION}}"

echo "[ota-test] compilando alvo: $ENV_NAME"
pio run -e "$ENV_NAME"

BIN=".pio/build/${ENV_NAME}/firmware.bin"
[[ -f "$BIN" ]] || {
    echo "[ERRO] firmware.bin nao encontrado: $BIN" >&2
    exit 2
}

python3 tools/make_ota_bundle.py \
  "$BIN" \
  --env "$ENV_NAME" \
  --output "$OUT"

echo
echo "[OK] Bundle OTA criado em: $OUT"
echo "[COPIAR PARA O SD]"
echo "  $OUT/firmware.bin  -> /mnemos/update/firmware.bin"
echo "  $OUT/manifest.json -> /mnemos/update/manifest.json"
echo
echo "Depois recoloque o SD e reinicie a placa."
