from pathlib import Path
import re

root = Path('.')
pio = root / 'platformio.ini'
cfg = root / 'include/config.h'
power = root / 'src/power_service.cpp'
main = root / 'src/main.cpp'

for p in (pio, cfg, power, main):
    if not p.exists():
        raise RuntimeError(f'Arquivo ausente: {p}')

# ----------------------------------------------------------------------
# platformio.ini
# ----------------------------------------------------------------------
s = pio.read_text(encoding='utf-8')

if '[platformio]' not in s:
    s = '[platformio]\ndefault_envs = lilygo-t5-47-s3-touch-bench\n\n' + s
else:
    section = re.search(r'(?ms)^\[platformio\]\s*\n(.*?)(?=^\[|\Z)', s)
    if not section:
        raise RuntimeError('Secao [platformio] invalida')
    body = section.group(1)
    if 'default_envs' in body:
        s = re.sub(
            r'(?m)^default_envs\s*=.*$',
            'default_envs = lilygo-t5-47-s3-touch-bench',
            s,
            count=1,
        )
    else:
        s = s.replace(
            '[platformio]\n',
            '[platformio]\ndefault_envs = lilygo-t5-47-s3-touch-bench\n',
            1,
        )

bench_section = '''
[env:lilygo-t5-47-s3-touch-bench]
extends = env:lilygo-t5-47-s3-touch
upload_speed = 460800
monitor_speed = 115200
build_flags =
    ${env:lilygo-t5-47-s3-touch.build_flags}
    -DMNEMOS_BENCH_BUILD=1

[env:lilygo-t5-47-s3-touch-bench-demo]
extends = env:lilygo-t5-47-s3-touch-bench
build_flags =
    ${env:lilygo-t5-47-s3-touch-bench.build_flags}
    -DMNEMOS_DEMO_INTERVALS=1
'''

if '[env:lilygo-t5-47-s3-touch-bench]' not in s:
    s = s.rstrip() + '\n\n' + bench_section.strip() + '\n'

pio.write_text(s, encoding='utf-8')

# ----------------------------------------------------------------------
# config.h
# ----------------------------------------------------------------------
c = cfg.read_text(encoding='utf-8')

if '0.7.0-preview.4.1.1-touch' not in c:
    raise RuntimeError('Baseline esperada: 0.7.0-preview.4.1.1-touch')

c, n = re.subn(
    r'constexpr char APP_VERSION\[\]\s*=\s*"0\.7\.0-preview\.4\.1\.1-touch"\s*;',
    'constexpr char APP_VERSION[] = "0.7.0-preview.4.1.2-touch";',
    c,
    count=1,
)
if n != 1:
    raise RuntimeError('Falha ao atualizar APP_VERSION')

c, n = re.subn(
    r'constexpr uint32_t OTA_GENERATION\s*=\s*70401U\s*;',
    'constexpr uint32_t OTA_GENERATION = 70402U;',
    c,
    count=1,
)
if n == 0 and 'OTA_GENERATION = 70402U' not in c:
    raise RuntimeError('OTA_GENERATION 70401U nao encontrada')

# DEMO_INTERVALS controlled by build profile.
demo_pattern = re.compile(r'constexpr bool DEMO_INTERVALS\s*=\s*(?:true|false)\s*;')
if demo_pattern.search(c):
    c = demo_pattern.sub(
        '#if defined(MNEMOS_DEMO_INTERVALS)\n'
        'constexpr bool DEMO_INTERVALS = true;\n'
        '#else\n'
        'constexpr bool DEMO_INTERVALS = false;\n'
        '#endif',
        c,
        count=1,
    )
elif 'MNEMOS_DEMO_INTERVALS' not in c:
    raise RuntimeError('DEMO_INTERVALS nao encontrado')

# Sleep and automatic local OTA controlled by build profile.
power_pattern = re.compile(
    r'constexpr bool LIGHT_SLEEP_ENABLED\s*=\s*(?:true|false)\s*;\s*'
    r'constexpr bool DEEP_SLEEP_ENABLED\s*=\s*(?:true|false)\s*;'
)
if power_pattern.search(c):
    c = power_pattern.sub(
        '#if defined(MNEMOS_BENCH_BUILD)\n'
        'constexpr bool BENCH_BUILD = true;\n'
        'constexpr char BUILD_FLAVOR[] = "bench";\n'
        'constexpr bool LIGHT_SLEEP_ENABLED = false;\n'
        'constexpr bool DEEP_SLEEP_ENABLED = false;\n'
        'constexpr bool OTA_AUTO_APPLY_ENABLED = false;\n'
        '#else\n'
        'constexpr bool BENCH_BUILD = false;\n'
        'constexpr char BUILD_FLAVOR[] = "product";\n'
        'constexpr bool LIGHT_SLEEP_ENABLED = true;\n'
        'constexpr bool DEEP_SLEEP_ENABLED = true;\n'
        'constexpr bool OTA_AUTO_APPLY_ENABLED = true;\n'
        '#endif',
        c,
        count=1,
    )
elif 'constexpr bool BENCH_BUILD' not in c:
    raise RuntimeError('Flags LIGHT/DEEP_SLEEP nao encontradas')

cfg.write_text(c, encoding='utf-8')

# ----------------------------------------------------------------------
# PowerService: bench must never enter or simulate sleep.
# ----------------------------------------------------------------------
p = power.read_text(encoding='utf-8')
signature = '''PowerDecision PowerService::evaluate(
    bool sleepAllowed,
    bool criticalBattery) const {
'''
if signature not in p:
    raise RuntimeError('PowerService::evaluate nao encontrado')

guard = '''PowerDecision PowerService::evaluate(
    bool sleepAllowed,
    bool criticalBattery) const {

    if (
        !Config::LIGHT_SLEEP_ENABLED &&
        !Config::DEEP_SLEEP_ENABLED
    ) {
        return
            PowerDecision::None;
    }
'''
if '!Config::LIGHT_SLEEP_ENABLED &&' not in p:
    p = p.replace(signature, guard, 1)
power.write_text(p, encoding='utf-8')

# ----------------------------------------------------------------------
# main.cpp: build diagnostics + OTA auto-apply gate.
# ----------------------------------------------------------------------
m = main.read_text(encoding='utf-8')

if '[build] flavor=' not in m:
    serial_match = re.search(r'Serial\.begin\s*\(\s*115200\s*\)\s*;', m)
    if not serial_match:
        raise RuntimeError('Serial.begin(115200) nao encontrado')
    pos = serial_match.end()
    build_log = '''

    Serial.printf(
        "[build] flavor=%s bench=%d demo=%d light-sleep=%d deep-sleep=%d ota-auto=%d\\n",
        Config::BUILD_FLAVOR,
        Config::BENCH_BUILD ? 1 : 0,
        Config::DEMO_INTERVALS ? 1 : 0,
        Config::LIGHT_SLEEP_ENABLED ? 1 : 0,
        Config::DEEP_SLEEP_ENABLED ? 1 : 0,
        Config::OTA_AUTO_APPLY_ENABLED ? 1 : 0);
'''
    m = m[:pos] + build_log + m[pos:]

# Gate the existing local OTA check. Handles normal formatting variations.
ota_pattern = re.compile(
    r'if\s*\(\s*sdCardService\.mounted\(\)\s*\)\s*\{\s*'
    r'otaService\.applyLocalUpdateIfRequested\(',
    re.MULTILINE,
)
if ota_pattern.search(m):
    m = ota_pattern.sub(
        'if (\n'
        '        Config::OTA_AUTO_APPLY_ENABLED &&\n'
        '        sdCardService.mounted()\n'
        '    ) {\n'
        '        otaService.applyLocalUpdateIfRequested(',
        m,
        count=1,
    )
elif 'Config::OTA_AUTO_APPLY_ENABLED' not in m:
    raise RuntimeError('Bloco de aplicacao OTA local nao encontrado')

main.write_text(m, encoding='utf-8')

# ----------------------------------------------------------------------
# Safe USB helpers.
# ----------------------------------------------------------------------
tools = root / 'tools'
tools.mkdir(exist_ok=True)

find_port = tools / 'find_mnemos_usb.py'
find_port.write_text('''#!/usr/bin/env python3
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
''', encoding='utf-8')
find_port.chmod(0o755)

upload = tools / 'upload-bench.sh'
upload.write_text('''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PORT="$(python3 tools/find_mnemos_usb.py)"
echo "[bench] porta: $PORT"
echo "[bench] ambiente: lilygo-t5-47-s3-touch-bench"
exec pio run -e lilygo-t5-47-s3-touch-bench -t upload --upload-port "$PORT"
''', encoding='utf-8')
upload.chmod(0o755)

monitor = tools / 'monitor-bench.sh'
monitor.write_text('''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PORT="$(python3 tools/find_mnemos_usb.py)"
echo "[bench] monitor: $PORT"
exec pio device monitor --port "$PORT" --baud 115200
''', encoding='utf-8')
monitor.chmod(0o755)

build = tools / 'build-bench.sh'
build.write_text('''#!/usr/bin/env bash
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
''', encoding='utf-8')
build.chmod(0o755)

# ----------------------------------------------------------------------
# Documentation.
# ----------------------------------------------------------------------
docs = root / 'docs'
docs.mkdir(exist_ok=True)
(docs / 'BENCH_BUILDS.md').write_text('''# Builds de bancada — T5-4.7-S3 Touch

A partir da série `0.7.0-preview.4.1.2`, o firmware possui perfis separados
para produto e desenvolvimento.

## Produto

`lilygo-t5-47-s3-touch`

- light sleep habilitado;
- deep sleep habilitado;
- OTA local automática habilitada;
- intervalos pedagógicos reais;
- upload em 921600.

```bash
pio run -e lilygo-t5-47-s3-touch
```

## Bancada

`lilygo-t5-47-s3-touch-bench`

- light sleep desabilitado;
- deep sleep desabilitado;
- OTA local automática desabilitada;
- intervalos pedagógicos reais;
- USB CDC/JTAG permanece disponível enquanto o firmware executa;
- upload em 460800.

Este é o `default_envs`; portanto `pio run` compila a bancada.

## Bancada demo

`lilygo-t5-47-s3-touch-bench-demo` mantém as proteções da bancada e ativa
`DEMO_INTERVALS=true` para testes rápidos de agenda e FSRS.

## Ferramentas

```bash
./tools/build-bench.sh bench
./tools/build-bench.sh demo
./tools/build-bench.sh product
./tools/upload-bench.sh
./tools/monitor-bench.sh
```

O uploader aceita somente uma porta `/dev/ttyACM*` identificada como Espressif
e aborta se ela não existir. Isso impede o fallback acidental para
`/dev/ttyS0`.

Se houver mais de um ESP32 conectado:

```bash
MNEMOS_UPLOAD_PORT=/dev/ttyACM0 ./tools/upload-bench.sh
```

## Diagnóstico

Bancada:

```text
[build] flavor=bench bench=1 demo=0 light-sleep=0 deep-sleep=0 ota-auto=0
```

Produto:

```text
[build] flavor=product bench=0 demo=0 light-sleep=1 deep-sleep=1 ota-auto=1
```

Testes reais de consumo, wake, light sleep e deep sleep devem ser feitos na
build de produto, não na build de bancada.
''', encoding='utf-8')

readme = root / 'README.md'
if readme.exists():
    r = readme.read_text(encoding='utf-8')
    if '## Builds de bancada' not in r:
        r += '''\n\n## Builds de bancada\n\nO ambiente padrão de desenvolvimento é `lilygo-t5-47-s3-touch-bench`, que mantém light/deep sleep e OTA automática desabilitados. Consulte `docs/BENCH_BUILDS.md`.\n'''
        readme.write_text(r, encoding='utf-8')

changelog = root / 'CHANGELOG.md'
if changelog.exists():
    ch = changelog.read_text(encoding='utf-8')
    if '## 0.7.0-preview.4.1.2-touch' not in ch:
        entry = '''## 0.7.0-preview.4.1.2-touch\n\n- separa build de produto e builds de bancada;\n- define `bench` como ambiente padrão;\n- desabilita light/deep sleep e OTA automática na bancada;\n- adiciona `bench-demo`;\n- reduz upload de bancada para 460800;\n- adiciona uploader que rejeita fallback para `/dev/ttyS0`;\n- adiciona diagnóstico do perfil de build;\n- avança `OTA_GENERATION` para `70402`.\n\n'''
        first, rest = ch.split('\n', 1)
        ch = first + '\n\n' + entry + rest.lstrip('\n')
        changelog.write_text(ch, encoding='utf-8')

checklist = root / 'docs/TEST_CHECKLIST.md'
if checklist.exists():
    t = checklist.read_text(encoding='utf-8')
    if '## Builds de bancada' not in t:
        t += '''\n\n## Builds de bancada\n\n- [ ] `pio run` compila apenas `lilygo-t5-47-s3-touch-bench`;\n- [ ] boot da bancada informa `flavor=bench`;\n- [ ] bancada informa `light-sleep=0 deep-sleep=0 ota-auto=0`;\n- [ ] após 25 minutos sem interação, USB continua enumerado;\n- [ ] `tools/upload-bench.sh` nunca tenta `/dev/ttyS0`;\n- [ ] `bench-demo` informa `demo=1`;\n- [ ] build de produto informa `flavor=product`;\n- [ ] build de produto mantém light/deep sleep habilitados.\n'''
        checklist.write_text(t, encoding='utf-8')

# ----------------------------------------------------------------------
# Guards.
# ----------------------------------------------------------------------
pf = pio.read_text(encoding='utf-8')
cf = cfg.read_text(encoding='utf-8')
powf = power.read_text(encoding='utf-8')
mf = main.read_text(encoding='utf-8')

assert 'default_envs = lilygo-t5-47-s3-touch-bench' in pf
assert '[env:lilygo-t5-47-s3-touch-bench]' in pf
assert '[env:lilygo-t5-47-s3-touch-bench-demo]' in pf
assert '-DMNEMOS_BENCH_BUILD=1' in pf
assert '-DMNEMOS_DEMO_INTERVALS=1' in pf
assert '0.7.0-preview.4.1.2-touch' in cf
assert 'OTA_GENERATION = 70402U' in cf
assert 'BUILD_FLAVOR[] = "bench"' in cf
assert 'BUILD_FLAVOR[] = "product"' in cf
assert 'OTA_AUTO_APPLY_ENABLED = false' in cf
assert 'OTA_AUTO_APPLY_ENABLED = true' in cf
assert 'MNEMOS_DEMO_INTERVALS' in cf
assert '!Config::LIGHT_SLEEP_ENABLED &&' in powf
assert '[build] flavor=' in mf
assert 'Config::OTA_AUTO_APPLY_ENABLED' in mf

print('[OK] perfis de bancada instalados')
print('[OK] pio run => lilygo-t5-47-s3-touch-bench')
print('[OK] sleep OFF e OTA auto OFF na bancada')
print('[OK] uploader USB seguro adicionado')
print('[OK] versao 0.7.0-preview.4.1.2-touch generation=70402')
