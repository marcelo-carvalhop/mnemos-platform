from pathlib import Path
import re

root = Path(".")

cpp = root / "src/sd_card_service.cpp"
cfg = root / "include/config.h"

for p in (cpp, cfg):
    if not p.exists():
        raise RuntimeError(f"Arquivo ausente: {p}")

s = cpp.read_text(encoding="utf-8")

old = """item.as<
                            JsonObjectConst>()"""
count = s.count(old)

if count != 2:
    raise RuntimeError(
        f"Esperadas 2 ocorrencias de JsonObject::as<JsonObjectConst>(), encontradas: {count}"
    )

s = s.replace(old, "item", 2)
cpp.write_text(s, encoding="utf-8")

c = cfg.read_text(encoding="utf-8")
c, n = re.subn(
    r'constexpr char APP_VERSION\[\]\s*=\s*"0\.7\.0-preview\.3-touch"\s*;',
    'constexpr char APP_VERSION[] = "0.7.0-preview.3.1-touch";',
    c,
    count=1,
)
if n != 1:
    raise RuntimeError(
        "APP_VERSION 0.7.0-preview.3-touch nao encontrado"
    )

cfg.write_text(c, encoding="utf-8")

final = cpp.read_text(encoding="utf-8")
assert ".as<" not in "\n".join(
    line for line in final.splitlines()
    if "item.as<" in line
)
assert final.count("parseCard(") >= 2
assert '0.7.0-preview.3.1-touch' in cfg.read_text(encoding="utf-8")

print("[OK] 2 conversoes invalidas removidas")
print("[OK] JsonObject agora e passado diretamente a parseCard(JsonObjectConst)")
print("[OK] versao: 0.7.0-preview.3.1-touch")
