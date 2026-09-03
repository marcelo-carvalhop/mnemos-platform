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
out="$repo/screenshots/web"
port="${MNEMOS_SCREENSHOT_PORT:-4600}"

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
    --user-data-dir="$work/$2-${3%.png}" --window-size=1440,900 \
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

echo "Wrote 11 screenshots to $out"
