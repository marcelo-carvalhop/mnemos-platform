#!/usr/bin/env bash
# Applies a release on the server. Shared by deploy.sh (manual, from a dev
# machine) and autodeploy.sh (cron, from GitHub).
#
#   apply.sh <source-dir> <web-dir>
#
# <source-dir> holds backend/, shared/ and deploy/lightsail/; <web-dir> holds
# the Angular build. The server's .env is kept. The previous API image is
# tagged first, so a release whose /healthz fails rolls back to it.
#
# Must not read stdin: deploy.sh feeds bash its script on stdin.
set -euo pipefail

SRC="$(cd "$1" && pwd)"
WEB="$(cd "$2" && pwd)"
ROOT=/opt/mnemos
DIR="$ROOT/deploy/lightsail"

test -f "$DIR/.env" || { echo "[apply] missing $DIR/.env" >&2; exit 1; }
test -f "$WEB/index.html" || { echo "[apply] no index.html in $WEB" >&2; exit 1; }

echo "[apply] installing files"
cp "$DIR/.env" /tmp/mnemos.env
rm -rf "$ROOT/backend" "$ROOT/shared" "$ROOT/web.new"
cp -a "$SRC/backend" "$SRC/shared" "$ROOT/"
mkdir -p "$DIR"
find "$DIR" -maxdepth 1 -type f ! -name .env -delete
cp -a "$SRC/deploy/lightsail/." "$DIR/"
rm -f "$DIR/.env.example"
# Replace the contents, never the directory: Caddy bind-mounts web/, and a
# bind mount follows the inode. rm + mv left the container serving an empty,
# deleted directory (every page 404, API unaffected).
mkdir -p "$ROOT/web"
find "$ROOT/web" -mindepth 1 -delete
cp -a "$WEB/." "$ROOT/web/"
rm -rf "$ROOT/web.new"
cp /tmp/mnemos.env "$DIR/.env" && chmod 600 "$DIR/.env" && rm -f /tmp/mnemos.env
chmod +x "$DIR"/*.sh

cd "$DIR"
set -a; . ./.env; set +a

if docker image inspect mnemos-server:latest >/dev/null 2>&1; then
  docker tag mnemos-server:latest mnemos-server:previous
fi

echo "[apply] building API image"
docker compose build server </dev/null
docker compose up -d postgres </dev/null
# Migrations are additive (§11.4), so the previous image still runs on the
# new schema if we have to roll back below.
docker compose run --rm -T migrate </dev/null
docker compose up -d --remove-orphans </dev/null
# The Caddyfile was deleted and copied again above, so it is a new file and
# the container's bind mount still shows the old one. Restart Caddy only when
# the config actually changed: a restart on every deploy drops connections.
if ! docker compose exec -T caddy cat /etc/caddy/Caddyfile </dev/null | cmp -s - Caddyfile; then
  echo "[apply] Caddyfile changed; restarting caddy"
  docker compose restart caddy </dev/null
fi

healthy() {
  for _ in $(seq 1 24); do
    curl -fsS "https://$DOMAIN/healthz" >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}

if ! healthy; then
  echo "[apply] /healthz failed; rolling back the API image" >&2
  if docker image inspect mnemos-server:previous >/dev/null 2>&1; then
    docker tag mnemos-server:previous mnemos-server:latest
    docker compose up -d --force-recreate server </dev/null
  fi
  exit 1
fi

# Daily backup. A fresh box has no crontab: `crontab -l` and grep exit 1.
mkdir -p "$ROOT/backups" "$ROOT/logs"
{ crontab -l 2>/dev/null | grep -v -e 'deploy/lightsail/backup.sh' -e 'deploy/lightsail/autodeploy.sh' || true
  echo "30 3 * * * $DIR/backup.sh >> $ROOT/backups/backup.log 2>&1"
  echo "*/3 * * * * $DIR/autodeploy.sh >> $ROOT/logs/autodeploy.log 2>&1"
} | crontab -

docker image prune -f >/dev/null
docker compose ps --format '{{.Service}}\t{{.Status}}'
echo "[apply] OK https://$DOMAIN"
