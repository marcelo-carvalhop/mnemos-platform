#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v git >/dev/null; then
  echo "Git is not installed. On Linux Mint: sudo apt install git"
  exit 1
fi

if [[ ! -d .git ]]; then
  git init
fi

git branch -M main

if [[ -z "$(git config --get user.name || true)" ]]; then
  read -r -p "Git commit name: " name
  git config user.name "$name"
fi

if [[ -z "$(git config --get user.email || true)" ]]; then
  read -r -p "Git commit email: " email
  git config user.email "$email"
fi

bash tools/repository/check-before-commit.sh

echo
echo "Current identity:"
git config user.name
git config user.email

echo
git status --short

echo
read -r -p "Stage all non-ignored files with 'git add .'? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  git add .
  git diff --cached --check
  git status
else
  echo "Nothing staged. See SETUP_GITHUB.md for the manual workflow."
  exit 0
fi

echo
read -r -p "Create the initial v0.3.0 commit now? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  git commit -m "feat: establish Mnemos v0.3 monorepo architecture"
  echo "Commit created. Configure 'origin' and push using SETUP_GITHUB.md."
else
  echo "Files remain staged; review with: git diff --cached"
fi
