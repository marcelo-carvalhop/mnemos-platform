#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(
    description="Cria manifesto Mnemos OTA v1 para firmware.bin."
)
parser.add_argument("firmware", type=Path)
parser.add_argument("--version", required=True)
parser.add_argument("--generation", required=True, type=int)
parser.add_argument(
    "--model",
    default="LILYGO-T5-4.7-S3-TOUCH",
)
parser.add_argument("--protocol-min", type=int, default=4)
parser.add_argument("--protocol-max", type=int, default=4)
parser.add_argument(
    "--output",
    type=Path,
    default=Path("mnemos-ota"),
)
args = parser.parse_args()

data = args.firmware.read_bytes()
digest = hashlib.sha256(data).hexdigest()

args.output.mkdir(parents=True, exist_ok=True)
image_out = args.output / "firmware.bin"
manifest_out = args.output / "manifest.json"

image_out.write_bytes(data)

manifest = {
    "schema": "mnemos.ota/v1",
    "version": args.version,
    "generation": args.generation,
    "model": args.model,
    "protocolMin": args.protocol_min,
    "protocolMax": args.protocol_max,
    "size": len(data),
    "sha256": digest,
    "file": "/mnemos/update/firmware.bin",
    "apply": True,
}

manifest_out.write_text(
    json.dumps(
        manifest,
        ensure_ascii=False,
        indent=2,
    ) + "\n",
    encoding="utf-8",
)

print(f"Imagem: {image_out}")
print(f"Manifesto: {manifest_out}")
print(f"SHA256: {digest}")
print(f"Tamanho: {len(data)} bytes")
print()
print("Copie para o SD:")
print("  /mnemos/update/firmware.bin")
print("  /mnemos/update/manifest.json")
