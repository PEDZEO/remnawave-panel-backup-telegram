#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main}"
MODE_SET="${MODE+x}"
MODE="${MODE:-install}"
INTERACTIVE="${INTERACTIVE:-auto}"
BACKUP_FILE="${BACKUP_FILE:-}"
BACKUP_URL="${BACKUP_URL:-}"
RESTORE_ONLY="${RESTORE_ONLY:-all}"
RESTORE_DRY_RUN="${RESTORE_DRY_RUN:-0}"
RESTORE_NO_RESTART="${RESTORE_NO_RESTART:-0}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-}"
TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-}"
REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
TMP_DIR="$(mktemp -d /tmp/panel-backup-install.XXXXXX)"
SUDO=""

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

usage() {
  cat <<USAGE
Unified installer/manager for panel backup system.

Modes:
  MODE=install   install/update scripts, env and timer (default)
  MODE=restore   restore backup (all or selected components)

INTERACTIVE:
  INTERACTIVE=auto  show menu in terminal if MODE is not set explicitly (default)
  INTERACTIVE=1     force interactive menu
  INTERACTIVE=0     disable menu, run selected MODE directly

Examples:
  bash <(curl -fsSL ${RAW_BASE}/install.sh)

  TELEGRAM_BOT_TOKEN='token' TELEGRAM_ADMIN_ID='123' \
  TELEGRAM_THREAD_ID='42' MODE=install \
  bash <(curl -fsSL ${RAW_BASE}/install.sh)

  MODE=restore BACKUP_FILE='/var/backups/panel/panel-backup-xxx.tar.gz' \
  bash <(curl -fsSL ${RAW_BASE}/install.sh)

  MODE=restore BACKUP_URL='https://example.com/panel-backup.tar.gz' \
  RESTORE_ONLY='db,configs' RESTORE_DRY_RUN=1 \
  bash <(curl -fsSL ${RAW_BASE}/install.sh)
USAGE
}

if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

fetch() {
  local src="$1"
  local dst="$2"
  curl -fsSL "${RAW_BASE}/${src}" -o "$dst"
}

is_interactive() {
  if [[ "$INTERACTIVE" == "1" ]]; then
    return 0
  fi

  if [[ "$INTERACTIVE" == "0" ]]; then
    return 1
  fi

  [[ -t 0 && -t 1 && -z "$MODE_SET" ]]
}

detect_remnawave_dir() {
  local guessed

  for guessed in \
    "${REMNAWAVE_DIR}" \
    "/opt/remnawave" \
    "/srv/remnawave" \
    "/root/remnawave" \
    "/home/remnawave"; do
    [[ -n "$guessed" ]] || continue
    if [[ -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(docker inspect remnawave --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
  if [[ -n "$guessed" && -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /opt /srv /root /home -maxdepth 3 -type f -name '.env' 2>/dev/null | while read -r f; do d="$(dirname "$f")"; [[ -f "$d/docker-compose.yml" ]] || continue; grep -q '^POSTGRES_USER=' "$f" 2>/dev/null || continue; grep -q '^POSTGRES_DB=' "$f" 2>/dev/null || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  return 1
}

load_existing_env_defaults() {
  local old_bot=""
  local old_admin=""
  local old_thread=""
  local old_dir=""
  local detected=""

  if [[ -f /etc/panel-backup.env ]]; then
    old_bot="$(grep -E '^TELEGRAM_BOT_TOKEN=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_admin="$(grep -E '^TELEGRAM_ADMIN_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_thread="$(grep -E '^TELEGRAM_THREAD_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_dir="$(grep -E '^REMNAWAVE_DIR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
  fi

  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$old_bot}"
  TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-$old_admin}"
  TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-$old_thread}"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$old_dir}"

  detected="$(detect_remnawave_dir || true)"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$detected}"
}

ask_value() {
  local prompt="$1"
  local current="${2:-}"
  local input=""

  if [[ -n "$current" ]]; then
    read -r -p "${prompt} [${current}]: " input
  else
    read -r -p "${prompt}: " input
  fi

  if [[ -n "$input" ]]; then
    echo "$input"
  else
    echo "$current"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local answer=""

  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "${prompt} [Y/n]: " answer
      answer="${answer:-y}"
    else
      read -r -p "${prompt} [y/N]: " answer
      answer="${answer:-n}"
    fi

    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

prompt_install_settings() {
  load_existing_env_defaults

  echo
  echo "Configure backup settings:"
  TELEGRAM_BOT_TOKEN="$(ask_value "TELEGRAM_BOT_TOKEN (empty disables Telegram notifications)" "$TELEGRAM_BOT_TOKEN")"
  TELEGRAM_ADMIN_ID="$(ask_value "TELEGRAM_ADMIN_ID (chat ID)" "$TELEGRAM_ADMIN_ID")"
  TELEGRAM_THREAD_ID="$(ask_value "TELEGRAM_THREAD_ID (optional)" "$TELEGRAM_THREAD_ID")"
  REMNAWAVE_DIR="$(ask_value "REMNAWAVE_DIR (path to panel)" "$REMNAWAVE_DIR")"
}

install_files() {
  echo "[1/5] Downloading files from ${RAW_BASE}"
  fetch "panel-backup.sh" "$TMP_DIR/panel-backup.sh"
  fetch "panel-restore.sh" "$TMP_DIR/panel-restore.sh"
  fetch "systemd/panel-backup.service" "$TMP_DIR/panel-backup.service"
  fetch "systemd/panel-backup.timer" "$TMP_DIR/panel-backup.timer"

  echo "[2/5] Installing scripts and systemd units"
  $SUDO install -m 755 "$TMP_DIR/panel-backup.sh" /usr/local/bin/panel-backup.sh
  $SUDO install -m 755 "$TMP_DIR/panel-restore.sh" /usr/local/bin/panel-restore.sh
  $SUDO install -m 644 "$TMP_DIR/panel-backup.service" /etc/systemd/system/panel-backup.service
  $SUDO install -m 644 "$TMP_DIR/panel-backup.timer" /etc/systemd/system/panel-backup.timer
}

write_env() {
  load_existing_env_defaults

  echo "[3/5] Writing /etc/panel-backup.env"
  $SUDO install -d -m 755 /etc
  $SUDO bash -c "cat > /etc/panel-backup.env <<ENV
${TELEGRAM_BOT_TOKEN:+TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}}
${TELEGRAM_ADMIN_ID:+TELEGRAM_ADMIN_ID=${TELEGRAM_ADMIN_ID}}
${TELEGRAM_THREAD_ID:+TELEGRAM_THREAD_ID=${TELEGRAM_THREAD_ID}}
${REMNAWAVE_DIR:+REMNAWAVE_DIR=${REMNAWAVE_DIR}}
ENV"
  $SUDO chmod 600 /etc/panel-backup.env
  $SUDO chown root:root /etc/panel-backup.env

  echo "      REMNAWAVE_DIR=${REMNAWAVE_DIR:-not-detected}"
}

enable_timer() {
  echo "[4/5] Reloading systemd and enabling timer"
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now panel-backup.timer

  echo "[5/5] Done"
  $SUDO systemctl status --no-pager panel-backup.timer | sed -n '1,12p'
}

disable_timer() {
  echo "Disabling backup timer"
  $SUDO systemctl disable --now panel-backup.timer
  $SUDO systemctl status --no-pager panel-backup.timer | sed -n '1,12p' || true
}

run_restore() {
  local from_path="$BACKUP_FILE"
  local restore_cmd
  local only_args=()

  if [[ -z "$from_path" && -n "$BACKUP_URL" ]]; then
    echo "[restore] Downloading backup from URL"
    from_path="$TMP_DIR/remote-backup.tar.gz"
    curl -fL "$BACKUP_URL" -o "$from_path"
  fi

  if [[ -z "$from_path" ]]; then
    from_path="$(ls -1t /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
  fi

  if [[ -z "$from_path" || ! -f "$from_path" ]]; then
    echo "[restore] Backup archive not found. Set BACKUP_FILE or BACKUP_URL." >&2
    exit 1
  fi

  IFS=',' read -r -a only_list <<< "$RESTORE_ONLY"
  for item in "${only_list[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] || continue
    only_args+=("--only" "$item")
  done

  echo "[restore] Using archive: $from_path"
  restore_cmd=(/usr/local/bin/panel-restore.sh --from "$from_path" "${only_args[@]}")

  if [[ "$RESTORE_DRY_RUN" == "1" ]]; then
    restore_cmd+=(--dry-run)
  fi
  if [[ "$RESTORE_NO_RESTART" == "1" ]]; then
    restore_cmd+=(--no-restart)
  fi

  if [[ -n "$SUDO" ]]; then
    restore_cmd=("$SUDO" "${restore_cmd[@]}")
  fi

  "${restore_cmd[@]}"
}

interactive_menu() {
  local action=""

  while true; do
    cat <<MENU

Select action:
  1) Install/update + configure backup
  2) Configure Telegram/path only
  3) Enable scheduled backup timer
  4) Disable scheduled backup timer
  5) Restore backup
  6) Exit
MENU
    read -r -p "Choice [1-6]: " action

    case "$action" in
      1)
        prompt_install_settings
        install_files
        write_env
        if ask_yes_no "Enable backup timer now?" "y"; then
          enable_timer
        else
          echo "Timer was not enabled. You can enable later with:"
          echo "  sudo systemctl enable --now panel-backup.timer"
        fi
        break
        ;;
      2)
        prompt_install_settings
        write_env
        echo "Settings updated."
        break
        ;;
      3)
        enable_timer
        break
        ;;
      4)
        disable_timer
        break
        ;;
      5)
        MODE="restore"
        BACKUP_FILE="$(ask_value "BACKUP_FILE (path, optional if BACKUP_URL is set)" "$BACKUP_FILE")"
        BACKUP_URL="$(ask_value "BACKUP_URL (optional)" "$BACKUP_URL")"
        RESTORE_ONLY="$(ask_value "RESTORE_ONLY (all/db/redis/configs/...)" "$RESTORE_ONLY")"
        if ask_yes_no "Run restore in dry-run mode?" "n"; then
          RESTORE_DRY_RUN=1
        fi
        if ask_yes_no "Skip service restart after restore?" "n"; then
          RESTORE_NO_RESTART=1
        fi
        if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
          install_files
          write_env
          $SUDO systemctl daemon-reload
        fi
        run_restore
        break
        ;;
      6)
        echo "Cancelled."
        break
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done
}

if is_interactive; then
  interactive_menu
  exit 0
fi

case "$MODE" in
  install)
    install_files
    write_env
    enable_timer
    echo
    echo "Run backup now:"
    echo "  sudo /usr/local/bin/panel-backup.sh"
    echo "Run restore:"
    echo "  MODE=restore BACKUP_FILE='/var/backups/panel/<archive>.tar.gz' bash <(curl -fsSL ${RAW_BASE}/install.sh)"
    ;;
  restore)
    if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
      install_files
      write_env
      $SUDO systemctl daemon-reload
    fi
    run_restore
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown MODE=$MODE" >&2
    usage
    exit 1
    ;;
esac
