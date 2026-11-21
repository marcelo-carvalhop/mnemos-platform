#!/usr/bin/env python3
"""Lê versão, geração OTA, modelo e protocolo de include/config.h.

Os valores dependem das macros de cada ambiente PlatformIO (por exemplo,
MNEMOS_OTA_TEST_SOURCE muda a geração). As macros são obtidas de
`pio project config` e config.h é pré-processado com o compilador C++ do
host, sem compilar o firmware.

Uso:
    python3 tools/firmware_meta.py --env t5s3-pro-bench-ota-target
    python3 tools/firmware_meta.py --env t5s3-pro --field generation
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
CONFIG_HEADER = PROJECT_DIR / "include" / "config.h"
DEFAULT_ENV = "t5s3-pro"

FIELDS = {
    "version": r'APP_VERSION\[\]\s*=\s*"([^"]+)"',
    "generation": r"OTA_GENERATION\s*=\s*(\d+)",
    "model": r'DEVICE_MODEL\[\]\s*=\s*"([^"]+)"',
    "protocol": r"DEVICE_PROTOCOL_VERSION\s*=\s*(\d+)",
}

INTEGER_FIELDS = {"generation", "protocol"}


def fail(message):
    print(f"[ERRO] {message}", file=sys.stderr)
    sys.exit(2)


def pio_executable():
    found = shutil.which("pio") or shutil.which("platformio")
    if found:
        return found

    bundled = Path.home() / ".platformio" / "penv" / "bin" / "pio"
    if bundled.exists():
        return str(bundled)

    fail("PlatformIO (pio) não encontrado no PATH.")


def env_defines(env):
    result = subprocess.run(
        [pio_executable(), "project", "config", "--json-output"],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        fail("`pio project config` falhou.")

    for section, options in json.loads(result.stdout):
        if section != f"env:{env}":
            continue

        flags = dict(options).get("build_flags", [])
        if isinstance(flags, str):
            flags = flags.split()

        defines = []
        for flag in flags:
            flag = flag.strip()
            if flag.startswith("-D"):
                defines.append(flag[2:].strip())
        return defines

    fail(f"ambiente desconhecido em platformio.ini: {env}")


def read_meta(env):
    compiler = (
        shutil.which("c++")
        or shutil.which("g++")
        or shutil.which("clang++")
    )
    if compiler is None:
        fail("compilador C++ do host não encontrado (c++, g++ ou clang++).")

    with tempfile.TemporaryDirectory() as stub_dir:
        # config.h inclui <Arduino.h>; só os tipos inteiros são necessários.
        Path(stub_dir, "Arduino.h").write_text(
            "#pragma once\n#include <stddef.h>\n#include <stdint.h>\n"
        )

        command = [
            compiler,
            "-E",
            "-P",
            "-x",
            "c++",
            "-std=gnu++17",
            f"-I{stub_dir}",
            f"-I{PROJECT_DIR / 'include'}",
        ]
        command += [f"-D{define}" for define in env_defines(env)]
        command.append(str(CONFIG_HEADER))

        result = subprocess.run(command, text=True, capture_output=True)

    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        fail("pré-processamento de include/config.h falhou.")

    meta = {"env": env}
    for name, pattern in FIELDS.items():
        match = re.search(pattern, result.stdout)
        if match is None:
            fail(f"campo {name} não encontrado em include/config.h.")
        value = match.group(1)
        meta[name] = int(value) if name in INTEGER_FIELDS else value

    return meta


def main():
    parser = argparse.ArgumentParser(
        description="Lê os metadados de build do firmware Mnemos T5S3 Pro."
    )
    parser.add_argument("--env", default=DEFAULT_ENV)
    parser.add_argument("--field", choices=sorted(FIELDS))
    args = parser.parse_args()

    meta = read_meta(args.env)

    if args.field:
        print(meta[args.field])
    else:
        print(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
