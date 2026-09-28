from pathlib import Path
import re

root = Path(".")
main = root / "src/main.cpp"
cfg = root / "include/config.h"

for p in (main, cfg):
    if not p.exists():
        raise RuntimeError(f"Arquivo ausente: {p}")

m = main.read_text(encoding="utf-8")

if "[sd-first] enabled=" not in m:
    anchor = '    rebuildEngine();\n\n    if (touchInput.online()) {\n'
    summary = '    rebuildEngine();\n\n    Serial.printf(\n        "[sd-first] enabled=%d mounted=%d canonical=%d cards=%u heap=%u\\\\n",\n        Config::SD_FIRST_LIBRARY\n            ? 1\n            : 0,\n        sdCardService.mounted()\n            ? 1\n            : 0,\n        sdCardService.canonicalLibraryAvailable()\n            ? 1\n            : 0,\n        static_cast<unsigned>(\n            cardCount),\n        static_cast<unsigned>(\n            ESP.getFreeHeap()));\n\n    if (\n        Config::SD_FIRST_LIBRARY &&\n        sdCardService.mounted() &&\n        !sdCardService.canonicalLibraryAvailable()\n    ) {\n        Serial.printf(\n            "[sd-first] fallback=LittleFS reason=%s\\\\n",\n            sdCardService.lastError().\n                c_str());\n    }\n\n    if (touchInput.online()) {\n'
    if anchor not in m:
        raise RuntimeError("Trecho final de setup() nao encontrado")
    m = m.replace(anchor, summary, 1)
    main.write_text(m, encoding="utf-8")

c = cfg.read_text(encoding="utf-8")
if "0.7.0-preview.3.1.1-touch" not in c:
    c, n = re.subn(
        r'constexpr char APP_VERSION\[\]\s*=\s*\"0\.7\.0-preview\.3\.1-touch\"\s*;',
        'constexpr char APP_VERSION[] = "0.7.0-preview.3.1.1-touch";',
        c,
        count=1,
    )
    if n != 1:
        raise RuntimeError("APP_VERSION esperado 0.7.0-preview.3.1-touch nao encontrado")
    cfg.write_text(c, encoding="utf-8")

mf = main.read_text(encoding="utf-8")
cf = cfg.read_text(encoding="utf-8")
assert "[sd-first] enabled=" in mf
assert "canonicalLibraryAvailable()" in mf
assert "0.7.0-preview.3.1.1-touch" in cf

print("[OK] resumo SD-first adicionado ao fim de setup()")
print("[OK] versao 0.7.0-preview.3.1.1-touch")
