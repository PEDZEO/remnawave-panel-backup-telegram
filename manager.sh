#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main}"
MODE_SET="${MODE+x}"
MODE="${MODE:-install}"
INTERACTIVE="${INTERACTIVE:-auto}"
UI_LANG="${UI_LANG:-auto}"
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
COLOR=0
UI_ACTIVE=0
CLR_RESET=""
CLR_TITLE=""
CLR_ACCENT=""
CLR_MUTED=""
CLR_OK=""
CLR_WARN=""

cleanup() {
  if [[ "$UI_ACTIVE" == "1" ]]; then
    tput cnorm >/dev/null 2>&1 || true
    tput rmcup >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

usage() {
  cat <<USAGE
Unified installer/manager for panel backup system.

Modes:
  MODE=install   install/update scripts, env and timer (default)
  MODE=restore   restore backup (all or selected components)
  MODE=status    show install/timer/backup status

INTERACTIVE:
  INTERACTIVE=auto  show menu in terminal if MODE is not set explicitly (default)
  INTERACTIVE=1     force interactive menu
  INTERACTIVE=0     disable menu, run selected MODE directly

UI_LANG:
  UI_LANG=auto      prompt language in interactive menu (default)
  UI_LANG=ru        Russian
  UI_LANG=en|eu     English

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

setup_colors() {
  if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    COLOR=1
    CLR_RESET="$(printf '\033[0m')"
    CLR_TITLE="$(printf '\033[1;36m')"
    CLR_ACCENT="$(printf '\033[1;34m')"
    CLR_MUTED="$(printf '\033[0;37m')"
    CLR_OK="$(printf '\033[1;32m')"
    CLR_WARN="$(printf '\033[1;33m')"
  fi
}

paint() {
  local color="$1"
  shift
  if [[ "$COLOR" == "1" ]]; then
    printf "%b%s%b\n" "$color" "$*" "$CLR_RESET"
  else
    printf "%s\n" "$*"
  fi
}

draw_header() {
  local title="$1"
  local subtitle="${2:-}"
  clear
  paint "$CLR_TITLE" "============================================"
  paint "$CLR_TITLE" "  ${title}"
  if [[ -n "$subtitle" ]]; then
    paint "$CLR_MUTED" "  ${subtitle}"
  fi
  paint "$CLR_TITLE" "============================================"
}

is_back_command() {
  local raw="$1"
  local cleaned=""
  cleaned="$(echo "$raw" | xargs 2>/dev/null || echo "$raw")"
  case "${cleaned,,}" in
    b|/b|back|/back|назад) return 0 ;;
    *) return 1 ;;
  esac
}

show_back_hint() {
  paint "$CLR_MUTED" "$(tr_text "Подсказка: b = назад" "Hint: b = back")"
}

mask_secret() {
  local value="$1"
  local len=0
  len="${#value}"
  if [[ "$len" -le 8 ]]; then
    echo "********"
    return 0
  fi
  echo "${value:0:4}****${value: -4}"
}

show_settings_preview() {
  local token_view=""
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    token_view="$(mask_secret "$TELEGRAM_BOT_TOKEN")"
  else
    token_view="$(tr_text "не задан" "not set")"
  fi

  paint "$CLR_TITLE" "$(tr_text "Проверка настроек перед применением" "Settings preview before apply")"
  paint "$CLR_MUTED" "  TELEGRAM_BOT_TOKEN: ${token_view}"
  paint "$CLR_MUTED" "  TELEGRAM_ADMIN_ID: ${TELEGRAM_ADMIN_ID:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  TELEGRAM_THREAD_ID: ${TELEGRAM_THREAD_ID:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  REMNAWAVE_DIR: ${REMNAWAVE_DIR:-$(tr_text "не задан" "not set")}"
}

wait_for_enter() {
  local msg
  msg="$(tr_text "Нажмите Enter для продолжения..." "Press Enter to continue...")"
  paint "$CLR_MUTED" "$msg"
  read -r
}

enter_ui_mode() {
  [[ -t 0 && -t 1 ]] || return 0
  tput smcup >/dev/null 2>&1 || true
  tput civis >/dev/null 2>&1 || true
  UI_ACTIVE=1
  clear
}

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

normalize_ui_lang() {
  case "${UI_LANG,,}" in
    eu) UI_LANG="en" ;;
    ru|en|auto) ;;
    *) UI_LANG="auto" ;;
  esac
}

tr_text() {
  local ru="$1"
  local en="$2"
  if [[ "$UI_LANG" == "en" ]]; then
    echo "$en"
  else
    echo "$ru"
  fi
}

choose_ui_lang() {
  local choice=""

  normalize_ui_lang
  if [[ "$UI_LANG" == "ru" || "$UI_LANG" == "en" ]]; then
    return 0
  fi

  if [[ -n "${LANG:-}" && "${LANG,,}" == ru* ]]; then
    UI_LANG="ru"
  else
    UI_LANG="en"
  fi

  draw_header "Panel Backup Manager" "Выберите язык / Choose language"
  paint "$CLR_ACCENT" "  1) Русский"
  paint "$CLR_ACCENT" "  2) English (EU)"
  read -r -p "Choice [1-2]: " choice
  case "$choice" in
    1) UI_LANG="ru" ;;
    2) UI_LANG="en" ;;
  esac
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

show_remnawave_autodetect() {
  local candidate="$1"
  local env_file=""
  local compose_file=""
  local caddy_dir=""
  local subscription_dir=""

  paint "$CLR_TITLE" "$(tr_text "Автопоиск путей Remnawave" "Remnawave path autodetect")"

  if [[ -z "$candidate" ]]; then
    paint "$CLR_WARN" "$(tr_text "Путь не найден автоматически. Укажите вручную." "Path was not auto-detected. Please provide it manually.")"
    return 0
  fi

  env_file="${candidate}/.env"
  compose_file="${candidate}/docker-compose.yml"
  caddy_dir="${candidate}/caddy"
  subscription_dir="${candidate}/subscription"

  paint "$CLR_OK" "$(tr_text "Найден путь панели" "Detected panel path"): ${candidate}"
  if [[ -f "$env_file" ]]; then
    paint "$CLR_OK" "  - .env: $(tr_text "найден" "found")"
  else
    paint "$CLR_WARN" "  - .env: $(tr_text "не найден" "not found")"
  fi
  if [[ -f "$compose_file" ]]; then
    paint "$CLR_OK" "  - docker-compose.yml: $(tr_text "найден" "found")"
  else
    paint "$CLR_WARN" "  - docker-compose.yml: $(tr_text "не найден" "not found")"
  fi
  if [[ -d "$caddy_dir" ]]; then
    paint "$CLR_OK" "  - caddy/: $(tr_text "найден" "found")"
  else
    paint "$CLR_WARN" "  - caddy/: $(tr_text "не найден (будет пропущен в backup)" "not found (will be skipped in backup)")"
  fi
  if [[ -d "$subscription_dir" ]]; then
    paint "$CLR_OK" "  - subscription/: $(tr_text "найден" "found")"
  else
    paint "$CLR_WARN" "  - subscription/: $(tr_text "не найден (будет пропущен в backup)" "not found (will be skipped in backup)")"
  fi
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
    if [[ "$COLOR" == "1" ]]; then
      printf "%b%s%b\n" "$CLR_MUTED" "${prompt} [${current}]" "$CLR_RESET" >&2
    else
      printf "%s\n" "${prompt} [${current}]" >&2
    fi
  else
    if [[ "$COLOR" == "1" ]]; then
      printf "%b%s%b\n" "$CLR_MUTED" "${prompt}" "$CLR_RESET" >&2
    else
      printf "%s\n" "${prompt}" >&2
    fi
  fi
  read -r -p "> " input

  if is_back_command "$input"; then
    echo "__PBM_BACK__"
    return 0
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
      paint "$CLR_MUTED" "${prompt} [Y/n]"
      read -r -p "> " answer
      answer="${answer:-y}"
    else
      paint "$CLR_MUTED" "${prompt} [y/N]"
      read -r -p "> " answer
      answer="${answer:-n}"
    fi

    case "${answer,,}" in
      y|yes|д|да) return 0 ;;
      n|no|н|нет) return 1 ;;
      *)
        if is_back_command "$answer"; then
          return 2
        fi
        echo "$(tr_text "Введите y/n (или д/н)." "Please answer y or n.")"
        ;;
    esac
  done
}

prompt_install_settings() {
  local val=""
  local detected_path=""
  load_existing_env_defaults

  draw_header "$(tr_text "Настройка параметров бэкапа" "Configure backup settings")"
  show_back_hint
  paint "$CLR_MUTED" "$(tr_text "Сейчас вы настраиваете: Telegram-уведомления и путь к панели." "You are configuring: Telegram notifications and panel path.")"
  paint "$CLR_MUTED" "$(tr_text "Пустое значение оставляет текущее (если есть)." "Empty input keeps current value (if any).")"
  echo
  detected_path="$(detect_remnawave_dir || true)"
  show_remnawave_autodetect "$detected_path"
  if [[ -z "${REMNAWAVE_DIR:-}" && -n "$detected_path" ]]; then
    REMNAWAVE_DIR="$detected_path"
  fi
  echo

  val="$(ask_value "$(tr_text "[1/4] Токен Telegram-бота (пример: 123456:ABCDEF...)" "[1/4] Telegram bot token (example: 123456:ABCDEF...)")" "$TELEGRAM_BOT_TOKEN")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_BOT_TOKEN="$val"

  val="$(ask_value "$(tr_text "[2/4] ID чата/канала Telegram (пример: 123456789 или -1001234567890)" "[2/4] Telegram chat/channel ID (example: 123456789 or -1001234567890)")" "$TELEGRAM_ADMIN_ID")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_ADMIN_ID="$val"

  val="$(ask_value "$(tr_text "[3/4] ID темы (topic), если нужен (иначе оставьте пусто)" "[3/4] Topic/thread ID if needed (otherwise leave empty)")" "$TELEGRAM_THREAD_ID")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_THREAD_ID="$val"

  val="$(ask_value "$(tr_text "[4/4] Путь к папке панели Remnawave (пример: /opt/remnawave)" "[4/4] Path to Remnawave panel directory (example: /opt/remnawave)")" "$REMNAWAVE_DIR")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  REMNAWAVE_DIR="$val"

  return 0
}

install_files() {
  paint "$CLR_ACCENT" "[1/5] $(tr_text "Загрузка файлов" "Downloading files")"
  fetch "panel-backup.sh" "$TMP_DIR/panel-backup.sh"
  fetch "panel-restore.sh" "$TMP_DIR/panel-restore.sh"
  fetch "systemd/panel-backup.service" "$TMP_DIR/panel-backup.service"
  fetch "systemd/panel-backup.timer" "$TMP_DIR/panel-backup.timer"

  paint "$CLR_ACCENT" "[2/5] $(tr_text "Установка скриптов и systemd-юнитов" "Installing scripts and systemd units")"
  $SUDO install -m 755 "$TMP_DIR/panel-backup.sh" /usr/local/bin/panel-backup.sh
  $SUDO install -m 755 "$TMP_DIR/panel-restore.sh" /usr/local/bin/panel-restore.sh
  $SUDO install -m 644 "$TMP_DIR/panel-backup.service" /etc/systemd/system/panel-backup.service
  $SUDO install -m 644 "$TMP_DIR/panel-backup.timer" /etc/systemd/system/panel-backup.timer
}

write_env() {
  load_existing_env_defaults

  paint "$CLR_ACCENT" "[3/5] $(tr_text "Запись /etc/panel-backup.env" "Writing /etc/panel-backup.env")"
  $SUDO install -d -m 755 /etc
  $SUDO bash -c "cat > /etc/panel-backup.env <<ENV
${TELEGRAM_BOT_TOKEN:+TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}}
${TELEGRAM_ADMIN_ID:+TELEGRAM_ADMIN_ID=${TELEGRAM_ADMIN_ID}}
${TELEGRAM_THREAD_ID:+TELEGRAM_THREAD_ID=${TELEGRAM_THREAD_ID}}
${REMNAWAVE_DIR:+REMNAWAVE_DIR=${REMNAWAVE_DIR}}
ENV"
  $SUDO chmod 600 /etc/panel-backup.env
  $SUDO chown root:root /etc/panel-backup.env

  paint "$CLR_MUTED" "REMNAWAVE_DIR=${REMNAWAVE_DIR:-not-detected}"
}

enable_timer() {
  paint "$CLR_ACCENT" "[4/5] $(tr_text "Перезагрузка systemd и включение таймера" "Reloading systemd and enabling timer")"
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now panel-backup.timer

  paint "$CLR_OK" "[5/5] $(tr_text "Готово" "Done")"
  $SUDO systemctl status --no-pager panel-backup.timer | sed -n '1,12p'
}

disable_timer() {
  echo "$(tr_text "Отключаю таймер бэкапа" "Disabling backup timer")"
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

show_status() {
  local timer_show=""
  local service_show=""
  local latest_backup=""
  local latest_backup_time=""
  local latest_backup_size=""
  local timer_load=""
  local timer_unit_file=""
  local timer_active=""
  local timer_sub=""
  local timer_next=""
  local timer_last=""
  local service_active=""
  local service_sub=""
  local service_result=""
  local service_status=""
  local service_started=""
  local service_finished=""

  draw_header "$(tr_text "Статус panel backup" "Panel backup status")"

  if [[ -x /usr/local/bin/panel-backup.sh ]]; then
    paint "$CLR_OK" "$(tr_text "Скрипт backup: установлен (/usr/local/bin/panel-backup.sh)" "Backup script: installed (/usr/local/bin/panel-backup.sh)")"
  else
    paint "$CLR_WARN" "$(tr_text "Скрипт backup: не установлен" "Backup script: not installed")"
  fi

  if [[ -x /usr/local/bin/panel-restore.sh ]]; then
    paint "$CLR_OK" "$(tr_text "Скрипт restore: установлен (/usr/local/bin/panel-restore.sh)" "Restore script: installed (/usr/local/bin/panel-restore.sh)")"
  else
    paint "$CLR_WARN" "$(tr_text "Скрипт restore: не установлен" "Restore script: not installed")"
  fi

  if [[ -f /etc/panel-backup.env ]]; then
    paint "$CLR_OK" "$(tr_text "Файл конфигурации: найден (/etc/panel-backup.env)" "Config file: present (/etc/panel-backup.env)")"
  else
    paint "$CLR_WARN" "$(tr_text "Файл конфигурации: отсутствует (/etc/panel-backup.env)" "Config file: missing (/etc/panel-backup.env)")"
  fi

  timer_show="$($SUDO systemctl show panel-backup.timer \
    -p LoadState -p UnitFileState -p ActiveState -p SubState \
    -p NextElapseUSecRealtime -p LastTriggerUSecRealtime 2>/dev/null || true)"
  if [[ -n "$timer_show" ]]; then
    timer_load="$(echo "$timer_show" | awk -F= '/^LoadState=/{print $2}')"
    timer_unit_file="$(echo "$timer_show" | awk -F= '/^UnitFileState=/{print $2}')"
    timer_active="$(echo "$timer_show" | awk -F= '/^ActiveState=/{print $2}')"
    timer_sub="$(echo "$timer_show" | awk -F= '/^SubState=/{print $2}')"
    timer_next="$(echo "$timer_show" | awk -F= '/^NextElapseUSecRealtime=/{print $2}')"
    timer_last="$(echo "$timer_show" | awk -F= '/^LastTriggerUSecRealtime=/{print $2}')"
    echo "$(tr_text "Таймер: load=${timer_load:-unknown}, unit-file=${timer_unit_file:-unknown}, active=${timer_active:-unknown}/${timer_sub:-unknown}" "Timer: load=${timer_load:-unknown}, unit-file=${timer_unit_file:-unknown}, active=${timer_active:-unknown}/${timer_sub:-unknown}")"
    echo "$(tr_text "Следующий запуск таймера: ${timer_next:-n/a}" "Timer next run: ${timer_next:-n/a}")"
    echo "$(tr_text "Последний запуск таймера: ${timer_last:-n/a}" "Timer last run: ${timer_last:-n/a}")"
  else
    echo "$(tr_text "Таймер: недоступен" "Timer: not available")"
  fi

  service_show="$($SUDO systemctl show panel-backup.service \
    -p ActiveState -p SubState -p Result -p ExecMainStatus \
    -p ExecMainStartTimestamp -p ExecMainExitTimestamp 2>/dev/null || true)"
  if [[ -n "$service_show" ]]; then
    service_active="$(echo "$service_show" | awk -F= '/^ActiveState=/{print $2}')"
    service_sub="$(echo "$service_show" | awk -F= '/^SubState=/{print $2}')"
    service_result="$(echo "$service_show" | awk -F= '/^Result=/{print $2}')"
    service_status="$(echo "$service_show" | awk -F= '/^ExecMainStatus=/{print $2}')"
    service_started="$(echo "$service_show" | awk -F= '/^ExecMainStartTimestamp=/{print $2}')"
    service_finished="$(echo "$service_show" | awk -F= '/^ExecMainExitTimestamp=/{print $2}')"
    echo "$(tr_text "Сервис: active=${service_active:-unknown}/${service_sub:-unknown}, result=${service_result:-unknown}, exit-code=${service_status:-unknown}" "Service: active=${service_active:-unknown}/${service_sub:-unknown}, result=${service_result:-unknown}, exit-code=${service_status:-unknown}")"
    echo "$(tr_text "Последний старт сервиса: ${service_started:-n/a}" "Service last start: ${service_started:-n/a}")"
    echo "$(tr_text "Последнее завершение сервиса: ${service_finished:-n/a}" "Service last finish: ${service_finished:-n/a}")"
  else
    echo "$(tr_text "Сервис: недоступен" "Service: not available")"
  fi

  latest_backup="$(ls -1t /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
    latest_backup_time="$(date -u -r "$latest_backup" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || stat -c '%y' "$latest_backup" 2>/dev/null || echo n/a)"
    latest_backup_size="$(du -h "$latest_backup" 2>/dev/null | awk '{print $1}' || echo n/a)"
    echo "$(tr_text "Последний backup: $(basename "$latest_backup")" "Latest backup: $(basename "$latest_backup")")"
    echo "$(tr_text "Дата/время backup: ${latest_backup_time}" "Latest backup time: ${latest_backup_time}")"
    echo "$(tr_text "Размер backup: ${latest_backup_size}" "Latest backup size: ${latest_backup_size}")"
  else
    echo "$(tr_text "Последний backup: не найден в /var/backups/panel" "Latest backup: not found in /var/backups/panel")"
  fi

  load_existing_env_defaults
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_ADMIN_ID" ]]; then
    echo "$(tr_text "Telegram: настроен" "Telegram: configured")"
  else
    echo "$(tr_text "Telegram: настроен не полностью" "Telegram: not fully configured")"
  fi
  echo "$(tr_text "Путь Remnawave: ${REMNAWAVE_DIR:-not-detected}" "Remnawave dir: ${REMNAWAVE_DIR:-not-detected}")"
}

interactive_menu() {
  local action=""

  setup_colors
  enter_ui_mode
  choose_ui_lang

  while true; do
    draw_header "$(tr_text "Менеджер бэкапа панели" "Panel Backup Manager")"
    paint "$CLR_MUTED" "$(tr_text "Выберите действие:" "Select action:")"
    paint "$CLR_ACCENT" "  1) $(tr_text "Установить/обновить файлы + первичная настройка" "Install/update files + initial setup")"
    paint "$CLR_ACCENT" "  2) $(tr_text "Изменить только текущие настройки (без переустановки)" "Edit current settings only (no reinstall)")"
    paint "$CLR_ACCENT" "  3) $(tr_text "Включить таймер backup" "Enable scheduled backup timer")"
    paint "$CLR_ACCENT" "  4) $(tr_text "Выключить таймер backup" "Disable scheduled backup timer")"
    paint "$CLR_ACCENT" "  5) $(tr_text "Восстановить backup" "Restore backup")"
    paint "$CLR_ACCENT" "  6) $(tr_text "Показать статус" "Show status")"
    paint "$CLR_ACCENT" "  7) $(tr_text "Выход" "Exit")"
    read -r -p "$(tr_text "Выбор [1-7]: " "Choice [1-7]: ")" action

    case "$action" in
      1)
        draw_header "$(tr_text "Установка и настройка" "Install and configure")"
        paint "$CLR_MUTED" "$(tr_text "Используйте этот пункт при первом запуске или обновлении скриптов." "Use this on first run or when updating scripts.")"
        if ! prompt_install_settings; then
          continue
        fi
        show_settings_preview
        if ! ask_yes_no "$(tr_text "Применить эти настройки и продолжить установку?" "Apply these settings and continue installation?")" "y"; then
          [[ "$?" == "2" ]] && continue
          paint "$CLR_WARN" "$(tr_text "Отменено пользователем." "Cancelled by user.")"
          wait_for_enter
          continue
        fi
        install_files
        write_env
        if ask_yes_no "$(tr_text "Включить таймер backup сейчас?" "Enable backup timer now?")" "y"; then enable_timer; else
          case $? in
            1)
              paint "$CLR_WARN" "$(tr_text "Таймер не включен. Позже можно включить так:" "Timer was not enabled. You can enable later with:")"
              paint "$CLR_MUTED" "  sudo systemctl enable --now panel-backup.timer"
              ;;
            2) paint "$CLR_WARN" "$(tr_text "Пропущено." "Skipped.")" ;;
          esac
        fi
        wait_for_enter
        ;;
      2)
        draw_header "$(tr_text "Настройка Telegram и пути" "Configure Telegram and path")"
        paint "$CLR_MUTED" "$(tr_text "Скрипты не переустанавливаются: меняется только /etc/panel-backup.env." "Scripts are not reinstalled: only /etc/panel-backup.env will be changed.")"
        if ! prompt_install_settings; then
          continue
        fi
        show_settings_preview
        if ! ask_yes_no "$(tr_text "Сохранить эти настройки?" "Save these settings?")" "y"; then
          [[ "$?" == "2" ]] && continue
          paint "$CLR_WARN" "$(tr_text "Изменения не сохранены." "Changes were not saved.")"
          wait_for_enter
          continue
        fi
        write_env
        paint "$CLR_OK" "$(tr_text "Настройки обновлены." "Settings updated.")"
        wait_for_enter
        ;;
      3)
        draw_header "$(tr_text "Включение таймера backup" "Enable backup timer")"
        enable_timer
        wait_for_enter
        ;;
      4)
        draw_header "$(tr_text "Отключение таймера backup" "Disable backup timer")"
        disable_timer
        wait_for_enter
        ;;
      5)
        draw_header "$(tr_text "Восстановление backup" "Restore backup")"
        show_back_hint
        MODE="restore"
        BACKUP_FILE="$(ask_value "$(tr_text "BACKUP_FILE (путь, можно пусто если задан BACKUP_URL)" "BACKUP_FILE (path, optional if BACKUP_URL is set)")" "$BACKUP_FILE")"
        [[ "$BACKUP_FILE" == "__PBM_BACK__" ]] && continue
        BACKUP_URL="$(ask_value "$(tr_text "BACKUP_URL (опционально)" "BACKUP_URL (optional)")" "$BACKUP_URL")"
        [[ "$BACKUP_URL" == "__PBM_BACK__" ]] && continue
        RESTORE_ONLY="$(ask_value "$(tr_text "RESTORE_ONLY (all/db/redis/configs/...)" "RESTORE_ONLY (all/db/redis/configs/...)")" "$RESTORE_ONLY")"
        [[ "$RESTORE_ONLY" == "__PBM_BACK__" ]] && continue
        if ask_yes_no "$(tr_text "Запустить restore в dry-run режиме?" "Run restore in dry-run mode?")" "n"; then
          RESTORE_DRY_RUN=1
        else
          [[ "$?" == "2" ]] && continue
        fi
        if ask_yes_no "$(tr_text "Пропустить перезапуск сервисов после restore?" "Skip service restart after restore?")" "n"; then
          RESTORE_NO_RESTART=1
        else
          [[ "$?" == "2" ]] && continue
        fi
        if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
          install_files
          write_env
          $SUDO systemctl daemon-reload
        fi
        run_restore
        wait_for_enter
        ;;
      6)
        show_status
        wait_for_enter
        ;;
      7)
        echo "$(tr_text "Выход." "Cancelled.")"
        break
        ;;
      *)
        echo "$(tr_text "Некорректный выбор." "Invalid choice.")"
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
    echo "$(tr_text "Запустить backup сейчас:" "Run backup now:")"
    echo "  sudo /usr/local/bin/panel-backup.sh"
    echo "$(tr_text "Запустить restore:" "Run restore:")"
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
  status)
    show_status
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
