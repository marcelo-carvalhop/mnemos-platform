from pathlib import Path
import re

ROOT = Path.cwd()

pio = ROOT / "platformio.ini"
cfg = ROOT / "include/config.h"
main = ROOT / "src/main.cpp"
readme = ROOT / "README.md"
changelog = ROOT / "CHANGELOG.md"
checklist = ROOT / "docs/TEST_CHECKLIST.md"

# ---------------------------------------------------------------------
# config.h: same source tree can build the USB-installed OTA source
# (generation 70402) and the real OTA target (generation 70403).
# ---------------------------------------------------------------------
c = cfg.read_text(encoding="utf-8")

old_version = 'constexpr char APP_VERSION[] = "0.7.0-preview.4.1.2-touch";'
old_generation = 'constexpr uint32_t OTA_GENERATION = 70402U;'

if old_version not in c:
    raise RuntimeError("APP_VERSION baseline 4.1.2 nao encontrada")
if old_generation not in c:
    raise RuntimeError("OTA_GENERATION baseline 70402 nao encontrada")

version_block = '''#if defined(MNEMOS_OTA_TEST_SOURCE)\nconstexpr char APP_VERSION[] = "0.7.0-preview.4.1.2-ota-source-touch";\nconstexpr uint32_t OTA_GENERATION = 70402U;\n#else\nconstexpr char APP_VERSION[] = "0.7.0-preview.4.2-touch";\nconstexpr uint32_t OTA_GENERATION = 70403U;\n#endif'''

# APP_VERSION and OTA_GENERATION are separated in the file. Replace version,
# then remove the old generation declaration later.
c = c.replace(old_version, version_block, 1)
c = c.replace("\n" + old_generation + "\n", "\n", 1)

# Extend the existing build-flavor block from preview.4.1.2.
bench_old = '''#if defined(MNEMOS_BENCH_BUILD)\nconstexpr bool BENCH_BUILD = true;\nconstexpr char BUILD_FLAVOR[] = "bench";\nconstexpr bool LIGHT_SLEEP_ENABLED = false;\nconstexpr bool DEEP_SLEEP_ENABLED = false;\nconstexpr bool OTA_AUTO_APPLY_ENABLED = false;\n#else\nconstexpr bool BENCH_BUILD = false;\nconstexpr char BUILD_FLAVOR[] = "product";\nconstexpr bool LIGHT_SLEEP_ENABLED = true;\nconstexpr bool DEEP_SLEEP_ENABLED = true;\nconstexpr bool OTA_AUTO_APPLY_ENABLED = true;\n#endif'''

bench_new = '''#if defined(MNEMOS_BENCH_BUILD)\nconstexpr bool BENCH_BUILD = true;\n#if defined(MNEMOS_OTA_TEST_SOURCE)\nconstexpr char BUILD_FLAVOR[] = "bench-ota-source";\nconstexpr bool OTA_AUTO_APPLY_ENABLED = true;\n#elif defined(MNEMOS_OTA_TEST_TARGET)\nconstexpr char BUILD_FLAVOR[] = "bench-ota-target";\nconstexpr bool OTA_AUTO_APPLY_ENABLED = false;\n#else\nconstexpr char BUILD_FLAVOR[] = "bench";\nconstexpr bool OTA_AUTO_APPLY_ENABLED = false;\n#endif\nconstexpr bool LIGHT_SLEEP_ENABLED = false;\nconstexpr bool DEEP_SLEEP_ENABLED = false;\n#else\nconstexpr bool BENCH_BUILD = false;\nconstexpr char BUILD_FLAVOR[] = "product";\nconstexpr bool LIGHT_SLEEP_ENABLED = true;\nconstexpr bool DEEP_SLEEP_ENABLED = true;\nconstexpr bool OTA_AUTO_APPLY_ENABLED = true;\n#endif'''

if bench_old not in c:
    raise RuntimeError("Bloco de build de bancada esperado nao encontrado")
c = c.replace(bench_old, bench_new, 1)

cfg.write_text(c, encoding="utf-8")

# ---------------------------------------------------------------------
# platformio.ini: add two dedicated OTA test environments.
# ---------------------------------------------------------------------
p = pio.read_text(encoding="utf-8")

source_env = '''\n[env:lilygo-t5-47-s3-touch-bench-ota-source]\nextends = env:lilygo-t5-47-s3-touch-bench\nbuild_flags =\n    ${env:lilygo-t5-47-s3-touch-bench.build_flags}\n    -DMNEMOS_OTA_TEST_SOURCE=1\n\n[env:lilygo-t5-47-s3-touch-bench-ota-target]\nextends = env:lilygo-t5-47-s3-touch-bench\nbuild_flags =\n    ${env:lilygo-t5-47-s3-touch-bench.build_flags}\n    -DMNEMOS_OTA_TEST_TARGET=1\n'''

if "[env:lilygo-t5-47-s3-touch-bench-ota-source]" not in p:
    p = p.rstrip() + "\n" + source_env
pio.write_text(p, encoding="utf-8")

# ---------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------
tools = ROOT / "tools"
tools.mkdir(exist_ok=True)

upload_source = tools / "upload-ota-source.sh"
upload_source.write_text(r'''#!/usr/bin/env bash
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
''', encoding="utf-8")
upload_source.chmod(0o755)

build_target = tools / "build-ota-target.sh"
build_target.write_text(r'''#!/usr/bin/env bash
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
''', encoding="utf-8")
build_target.chmod(0o755)

# ---------------------------------------------------------------------
# Documentation.
# ---------------------------------------------------------------------
if readme.exists():
    r = readme.read_text(encoding="utf-8")
    marker = "## Primeiro teste OTA A/B"
    if marker not in r:
        r += '''\n\n## Primeiro teste OTA A/B\n\nA serie `0.7.0-preview.4.2` adiciona dois ambientes temporarios de bancada:\n\n- `lilygo-t5-47-s3-touch-bench-ota-source`: generation 70402, sleep OFF, OTA automatica ON;\n- `lilygo-t5-47-s3-touch-bench-ota-target`: generation 70403, sleep OFF, OTA automatica OFF.\n\nO primeiro e gravado por USB apenas para fornecer uma origem segura ao ensaio.\nO segundo e compilado em bundle e instalado pelo microSD no slot OTA inativo.\n\nUse:\n\n```bash\n./tools/upload-ota-source.sh\n./tools/build-ota-target.sh\n```\n'''
        readme.write_text(r, encoding="utf-8")

if changelog.exists():
    ch = changelog.read_text(encoding="utf-8")
    if "## 0.7.0-preview.4.2-touch" not in ch:
        entry = '''## 0.7.0-preview.4.2-touch\n\n- prepara o primeiro ensaio OTA A/B real;\n- adiciona ambiente `bench-ota-source` em generation 70402;\n- adiciona ambiente `bench-ota-target` em generation 70403;\n- mantem sleep desabilitado nos dois lados do ensaio;\n- habilita OTA automatica apenas na imagem fonte;\n- gera o alvo via `tools/build-ota-target.sh`;\n- nao altera HMI, FSRS ou biblioteca SD-first.\n\n'''
        first, rest = ch.split("\n", 1)
        ch = first + "\n\n" + entry + rest.lstrip("\n")
        changelog.write_text(ch, encoding="utf-8")

if checklist.exists():
    t = checklist.read_text(encoding="utf-8")
    if "## Primeiro OTA A/B" not in t:
        t += '''\n\n## Primeiro OTA A/B\n\n- [ ] `bench-ota-source` inicia em app0 com generation 70402;\n- [ ] `bench-ota-source` informa `ota-auto=1`;\n- [ ] bundle 70403 valida SHA-256 e tamanho;\n- [ ] manifesto e firmware ficam em `/mnemos/update/`;\n- [ ] source detecta e verifica a imagem antes de `Update.begin`;\n- [ ] instalacao grava o slot inativo;\n- [ ] reboot entra em app1 com generation 70403;\n- [ ] boot completo chama `confirmRunningImage`;\n- [ ] `ota-summary` mostra `running=app1 next=app0 rollback=1`;\n- [ ] FSRS e biblioteca SD-first permanecem intactos;\n- [ ] USB continua enumerado apos o update.\n'''
        checklist.write_text(t, encoding="utf-8")

# ---------------------------------------------------------------------
# Guards.
# ---------------------------------------------------------------------
cf = cfg.read_text(encoding="utf-8")
pf = pio.read_text(encoding="utf-8")

assert "MNEMOS_OTA_TEST_SOURCE" in cf
assert '0.7.0-preview.4.1.2-ota-source-touch' in cf
assert '0.7.0-preview.4.2-touch' in cf
assert "OTA_GENERATION = 70402U" in cf
assert "OTA_GENERATION = 70403U" in cf
assert 'BUILD_FLAVOR[] = "bench-ota-source"' in cf
assert 'BUILD_FLAVOR[] = "bench-ota-target"' in cf
assert "[env:lilygo-t5-47-s3-touch-bench-ota-source]" in pf
assert "[env:lilygo-t5-47-s3-touch-bench-ota-target]" in pf

print("[OK] fonte OTA de bancada: 70402 / auto-apply ON / sleep OFF")
print("[OK] alvo OTA de bancada: 70403 / auto-apply OFF / sleep OFF")
print("[OK] HMI, FSRS e SD-first inalterados")
