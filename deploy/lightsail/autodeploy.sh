#!/usr/bin/env bash
# Continuous deployment of `main`, pulled by the server (cron, every 3 min).
#
# The AWS project's SCP forbids IAM OIDC providers, so GitHub cannot be given
# AWS access to open the firewall for a push-based deploy. Pulling needs no
# secret at all: the repository is public, and the server only reads the
# GitHub API and the source tarball.
#
# A commit is deployed only when every GitHub Actions run for it has
# finished and none failed. A commit with no runs (paths the CI ignores) is
# deployed once it is old enough for any run to have been created.
#
#   autodeploy.sh                 # what cron runs
#   autodeploy.sh --ref dev --force   # deploy another branch now, ignoring CI
set -euo pipefail

REPO="${MNEMOS_REPO:-marcelo-carvalhop/mnemos-platform}"
REF=main
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT=/opt/mnemos
STATE="$ROOT/.deployed-sha"
FAILED="$ROOT/.failed-sha"
NODE_IMAGE="node:22.23.5-alpine"
API="https://api.github.com/repos/$REPO"
log() { echo "$(date -u +%FT%TZ) [autodeploy] $*"; }

exec 9>/tmp/mnemos-autodeploy.lock
flock -n 9 || exit 0
command -v jq >/dev/null || { log "jq not installed"; exit 1; }

gh() { curl -fsS -H "Accept: application/vnd.github+json" "$API/$1"; }

COMMIT=$(gh "commits/$REF")
SHA=$(jq -r .sha <<<"$COMMIT")
[ -n "$SHA" ] && [ "$SHA" != null ] || { log "could not resolve $REF"; exit 1; }

if [ "$FORCE" = 0 ]; then
  [ "$SHA" = "$(cat "$STATE" 2>/dev/null)" ] && exit 0
  [ "$SHA" = "$(cat "$FAILED" 2>/dev/null)" ] && exit 0

  RUNS=$(gh "actions/runs?head_sha=$SHA&per_page=100")
  TOTAL=$(jq '.total_count' <<<"$RUNS")
  PENDING=$(jq '[.workflow_runs[] | select(.status != "completed")] | length' <<<"$RUNS")
  BAD=$(jq -r '[.workflow_runs[] | select(.status == "completed")
               | select(.conclusion | IN("success","skipped","neutral") | not)
               | .name] | join(", ")' <<<"$RUNS")

  if [ -n "$BAD" ]; then
    log "${SHA:0:7}: CI failed ($BAD); not deploying"
    echo "$SHA" > "$FAILED"
    exit 0
  fi
  [ "$PENDING" -gt 0 ] && exit 0
  if [ "$TOTAL" -eq 0 ]; then
    DATE=$(jq -r .commit.committer.date <<<"$COMMIT")
    AGE=$(( $(date -u +%s) - $(date -u -d "$DATE" +%s) ))
    [ "$AGE" -lt 600 ] && exit 0
  fi
fi

log "deploying $REF ${SHA:0:7}"
WORK=$(mktemp -d /tmp/mnemos-release.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$SHA" | tar -xz -C "$WORK" --strip-components=1
if [ ! -f "$WORK/deploy/lightsail/apply.sh" ]; then
  log "${SHA:0:7} has no deploy/lightsail/apply.sh; skipping"
  echo "$SHA" > "$FAILED"
  exit 0
fi

log "building web"
# As this user, not root: files root creates in $WORK would outlive the trap.
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$WORK/app/web:/app" -w /app -e NODE_OPTIONS=--max-old-space-size=1536 \
  "$NODE_IMAGE" sh -c "npm ci --no-audit --no-fund --loglevel=error && npx ng build --configuration production" \
  </dev/null

if bash "$WORK/deploy/lightsail/apply.sh" "$WORK" "$WORK/app/web/dist/mnemos-web/browser" </dev/null; then
  echo "$SHA" > "$STATE"
  rm -f "$FAILED"
  log "deployed ${SHA:0:7}"
else
  echo "$SHA" > "$FAILED"
  log "${SHA:0:7} failed to apply (rolled back if it got that far)"
  exit 1
fi
