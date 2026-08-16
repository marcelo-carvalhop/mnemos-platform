#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail=0

echo "[1/5] Checking forbidden secret/local filenames..."
while IFS= read -r path; do
  case "$path" in
    */.env.example|./backend/.env.example) continue ;;
  esac
  echo "ERROR: sensitive/local file found: $path"
  fail=1
done < <(find . -type f \( \
  -name '.env' -o -name '*.pem' -o -name '*.key' -o -name '*.p12' -o \
  -name '*.pfx' -o -name '*.jks' -o -name '*.keystore' -o \
  -name 'secrets.json' -o -name 'credentials.json' -o \
  -name 'google-services.json' -o -name 'GoogleService-Info.plist' \
\) -print)

echo "[2/5] Checking generated build/cache directories..."
while IFS= read -r path; do
  echo "ERROR: generated/cache path found: $path"
  fail=1
done < <(find . -type d \( \
  -name '.dart_tool' -o -name '.gradle' -o -name '.pio' -o \
  -name '__pycache__' -o -name 'build' \
\) -print)

echo "[3/5] Checking large files (>10 MiB project policy)..."
while IFS= read -r path; do
  echo "ERROR: large file found: $path"
  fail=1
done < <(find . -type f -size +10M -print)

echo "[4/5] Checking JSON syntax..."
while IFS= read -r path; do
  python3 -m json.tool "$path" >/dev/null || fail=1
done < <(find spec -type f -name '*.json' -print | sort)

echo "[5/5] Checking Git whitespace when repository/staging exists..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check || fail=1
  git diff --cached --check || fail=1
else
  echo "Git repository not initialized yet; skipping git diff checks."
fi

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "Repository check FAILED. Correct the items above before committing."
  exit 1
fi

echo
printf '%s\n' "Repository check OK."
