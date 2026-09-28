from pathlib import Path
import re

root = Path('.')
touch = root / 'src/touch_input.cpp'
main = root / 'src/main.cpp'
cfg = root / 'include/config.h'

for p in (touch, main, cfg):
    if not p.exists():
        raise RuntimeError(f'Arquivo ausente: {p}')

# 1) Touch IRQ: detach only if this firmware attached it before.
t = touch.read_text(encoding='utf-8')

global_anchor = '''volatile bool gTouchIrqPending = true;

void IRAM_ATTR onGt911Interrupt() {
'''
global_replacement = '''volatile bool gTouchIrqPending = true;
bool gTouchInterruptAttached = false;

void IRAM_ATTR onGt911Interrupt() {
'''
if 'gTouchInterruptAttached' not in t:
    if global_anchor not in t:
        raise RuntimeError('Anchor global de IRQ nao encontrado')
    t = t.replace(global_anchor, global_replacement, 1)

old_detach = '''    detachInterrupt(
        digitalPinToInterrupt(
            Config::TOUCH_IRQ_PIN));

'''
new_detach = '''    if (gTouchInterruptAttached) {
        detachInterrupt(
            digitalPinToInterrupt(
                Config::TOUCH_IRQ_PIN));

        gTouchInterruptAttached =
            false;
    }

'''
if old_detach in t:
    t = t.replace(old_detach, new_detach, 1)
elif new_detach not in t:
    raise RuntimeError('Trecho detachInterrupt esperado nao encontrado')

old_attach = '''        attachInterrupt(
            digitalPinToInterrupt(
                Config::TOUCH_IRQ_PIN),
            onGt911Interrupt,
            FALLING);

        irqEnabled_ = true;
'''
new_attach = '''        attachInterrupt(
            digitalPinToInterrupt(
                Config::TOUCH_IRQ_PIN),
            onGt911Interrupt,
            FALLING);

        gTouchInterruptAttached =
            true;

        irqEnabled_ = true;
'''
if old_attach in t:
    t = t.replace(old_attach, new_attach, 1)
elif new_attach not in t:
    raise RuntimeError('Trecho attachInterrupt esperado nao encontrado')

touch.write_text(t, encoding='utf-8')

# 2) Diagnostic newline: replace a literal backslash-n in C++ string with a real C escape.
m = main.read_text(encoding='utf-8')
m = m.replace('heap=%u\\\\n",', 'heap=%u\\n",')
m = m.replace('reason=%s\\\\n",', 'reason=%s\\n",')
main.write_text(m, encoding='utf-8')

# 3) Version bump.
c = cfg.read_text(encoding='utf-8')
if '0.7.0-preview.3.1.2-touch' not in c:
    c, n = re.subn(
        r'constexpr char APP_VERSION\[\]\s*=\s*"0\.7\.0-preview\.3\.1\.1-touch"\s*;',
        'constexpr char APP_VERSION[] = "0.7.0-preview.3.1.2-touch";',
        c,
        count=1,
    )
    if n != 1:
        raise RuntimeError('APP_VERSION 0.7.0-preview.3.1.1-touch nao encontrado')
    cfg.write_text(c, encoding='utf-8')

# Guards.
tf = touch.read_text(encoding='utf-8')
mf = main.read_text(encoding='utf-8')
cf = cfg.read_text(encoding='utf-8')
assert 'gTouchInterruptAttached = false;' in tf
assert 'if (gTouchInterruptAttached)' in tf
assert 'gTouchInterruptAttached =' in tf
assert '0.7.0-preview.3.1.2-touch' in cf
if '[sd-first] enabled=' in mf:
    assert 'heap=%u\\\\n",' not in mf

print('[OK] detachInterrupt condicionado ao handler instalado')
print('[OK] newline do diagnostico SD-first corrigido')
print('[OK] versao 0.7.0-preview.3.1.2-touch')
