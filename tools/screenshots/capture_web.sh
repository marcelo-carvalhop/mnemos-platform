#!/usr/bin/env bash
# Captures every screen of the web client into screenshots/web.
#
# The published bundle is a static SPA that keeps its session in localStorage
# and talks to its own origin, so a local server that serves the build, injects
# a session and answers /v1/* is enough to reach the signed-in screens without
# Postgres, Docker or a real account. See screenshots/README.md.
#
#   tools/screenshots/capture_web.sh [path-to-chrome]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
build="$repo/app/web/dist/mnemos-web/browser"
out="${MNEMOS_SCREENSHOT_OUT:-$repo/screenshots/web}"
port="${MNEMOS_SCREENSHOT_PORT:-4600}"
# Variantes para revisão, fora da pasta documentada:
#   MNEMOS_SCREENSHOT_SCHEME=dark       tema escuro (prefers-color-scheme)
#   MNEMOS_SCREENSHOT_SIZE=390,844      largura de celular
#   MNEMOS_SCREENSHOT_OUT=/outra/pasta  para não sobrescrever screenshots/web
size="${MNEMOS_SCREENSHOT_SIZE:-1440,900}"
scheme_flag=()
if [ "${MNEMOS_SCREENSHOT_SCHEME:-light}" = "dark" ]; then
  scheme_flag=(--blink-settings=preferredColorScheme=0)
fi

chrome="${1:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
[ -x "$chrome" ] || chrome="$(command -v google-chrome || command -v chromium || true)"
if [ -z "$chrome" ]; then
  echo "Chrome not found. Pass its path as the first argument." >&2
  exit 1
fi

if [ ! -f "$build/index.html" ]; then
  echo "No web build at $build — nothing to capture." >&2
  exit 1
fi

# Caminho nativo do sistema, não o `/tmp/...` do MSYS: o Chrome no Windows não
# resolve o caminho POSIX, falha ao abrir o perfil e passa a recusar
# `localStorage` — o que fazia a sessão injetada sumir e as capturas saírem
# todas no estado deslogado.
work="$(python -c 'import tempfile; print(tempfile.mkdtemp())')"
trap 'kill "${server:-0}" 2>/dev/null || true; rm -rf "$work"' EXIT

python "$here/web_fixture_server.py" "$build" "$port" &
server=$!
until curl -sf -o /dev/null "http://127.0.0.1:$port/"; do sleep 0.2; done

mkdir -p "$out"

# Um perfil por captura. Compartilhar um só fazia as invocações disputarem o
# lock do perfil, e uma delas fotografava um estado velho — foi assim que a
# tela do dispositivo saiu vazia mesmo com o terminal presente no DOM.
shot() { # url profile filename
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --user-data-dir="$work/$2-${3%.png}" --window-size="$size" "${scheme_flag[@]}" \
    --force-device-scale-factor=2 --virtual-time-budget=20000 \
    --screenshot="$out/$3" "$1" >/dev/null 2>&1
  echo "  $3"
}

base="http://127.0.0.1:$port"

# Signed out. A separate browser profile, so no injected session leaks in.
shot "$base/?anon=1"       anon "01-landing.png"
shot "$base/entrar?anon=1" anon "02-entrar.png"

# Signed in, via the session the server injects into localStorage.
shot "$base/hoje"          auth "03-hoje.png"
shot "$base/biblioteca"    auth "04-biblioteca.png"
shot "$base/criar"         auth "05-criar.png"
# As quatro origens de Criar sao estado do componente, nao rota: o servidor de
# fixture aperta o botao para a foto sair no estado certo (ver `?clique=`).
shot "$base/criar?clique=Texto%20colado" auth "05b-criar-texto-colado.png"
shot "$base/criar?clique=PDF"            auth "05c-criar-pdf.png"
shot "$base/estudar"       auth "06-estudar.png"
shot "$base/progresso"     auth "07-progresso.png"
shot "$base/dispositivo"   auth "08-dispositivo.png"
shot "$base/configuracoes" auth "09-configuracoes.png"
# Ids fixos do servidor de fixture: um baralho, uma geração rodando e outra
# pronta para aprovar.
shot "$base/biblioteca/01927f01-0000-7000-8000-000000000001" auth "10-baralho.png"
shot "$base/gerar/01927f01-0000-7000-8000-00000000a001"      auth "11-gerando.png"
shot "$base/aprovar/01927f01-0000-7000-8000-00000000a002"    auth "12-aprovar.png"
shot "$base/confirmar?token=exemplo&anon=1"                 anon "13-confirmar.png"

echo "Wrote 15 screenshots to $out"
