from pathlib import Path
import re

root = Path(".")

cpp = root / "src/sd_card_service.cpp"
cfg = root / "include/config.h"

for p in (cpp, cfg):
    if not p.exists():
        raise RuntimeError(f"Arquivo ausente: {p}")

s = cpp.read_text(encoding="utf-8")

pattern = re.compile(
    r'item\s*\.\s*as\s*<\s*JsonObjectConst\s*>\s*\(\s*\)',
    re.MULTILINE
)

matches_before = list(pattern.finditer(s))

if not matches_before:
    # Permite reaplicar se o código já tiver sido corrigido manualmente.
    if "parseCard(" not in s:
        raise RuntimeError(
            "Nenhuma conversao invalida encontrada e parseCard() tambem nao foi localizado"
        )
    print("[INFO] Nenhuma ocorrencia item.as<JsonObjectConst>() pendente.")
else:
    s, replaced = pattern.subn("item", s)
    cpp.write_text(s, encoding="utf-8")
    print(f"[OK] Conversoes invalidas substituidas: {replaced}")

# Verificação independente da formatação.
final = cpp.read_text(encoding="utf-8")

remaining = list(pattern.finditer(final))
if remaining:
    raise RuntimeError(
        f"Ainda restam {len(remaining)} conversoes item.as<JsonObjectConst>()"
    )

# Atualiza a versão somente se ainda estiver em preview.3.
c = cfg.read_text(encoding="utf-8")

if "0.7.0-preview.3.1-touch" in c:
    print("[INFO] Versao ja estava em 0.7.0-preview.3.1-touch")
else:
    c, n = re.subn(
        r'constexpr char APP_VERSION\[\]\s*=\s*"0\.7\.0-preview\.3-touch"\s*;',
        'constexpr char APP_VERSION[] = "0.7.0-preview.3.1-touch";',
        c,
        count=1,
    )

    if n != 1:
        raise RuntimeError(
            "APP_VERSION esperado (preview.3 ou preview.3.1) nao encontrado"
        )

    cfg.write_text(c, encoding="utf-8")
    print("[OK] Versao atualizada para 0.7.0-preview.3.1-touch")

# Confirma que os dois blocos de parse do importador continuam presentes.
segment_start = final.find(
    "SdImportResult SdCardService::importDeckFileToCanonical(")
if segment_start < 0:
    raise RuntimeError(
        "importDeckFileToCanonical() nao encontrado")

segment = final[segment_start:]

direct_calls = len(re.findall(
    r'parseCard\s*\(\s*item\s*,\s*candidate\s*\)',
    segment,
    re.MULTILINE
))

if direct_calls < 2:
    raise RuntimeError(
        f"Esperadas pelo menos 2 chamadas parseCard(item, candidate); encontradas: {direct_calls}"
    )

print(f"[OK] Chamadas parseCard(item, candidate) verificadas: {direct_calls}")
print("[OK] Compatibilidade com ArduinoJson 7.4.3 corrigida")
