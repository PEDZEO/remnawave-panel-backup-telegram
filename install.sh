#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main}"
REPO_API="${REPO_API:-https://api.github.com/repos/PEDZEO/remnawave-panel-backup-telegram/commits/main}"
REPO_SHA=""
MANAGER_URL=""
TMP_MANAGER="$(mktemp /tmp/panel-backup-manager.XXXXXX.sh)"

cleanup() {
  rm -f "$TMP_MANAGER"
}
trap cleanup EXIT

REPO_SHA="$(curl -fsSL "$REPO_API" 2>/dev/null | sed -n 's/.*"sha":[[:space:]]*"\([a-f0-9]\{40\}\)".*/\1/p' | head -n1 || true)"
if [[ -n "$REPO_SHA" ]]; then
  MANAGER_URL="https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/${REPO_SHA}/scripts/bin/manager.sh"
else
  MANAGER_URL="${RAW_BASE}/scripts/bin/manager.sh"
fi

curl -fsSL "$MANAGER_URL" -o "$TMP_MANAGER"
chmod 700 "$TMP_MANAGER"

exec bash "$TMP_MANAGER" "$@"
