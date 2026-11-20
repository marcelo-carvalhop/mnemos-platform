#!/usr/bin/env bash
# Deploys the working tree to the Lightsail instance.
#
#   MNEMOS_HOST=3.13.6.164 MNEMOS_SSH_KEY=~/.ssh/mnemos-lightsail.pem \
#     deploy/lightsail/deploy.sh
#
# Builds the web locally (in a Node container, so no Node install is needed),
# ships backend/, shared/, deploy/lightsail/ and the web build over SSH,
# then builds the API image, migrates and restarts on the server.
# The server's .env is never touched; create it once from .env.example.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

HOST="${MNEMOS_HOST:?set MNEMOS_HOST}"
KEY="${MNEMOS_SSH_KEY:-$HOME/.ssh/mnemos-lightsail.pem}"
NODE_IMAGE="node:22.23.5-alpine"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$HOST")

echo "[deploy] building web in $NODE_IMAGE"
# MSYS_NO_PATHCONV keeps Git Bash on Windows from rewriting the mount paths.
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd)/app/web:/app" -w /app "$NODE_IMAGE" \
  sh -c "npm ci --no-audit --no-fund && npx ng build --configuration production"
test -f app/web/dist/mnemos-web/browser/index.html

echo "[deploy] packaging sources"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# Tracked and untracked-but-not-ignored files only: never .env, caches or venvs.
git ls-files -co --exclude-standard backend shared deploy/lightsail \
  | tar -czf "$STAGE/src.tgz" -T -
tar -czf "$STAGE/web.tgz" -C app/web/dist/mnemos-web/browser .


echo "[deploy] uploading to $HOST"
scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$STAGE/src.tgz" "$STAGE/web.tgz" "ubuntu@$HOST:/tmp/"

# apply.sh does the rest (install, build, migrate, restart, health check with
# rollback) — the same script the server's autodeploy runs.
"${SSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
STAGE=$(mktemp -d /tmp/mnemos-manual.XXXXXX)
trap 'rm -rf "$STAGE" /tmp/src.tgz /tmp/web.tgz' EXIT
mkdir -p "$STAGE/src" "$STAGE/web"
tar -xzf /tmp/src.tgz -C "$STAGE/src"
tar -xzf /tmp/web.tgz -C "$STAGE/web"
bash "$STAGE/src/deploy/lightsail/apply.sh" "$STAGE/src" "$STAGE/web" </dev/null
REMOTE
