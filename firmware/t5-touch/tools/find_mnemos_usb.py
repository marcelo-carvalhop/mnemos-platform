#!/usr/bin/env python3
import json
import os
import subprocess
import sys

override = os.environ.get("MNEMOS_UPLOAD_PORT", "").strip()
if override:
    if not os.path.exists(override):
        print(f"[ERRO] MNEMOS_UPLOAD_PORT nao existe: {override}", file=sys.stderr)
        sys.exit(2)
    print(override)
    sys.exit(0)

result = subprocess.run(
    ["pio", "device", "list", "--json-output"],
    text=True,
    capture_output=True,
)
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)

try:
    devices = json.loads(result.stdout)
except json.JSONDecodeError:
    print("[ERRO] Nao foi possivel interpretar pio device list --json-output.", file=sys.stderr)
    sys.stderr.write(result.stdout)
    sys.exit(3)

candidates = []
for dev in devices:
    port = str(dev.get("port", ""))
    hwid = str(dev.get("hwid", "")).upper()
    description = str(dev.get("description", "")).upper()
    is_acm = port.startswith("/dev/ttyACM")
    is_espressif = (
        "VID:PID=303A:" in hwid
        or "VID_303A" in hwid
        or "ESPRESSIF" in description
    )
    if is_acm and is_espressif:
        candidates.append(port)

if len(candidates) == 1:
    print(candidates[0])
    sys.exit(0)

if not candidates:
    print("[ERRO] Nenhuma porta USB Espressif /dev/ttyACM* foi encontrada.", file=sys.stderr)
    print("[ERRO] Upload abortado para impedir fallback em /dev/ttyS0.", file=sys.stderr)
    print("[DICA] Acorde a placa ou use SIR_IO0 + RST para download mode.", file=sys.stderr)
    sys.exit(4)

print("[ERRO] Mais de uma porta Espressif: " + ", ".join(candidates), file=sys.stderr)
print("[DICA] Use MNEMOS_UPLOAD_PORT=/dev/ttyACM0 ./tools/upload-bench.sh", file=sys.stderr)
sys.exit(5)
