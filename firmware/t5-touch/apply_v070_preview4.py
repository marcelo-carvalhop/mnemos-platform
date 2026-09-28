from pathlib import Path
import base64, re, shutil
ROOT = Path.cwd()
PKG = Path(__file__).resolve().parent
README_ADD = base64.b64decode("CiMjIE9UQSBsb2NhbCB2ZXJpZmljYWRhCgpBIGAwLjcuMC1wcmV2aWV3LjRgIGludHJvZHV6IGluc3RhbGHDp8OjbyBBL0IgcGVsbyBtaWNyb1NELCB1c2FuZG8gYGFwcDBgLApgYXBwMWAgZSBgb3RhZGF0YWAgasOhIHByZXNlbnRlcyBuYSB0YWJlbGEgZGUgcGFydGnDp8O1ZXMuCgpPIHBhY290ZSBkZSBhdHVhbGl6YcOnw6NvIGZpY2EgZW06CgpgYGB0ZXh0Ci9tbmVtb3MvdXBkYXRlL21hbmlmZXN0Lmpzb24KL21uZW1vcy91cGRhdGUvZmlybXdhcmUuYmluCmBgYAoKTyBtYW5pZmVzdG8gdXNhIGBtbmVtb3Mub3RhL3YxYCBlIMOpIHZhbGlkYWRvIGFudGVzIGRlIHF1YWxxdWVyIGdyYXZhw6fDo286Cm1vZGVsbywgcHJvdG9jb2xvLCBnZXJhw6fDo28gbW9ub3TDtG5pY2EsIHRhbWFuaG8sIG1hZ2ljIGJ5dGUgZGUgaW1hZ2VtIEVTUCBlClNIQS0yNTYuIEEgaW1hZ2VtIHPDsyDDqSBlbnRyZWd1ZSBhIGBVcGRhdGVgIGRlcG9pcyBkYSB2ZXJpZmljYcOnw6NvIGNvbXBsZXRhLgoKYGdlbmVyYXRpb25gIMOpIG8gbWVjYW5pc21vIGFudGktZG93bmdyYWRlIGRvIGZpcm13YXJlLiBBIGJ1aWxkIGF0dWFsIHVzYQpgNzA0MDBgOyB1bSBwYWNvdGUgT1RBIHByZWNpc2EgdGVyIGdlcmHDp8OjbyBtYWlvci4KCkEgYXR1YWxpemHDp8OjbyDDqSByZWN1c2FkYSBxdWFuZG8gdW1hIGJhdGVyaWEgZGV0ZWN0YWRhIGVzdMOhIGFiYWl4byBkZSAyMCUuCk8gbWFuaWZlc3RvIHRhbWLDqW0gcHJlY2lzYSBjb250ZXIgYGFwcGx5PXRydWVgLCBldml0YW5kbyBpbnN0YWxhw6fDo28gYXBlbmFzIHBvcgpjb3BpYXIgYWNpZGVudGFsbWVudGUgdW0gYXJxdWl2byBwYXJhIG8gY2FydMOjby4KCkFww7NzIHN1Y2Vzc28sIGBtYW5pZmVzdC5qc29uYCDDqSByZW5vbWVhZG8gcGFyYSBgbWFuaWZlc3QuYXBwbGllZC5qc29uYCBlIG8KRVNQMzIgcmVpbmljaWEgbm8gb3V0cm8gc2xvdCBPVEEuCgpBIHRhYmVsYSBhdHVhbCBmb3JuZWNlIGRvaXMgc2xvdHMgZGUgMyBNaUIuIEltYWdlbnMgbWFpb3JlcyBzw6NvIHJlamVpdGFkYXMuCgojIyMgUm9sbGJhY2sKCkEgaW5mcmFlc3RydXR1cmEgdXNhIEEvQiBlIGNvbnN1bHRhIG8gZXN0YWRvIE9UQSBkbyBFU1AtSURGLiBRdWFuZG8KYENPTkZJR19CT09UTE9BREVSX0FQUF9ST0xMQkFDS19FTkFCTEVgIGVzdGl2ZXIgcmVhbG1lbnRlIGhhYmlsaXRhZG8gbm8KYm9vdGxvYWRlciwgYSBhcGxpY2HDp8OjbyBjb25maXJtYSBhIG5vdmEgaW1hZ2VtIGRlcG9pcyBkZSBjb25jbHVpciBvIGJvb3QuCgpObyBBcmR1aW5vLUVTUDMyIDIuMC4xNyB1c2FkbyBhdHVhbG1lbnRlLCByb2xsYmFjayBhdXRvbcOhdGljbyBkbyBib290bG9hZGVyCm7Do28gZGV2ZSBzZXIgcHJlc3VtaWRvLiBBL0IgcmVkdXogbyByaXNjbyBkZSBzb2JyZXNjcmV2ZXIgYSBpbWFnZW0gZW0gZXhlY3XDp8OjbywKbWFzIHVtYSBpbWFnZW0gcXVlIG7Do28gaW5pY2lhbGl6ZSBwb2RlIGFpbmRhIGV4aWdpciByZWN1cGVyYcOnw6NvIHBvciBVU0IuCgojIyMgR2VyYcOnw6NvIGRvIHBhY290ZQoKRGVwb2lzIGRlIGNvbXBpbGFyIHVtYSB2ZXJzw6NvIGZ1dHVyYToKCmBgYGJhc2gKcHl0aG9uMyB0b29scy9tYWtlX290YV9idW5kbGUucHkgXAogIC5waW8vYnVpbGQvbGlseWdvLXQ1LTQ3LXMzLXRvdWNoL2Zpcm13YXJlLmJpbiBcCiAgLS12ZXJzaW9uIDAuNy4wLXByZXZpZXcuNC4xLXRvdWNoIFwKICAtLWdlbmVyYXRpb24gNzA0MDEKYGBgCgpDb3BpYXIgYGZpcm13YXJlLmJpbmAgZSBgbWFuaWZlc3QuanNvbmAgZ2VyYWRvcyBwYXJhIGAvbW5lbW9zL3VwZGF0ZS9gIG5vIFNELgo=").decode("utf-8")
CHANGELOG_ENTRY = base64.b64decode("IyMgMC43LjAtcHJldmlldy40LXRvdWNoCgotIGFkaWNpb25hIGBPdGFTZXJ2aWNlYDsKLSBpbnN0YWxhIGZpcm13YXJlIG5vIHNsb3QgT1RBIGluYXRpdm8gYSBwYXJ0aXIgZG8gbWljcm9TRDsKLSB2YWxpZGEgbWFuaWZlc3RvIGBtbmVtb3Mub3RhL3YxYDsKLSBleGlnZSBtb2RlbG8gZSBwcm90b2NvbG8gY29tcGF0w612ZWlzOwotIHVzYSBnZXJhw6fDo28gbW9ub3TDtG5pY2EgcGFyYSBibG9xdWVhciBkb3duZ3JhZGU7Ci0gdmFsaWRhIHRhbWFuaG8gZSBTSEEtMjU2IGFudGVzIGRlIGdyYXZhciBhIGZsYXNoOwotIGV4aWdlIGBhcHBseT10cnVlYDsKLSBibG9xdWVpYSBPVEEgY29tIGJhdGVyaWEgZGV0ZWN0YWRhIGFiYWl4byBkZSAyMCU7Ci0gbW92ZSBtYW5pZmVzdG8gYXBsaWNhZG8gcGFyYSBgbWFuaWZlc3QuYXBwbGllZC5qc29uYDsKLSBkZXRlY3RhIGUgZG9jdW1lbnRhIGRpc3BvbmliaWxpZGFkZSByZWFsIGRlIHJvbGxiYWNrIGRvIGJvb3Rsb2FkZXI7Ci0gYWRpY2lvbmEgZmVycmFtZW50YSBkZSBnZXJhw6fDo28gZGUgYnVuZGxlIE9UQTsKLSBuw6NvIGFsdGVyYSBITUkuCg==").decode("utf-8")
CHECKLIST_ADD = base64.b64decode("CiMjIFPDqXJpZSAwLjcgcHJldmlldy40IOKAlCBPVEEgbG9jYWwKCi0gWyBdIGJvb3Qgc2VtIGAvbW5lbW9zL3VwZGF0ZS9tYW5pZmVzdC5qc29uYCBjb250aW51YSBub3JtYWw7Ci0gWyBdIG1hbmlmZXN0byBjb20gYGFwcGx5PWZhbHNlYCBuw6NvIGluc3RhbGE7Ci0gWyBdIG1vZGVsbyBpbmNvcnJldG8gw6kgcmVqZWl0YWRvOwotIFsgXSBwcm90b2NvbG8gaW5jb21wYXTDrXZlbCDDqSByZWplaXRhZG87Ci0gWyBdIGdlcmHDp8OjbyA8PSBnZXJhw6fDo28gYXR1YWwgw6kgcmVqZWl0YWRhOwotIFsgXSBTSEEtMjU2IGluY29ycmV0byDDqSByZWplaXRhZG8gYW50ZXMgZGUgYFVwZGF0ZS5iZWdpbmA7Ci0gWyBdIHRhbWFuaG8gaW5jb3JyZXRvIMOpIHJlamVpdGFkbzsKLSBbIF0gYmF0ZXJpYSBkZXRlY3RhZGEgPDIwJSBibG9xdWVpYSBpbnN0YWxhw6fDo287Ci0gWyBdIGJ1bmRsZSB2w6FsaWRvIMOpIGdyYXZhZG8gbm8gc2xvdCBPVEEgaW5hdGl2bzsKLSBbIF0gYXDDs3MgaW5zdGFsYcOnw6NvIG8gZGlzcG9zaXRpdm8gcmVpbmljaWEgbm8gbm92byBzbG90OwotIFsgXSBtYW5pZmVzdG8gdmlyYSBgbWFuaWZlc3QuYXBwbGllZC5qc29uYDsKLSBbIF0gYmlibGlvdGVjYSBTRC1maXJzdCBwZXJtYW5lY2UgaW50YWN0YTsKLSBbIF0gZXN0YWRvcyBGU1JTIHBlcm1hbmVjZW0gaW50YWN0b3M7Ci0gWyBdIHNlcmlhbCBpbmZvcm1hIGBydW5uaW5nPWFwcDAvYXBwMWAgZSBgbmV4dD1hcHAxL2FwcDBgOwotIFsgXSBzZXJpYWwgaW5mb3JtYSBleHBsaWNpdGFtZW50ZSBzZSByb2xsYmFjayBkbyBib290bG9hZGVyIGVzdMOhIGhhYmlsaXRhZG8uCg==").decode("utf-8")
TODO_ADD = base64.b64decode("CiMjIE9UQSByZW1vdGEgLyBkaXN0cmlidWnDp8OjbwoKTyBmaXJtd2FyZSBpbXBsZW1lbnRhIHByaW1laXJvIE9UQSBsb2NhbCB2ZXJpZmljYWRhIHBlbG8gbWljcm9TRC4gUGFyYQpkaXN0cmlidWnDp8OjbyByZW1vdGEsIEJhY2tlbmQvQXBwIG7Do28gZGV2ZW0gZW52aWFyIGJpbsOhcmlvIGRpcmV0YW1lbnRlIHBhcmEgYQpmbGFzaCBkbyB0ZXJtaW5hbC4gTyBjb250cmF0byByZWNvbWVuZGFkbyDDqSB1bSBtYW5pZmVzdG8gSFRUUFMKYG1uZW1vcy5vdGEvdjFgIGNvbSBvcyBtZXNtb3MgY2FtcG9zIHVzYWRvcyBsb2NhbG1lbnRlOgoKLSBgdmVyc2lvbmA7Ci0gYGdlbmVyYXRpb25gIG1vbm90w7RuaWNhOwotIGBtb2RlbGA7Ci0gYHByb3RvY29sTWluYCAvIGBwcm90b2NvbE1heGA7Ci0gYHNpemVgOwotIGBzaGEyNTZgOwotIFVSTCBIVFRQUyBkYSBpbWFnZW0uCgpBIGltYWdlbSByZW1vdGEgZGV2ZXLDoSBzZXIgYmFpeGFkYSBwYXJhIHN0YWdpbmcgbm8gbWljcm9TRCwgdmVyaWZpY2FkYSBlIHPDswpkZXBvaXMgaW5zdGFsYWRhIG5vIHNsb3QgT1RBLgoKUGFyYSBwcm9kdcOnw6NvLCBhZGljaW9uYXIgYXNzaW5hdHVyYSBjcmlwdG9ncsOhZmljYSBkbyBtYW5pZmVzdG8vaW1hZ2VtIGNvbSB1bWEKY2hhdmUgcMO6YmxpY2EgZW1iYXJjYWRhIG5vIGZpcm13YXJlLiBTSEEtMjU2ICsgVExTIHByb3RlZ2VtIGludGVncmlkYWRlIGVtCnRyw6Juc2l0byBlIGNvcnJlc3BvbmTDqm5jaWEgZGEgaW1hZ2VtLCBtYXMgbsOjbyBzdWJzdGl0dWVtIGNvZGUgc2lnbmluZyBjb250cmEKY29tcHJvbWV0aW1lbnRvIGRvIHNlcnZpZG9yIGRlIGF0dWFsaXphw6fDo28uCgpOZW5odW0gZW5kcG9pbnQgZGUgQmFja2VuZCDDqSBjcmlhZG8gb3UgbW9kaWZpY2FkbyBwZWxvIGZpcm13YXJlLgo=").decode("utf-8")

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")
def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")

# New source/tool/example files.
shutil.copy2(PKG/"payload/include/ota_service.h", ROOT/"include/ota_service.h")
shutil.copy2(PKG/"payload/src/ota_service.cpp", ROOT/"src/ota_service.cpp")
(ROOT/"tools").mkdir(exist_ok=True)
shutil.copy2(PKG/"payload/tools/make_ota_bundle.py", ROOT/"tools/make_ota_bundle.py")
(ROOT/"examples/ota").mkdir(parents=True, exist_ok=True)
shutil.copy2(PKG/"payload/examples/ota/manifest.example.json", ROOT/"examples/ota/manifest.example.json")

# config
p="include/config.h"; s=read(p)
if "0.7.0-preview.3.1.2-touch" not in s: raise RuntimeError("baseline esperada 0.7.0-preview.3.1.2-touch")
s = re.sub(
    r'constexpr char APP_VERSION\[\]\s*=\s*\"[^\"]+\"\s*;',
    'constexpr char APP_VERSION[] = "0.7.0-preview.4-touch";', s, count=1)
anchor = 'constexpr char DEVICE_MODEL[] = "LILYGO-T5-4.7-S3-TOUCH";\n'
if anchor not in s: raise RuntimeError("DEVICE_MODEL anchor ausente")
ota_cfg = '''constexpr uint32_t OTA_GENERATION = 70400U;\nconstexpr uint32_t OTA_MAX_IMAGE_BYTES = 0x300000U;\nconstexpr uint8_t OTA_MIN_BATTERY_PERCENT = 20;\nconstexpr char OTA_LOCAL_MANIFEST_PATH[] = "/mnemos/update/manifest.json";\nconstexpr char OTA_APPLIED_MANIFEST_PATH[] = "/mnemos/update/manifest.applied.json";\nconstexpr char OTA_LOCAL_IMAGE_PATH[] = "/mnemos/update/firmware.bin";\n'''
if "OTA_GENERATION" not in s: s=s.replace(anchor, anchor+"\n"+ota_cfg,1)
write(p,s)

# SD creates update dir.
p="src/sd_card_service.cpp"; s=read(p)
if '"/mnemos/update"' not in s:
    const_anchor = 'constexpr const char* EXPORT_DIR =\n    "/mnemos/export";\n'
    if const_anchor not in s: raise RuntimeError("EXPORT_DIR anchor ausente")
    s=s.replace(const_anchor,const_anchor+'\nconstexpr const char* UPDATE_DIR =\n    "/mnemos/update";\n',1)
    folder_anchor = '''    if (!SD.exists(EXPORT_DIR)) {\n        if (!SD.mkdir(EXPORT_DIR)) {\n            return false;\n        }\n    }\n'''
    folder_new = folder_anchor + '''\n    if (!SD.exists(UPDATE_DIR)) {\n        if (!SD.mkdir(UPDATE_DIR)) {\n            return false;\n        }\n    }\n'''
    if folder_anchor not in s: raise RuntimeError("ensureFolders export anchor ausente")
    s=s.replace(folder_anchor,folder_new,1)
write(p,s)

# main integration
p="src/main.cpp"; s=read(p)
if '#include "ota_service.h"' not in s:
    inc_anchor = '#include "network_service.h"\n'
    if inc_anchor not in s: raise RuntimeError("network include anchor ausente")
    s=s.replace(inc_anchor,inc_anchor+'#include "ota_service.h"\n',1)
if "OtaService otaService;" not in s:
    global_anchor="PowerService powerService;\n"
    if global_anchor not in s: raise RuntimeError("PowerService global anchor ausente")
    s=s.replace(global_anchor,global_anchor+"OtaService otaService;\n",1)

# Begin OTA after SD mount, before library loading.
anchor = "    sdCardService.begin();\n\n    touchInput.setPortrait(\n"
if anchor not in s: raise RuntimeError("sd begin anchor ausente")
if "otaService.begin();" not in s:
    repl = "    sdCardService.begin();\n    otaService.begin();\n\n    if (sdCardService.mounted()) {\n        otaService.applyLocalUpdateIfRequested(\n            batteryService.available(),\n            batteryService.percent());\n    }\n\n    touchInput.setPortrait(\n"
    s=s.replace(anchor,repl,1)

# Confirm only after successful core initialization and render.
anchor = '''    if (touchInput.online()) {\n        renderHome();\n    } else {\n        display.showTouchMissing();\n    }\n}'''
if anchor not in s: raise RuntimeError("setup final anchor ausente")
if "otaService.confirmRunningImage();" not in s:
    repl = '''    if (touchInput.online()) {\n        renderHome();\n    } else {\n        display.showTouchMissing();\n    }\n\n    otaService.confirmRunningImage();\n}'''
    s=s.replace(anchor,repl,1)
write(p,s)

# docs
p="README.md"; s=read(p)
if "## OTA local verificada" not in s: s += "\n\n"+README_ADD+"\n"
write(p,s)
p="CHANGELOG.md"; s=read(p); first,rest=s.split("\n",1); s=first+"\n\n"+CHANGELOG_ENTRY+"\n\n"+rest.lstrip("\n"); write(p,s)
p="docs/TEST_CHECKLIST.md"; s=read(p); s += "\n\n"+CHECKLIST_ADD+"\n"; write(p,s)
todo=ROOT/"../../docs/integration/T5_TOUCH_EXTERNAL_TODO.md"
if todo.exists():
    t=todo.read_text(encoding="utf-8")
    if "## OTA remota / distribuição" not in t: t += "\n\n"+TODO_ADD+"\n"
    todo.write_text(t,encoding="utf-8")

# guards
assert "0.7.0-preview.4-touch" in read("include/config.h")
assert "OTA_GENERATION = 70400U" in read("include/config.h")
assert (ROOT/"include/ota_service.h").exists()
assert (ROOT/"src/ota_service.cpp").exists()
assert "applyLocalUpdateIfRequested" in read("src/main.cpp")
assert "otaService.confirmRunningImage();" in read("src/main.cpp")
assert '"/mnemos/update"' in read("src/sd_card_service.cpp")
print("[OK] 0.7.0-preview.4-touch aplicada")
print("[OK] OTA local A/B + SHA-256 + anti-downgrade")
print("[OK] ferramenta de bundle instalada em tools/")