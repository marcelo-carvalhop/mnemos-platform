#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_NAME="lilygo-t5-47-s3-touch-bench-ota-target"
VERSION="0.7.0-preview.4.2-touch"
GENERATION="70403"
OUT="/tmp/mnemos-ota-${GENERATION}"

echo "[ota-test] compilando alvo: $ENV_NAME"
pio run -e "$ENV_NAME"

BIN=".pio/build/${ENV_NAME}/firmware.bin"
[[ -f "$BIN" ]] || {
    echo "[ERRO] firmware.bin nao encontrado: $BIN" >&2
    exit 2
}

rm -rf "$OUT"
python3 tools/make_ota_bundle.py \
  "$BIN" \
  --version "$VERSION" \
  --generation "$GENERATION" \
  --output "$OUT"

echo
echo "[OK] Bundle OTA criado em: $OUT"
echo "[COPIAR PARA O SD]"
echo "  $OUT/firmware.bin  -> /mnemos/update/firmware.bin"
echo "  $OUT/manifest.json -> /mnemos/update/manifest.json"
echo
echo "Depois recoloque o SD e reinicie a placa."
