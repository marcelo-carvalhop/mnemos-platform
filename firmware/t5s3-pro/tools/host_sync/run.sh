#!/usr/bin/env bash
# Compila o simulador do terminal (código real de sincronização) e roda os
# testes ponta a ponta contra o backend em MNEMOS_API (padrão localhost:8000).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="$(cd "$HERE/../.." && pwd)"

ARDUINOJSON_SRC="${ARDUINOJSON_SRC:-}"
if [[ -z "$ARDUINOJSON_SRC" ]]; then
  for candidate in "$FW"/.pio/libdeps/*/ArduinoJson/src; do
    [[ -d "$candidate" ]] && ARDUINOJSON_SRC="$candidate" && break
  done
fi
if [[ -z "$ARDUINOJSON_SRC" || ! -f "$ARDUINOJSON_SRC/ArduinoJson.h" ]]; then
  echo "ArduinoJson não encontrado. Rode 'pio run' uma vez em firmware/t5s3-pro"
  echo "ou exporte ARDUINOJSON_SRC=/caminho/ArduinoJson/src (git clone bblanchon/ArduinoJson)."
  exit 2
fi

g++ -std=gnu++17 -O1 -g -Wall -Wextra -Wno-unused-parameter \
  -DARDUINOJSON_ENABLE_PROGMEM=0 -DARDUINOJSON_ENABLE_ARDUINO_STRING=1 \
  -DARDUINOJSON_ENABLE_ARDUINO_STREAM=1 -DARDUINOJSON_ENABLE_ARDUINO_PRINT=1 \
  -DMNEMOS_BENCH_BUILD=1 \
  -I"$HERE/stubs" -I"$FW/include" -I"$ARDUINOJSON_SRC" \
  "$HERE/fwsim.cpp" "$HERE/stubs/host_runtime.cpp" \
  "$FW/src/backend_sync_service.cpp" "$FW/src/sync_codec.cpp" "$FW/src/storage.cpp" \
  "$FW/src/text_sanitizer.cpp" "$FW/src/terminal_identity.cpp" \
  -o "$HERE/fwsim"

echo "simulador compilado: $HERE/fwsim"
exec python3 "$HERE/e2e.py"
