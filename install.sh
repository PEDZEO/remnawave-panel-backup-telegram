#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main}"
MANAGER_URL="${RAW_BASE}/manager.sh"
TMP_MANAGER="$(mktemp /tmp/panel-backup-manager.XXXXXX.sh)"

cleanup() {
  rm -f "$TMP_MANAGER"
}
trap cleanup EXIT

curl -fsSL "$MANAGER_URL" -o "$TMP_MANAGER"
chmod 700 "$TMP_MANAGER"

exec bash "$TMP_MANAGER" "$@"
