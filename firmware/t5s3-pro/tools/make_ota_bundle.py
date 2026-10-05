#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

from firmware_meta import DEFAULT_ENV, read_meta

parser = argparse.ArgumentParser(
    description=(
        "Cria manifesto Mnemos OTA v1 para firmware.bin. Versão, geração, "
        "modelo e protocolo vêm de include/config.h para o ambiente "
        "indicado em --env, salvo quando informados explicitamente."
    )
)
parser.add_argument("firmware", type=Path)
parser.add_argument("--env", default=DEFAULT_ENV)
parser.add_argument("--version")
parser.add_argument("--generation", type=int)
parser.add_argument("--model")
parser.add_argument("--protocol-min", type=int)
parser.add_argument("--protocol-max", type=int)
parser.add_argument(
    "--output",
    type=Path,
    default=Path("mnemos-ota"),
)
args = parser.parse_args()

explicit = (
    args.version,
    args.generation,
    args.model,
    args.protocol_min,
    args.protocol_max,
)
meta = (
    read_meta(args.env)
    if any(value is None for value in explicit)
    else {}
)

version = args.version or meta["version"]
generation = (
    args.generation
    if args.generation is not None
    else meta["generation"]
)
model = args.model or meta["model"]
protocol_min = (
    args.protocol_min
    if args.protocol_min is not None
    else meta["protocol"]
)
protocol_max = (
    args.protocol_max
    if args.protocol_max is not None
    else meta["protocol"]
)

data = args.firmware.read_bytes()
digest = hashlib.sha256(data).hexdigest()

args.output.mkdir(parents=True, exist_ok=True)
image_out = args.output / "firmware.bin"
manifest_out = args.output / "manifest.json"

image_out.write_bytes(data)

manifest = {
    "schema": "mnemos.ota/v1",
    "version": version,
    "generation": generation,
    "model": model,
    "protocolMin": protocol_min,
    "protocolMax": protocol_max,
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
print(f"Versão: {version} geração={generation} modelo={model}")
print(f"SHA256: {digest}")
print(f"Tamanho: {len(data)} bytes")
print()
print("Copie para o SD:")
print("  /mnemos/update/firmware.bin")
print("  /mnemos/update/manifest.json")
