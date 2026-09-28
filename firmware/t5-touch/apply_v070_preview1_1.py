
from pathlib import Path
import re

root = Path(".")

header = root / "include/network_service.h"
main = root / "src/main.cpp"
config = root / "include/config.h"

for p in (header, main, config):
    if not p.exists():
        raise RuntimeError(f"Arquivo ausente: {p}")

# 1) network_service.h usa Config::*
h = header.read_text(encoding="utf-8")

if '#include "config.h"' not in h:
    anchor = '#include <Preferences.h>\n'
    if anchor not in h:
        raise RuntimeError("Anchor de include não encontrado em network_service.h")
    h = h.replace(
        anchor,
        anchor + '#include "config.h"\n',
        1,
    )

header.write_text(h, encoding="utf-8")

# 2) scanWifiNetworks() chama helpers definidos mais abaixo
m = main.read_text(encoding="utf-8")

marker = "void scanWifiNetworks()"
pos = m.find(marker)
if pos < 0:
    raise RuntimeError("scanWifiNetworks() não encontrado em main.cpp")

prefix = m[:pos]

decl_block = (
    "String friendlyWifiError();\n"
    "void renderWifiMessage();\n\n"
)

if "String friendlyWifiError();" not in prefix:
    m = m[:pos] + decl_block + m[pos:]

main.write_text(m, encoding="utf-8")

# 3) bump de hotfix
c = config.read_text(encoding="utf-8")
c, n = re.subn(
    r'constexpr char APP_VERSION\[\]\s*=\s*"0\.7\.0-preview\.1-touch"\s*;',
    'constexpr char APP_VERSION[] = "0.7.0-preview.1.1-touch";',
    c,
    count=1,
)
if n != 1:
    raise RuntimeError(
        "APP_VERSION esperado (0.7.0-preview.1-touch) não encontrado"
    )

config.write_text(c, encoding="utf-8")

# validação
hf = header.read_text(encoding="utf-8")
mf = main.read_text(encoding="utf-8")
cf = config.read_text(encoding="utf-8")

scan_pos = mf.find("void scanWifiNetworks()")
decl_pos_1 = mf.find("String friendlyWifiError();")
decl_pos_2 = mf.find("void renderWifiMessage();")

assert '#include "config.h"' in hf
assert decl_pos_1 >= 0 and decl_pos_1 < scan_pos
assert decl_pos_2 >= 0 and decl_pos_2 < scan_pos
assert '0.7.0-preview.1.1-touch' in cf

print("[OK] network_service.h inclui config.h")
print("[OK] helpers declarados antes de scanWifiNetworks()")
print("[OK] versão: 0.7.0-preview.1.1-touch")
