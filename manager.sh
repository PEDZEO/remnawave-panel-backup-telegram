#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main}"
RAW_BASE_RESOLVED="$RAW_BASE"
REPO_API="${REPO_API:-https://api.github.com/repos/PEDZEO/remnawave-panel-backup-telegram/commits/main}"
MODE_SET="${MODE+x}"
MODE="${MODE:-install}"
INTERACTIVE="${INTERACTIVE:-auto}"
UI_LANG="${UI_LANG:-auto}"
BACKUP_LANG="${BACKUP_LANG:-}"
BACKUP_FILE="${BACKUP_FILE:-}"
BACKUP_URL="${BACKUP_URL:-}"
RESTORE_ONLY="${RESTORE_ONLY:-all}"
RESTORE_DRY_RUN="${RESTORE_DRY_RUN:-0}"
RESTORE_NO_RESTART="${RESTORE_NO_RESTART:-0}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-}"
TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-}"
REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-}"
TMP_DIR="$(mktemp -d /tmp/panel-backup-install.XXXXXX)"
SUDO=""
COLOR=0
UI_ACTIVE=0
APP_VERSION="1.1.1"
CLR_RESET=""
CLR_TITLE=""
CLR_ACCENT=""
CLR_MUTED=""
CLR_OK=""
CLR_WARN=""
CLR_DANGER=""

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
  MODE=backup    run backup now
  MODE=status    show install/timer/backup status

INTERACTIVE:
  INTERACTIVE=auto  show menu in terminal if MODE is not set explicitly (default)
  INTERACTIVE=1     force interactive menu
  INTERACTIVE=0     disable menu, run selected MODE directly

UI_LANG:
  UI_LANG=auto      prompt language in interactive menu (default)
  UI_LANG=ru        Russian
  UI_LANG=en|eu     English

Schedule:
  BACKUP_ON_CALENDAR='*-*-* 03:40:00 UTC'  systemd OnCalendar expression

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
    CLR_DANGER="$(printf '\033[1;31m')"
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

container_state() {
  local name="$1"
  local state=""
  state="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    echo "$(tr_text "не найден" "not found")"
  else
    echo "$state"
  fi
}

memory_usage_label() {
  local total_kb=0
  local avail_kb=0
  local used_kb=0
  local used_mb=0
  local total_mb=0
  local percent=0

  total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$total_kb" =~ ^[0-9]+$ && "$avail_kb" =~ ^[0-9]+$ && "$total_kb" -gt 0 ]]; then
    used_kb=$((total_kb - avail_kb))
    used_mb=$((used_kb / 1024))
    total_mb=$((total_kb / 1024))
    percent=$((used_kb * 100 / total_kb))
    echo "${used_mb}MB / ${total_mb}MB (${percent}%)"
    return 0
  fi
  echo "n/a"
}

memory_usage_percent() {
  local total_kb=0
  local avail_kb=0
  local used_kb=0
  total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$total_kb" =~ ^[0-9]+$ && "$avail_kb" =~ ^[0-9]+$ && "$total_kb" -gt 0 ]]; then
    used_kb=$((total_kb - avail_kb))
    echo $((used_kb * 100 / total_kb))
    return 0
  fi
  echo "-1"
}

disk_usage_label() {
  local line=""
  local used=""
  local total=""
  local percent=""
  line="$(df -h / 2>/dev/null | awk 'NR==2 {print $3" "$2" "$5}' || true)"
  if [[ -z "$line" ]]; then
    echo "n/a"
    return 0
  fi
  used="$(echo "$line" | awk '{print $1}')"
  total="$(echo "$line" | awk '{print $2}')"
  percent="$(echo "$line" | awk '{print $3}')"
  echo "$(tr_text "${used} из ${total} (${percent})" "${used} of ${total} (${percent})")"
}

disk_usage_percent() {
  local raw=""
  raw="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}' || true)"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo "-1"
  fi
}

metric_color_ram() {
  local percent="$1"
  if [[ "$percent" =~ ^[0-9]+$ ]]; then
    if (( percent >= 90 )); then
      echo "$CLR_DANGER"
      return 0
    fi
    if (( percent >= 75 )); then
      echo "$CLR_WARN"
      return 0
    fi
    echo "$CLR_OK"
    return 0
  fi
  echo "$CLR_MUTED"
}

metric_color_disk() {
  local percent="$1"
  if [[ "$percent" =~ ^[0-9]+$ ]]; then
    if (( percent >= 85 )); then
      echo "$CLR_DANGER"
      return 0
    fi
    if (( percent >= 70 )); then
      echo "$CLR_WARN"
      return 0
    fi
    echo "$CLR_OK"
    return 0
  fi
  echo "$CLR_MUTED"
}

state_color() {
  local state="$1"
  case "$state" in
    running|active) echo "$CLR_OK" ;;
    restarting|created|paused) echo "$CLR_WARN" ;;
    *) echo "$CLR_DANGER" ;;
  esac
}

paint_labeled_value() {
  local label="$1"
  local value="$2"
  local value_color="$3"
  if [[ "$COLOR" == "1" ]]; then
    printf "%b  %s%b %b%s%b\n" "$CLR_MUTED" "$label" "$CLR_RESET" "$value_color" "$value" "$CLR_RESET"
  else
    printf "  %s %s\n" "$label" "$value"
  fi
}

draw_header() {
  local title="$1"
  local subtitle="${2:-}"
  local timer_state=""
  local schedule_now=""
  local schedule_label=""
  local latest_backup=""
  local latest_label=""
  local panel_state=""
  local sub_state=""
  local ram_label=""
  local disk_label=""
  local ram_percent=""
  local disk_percent=""
  local ram_color=""
  local disk_color=""
  local panel_color=""
  local sub_color=""

  clear
  timer_state="$($SUDO systemctl is-active panel-backup.timer 2>/dev/null || echo "inactive")"
  schedule_now="$(get_current_timer_calendar || true)"
  schedule_label="$(format_schedule_label "$schedule_now")"
  panel_state="$(container_state remnawave)"
  sub_state="$(container_state remnawave-subscription-page)"
  ram_label="$(memory_usage_label)"
  disk_label="$(disk_usage_label)"
  ram_percent="$(memory_usage_percent)"
  disk_percent="$(disk_usage_percent)"
  ram_color="$(metric_color_ram "$ram_percent")"
  disk_color="$(metric_color_disk "$disk_percent")"
  panel_color="$(state_color "$panel_state")"
  sub_color="$(state_color "$sub_state")"
  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_backup" ]]; then
    latest_label="$(basename "$latest_backup")"
  else
    latest_label="$(tr_text "нет" "none")"
  fi

  paint "$CLR_TITLE" "============================================================"
  paint "$CLR_ACCENT" "  ${title}"
  paint "$CLR_OK" "  Version: ${APP_VERSION}"
  if [[ -n "$subtitle" ]]; then
    paint "$CLR_MUTED" "  ${subtitle}"
  fi
  print_separator
  paint_labeled_value "$(tr_text "Панель (remnawave):" "Panel (remnawave):")" "$panel_state" "$panel_color"
  paint_labeled_value "$(tr_text "Подписка:" "Subscription:")" "$sub_state" "$sub_color"
  paint_labeled_value "RAM:" "$ram_label" "$ram_color"
  paint_labeled_value "$(tr_text "Диск:" "Disk:")" "$disk_label" "$disk_color"
  print_separator
  paint "$CLR_MUTED" "  $(tr_text "Таймер:" "Timer:") ${timer_state}   |   $(tr_text "Расписание:" "Schedule:") ${schedule_label}"
  paint "$CLR_MUTED" "  $(tr_text "Последний backup:" "Latest backup:") $(short_backup_label "$latest_label")"
  paint "$CLR_TITLE" "============================================================"
  paint "$CLR_MUTED" "$(tr_text "Чё делать будем, босс?" "What are we doing, boss?")"
  echo
}

print_separator() {
  paint "$CLR_MUTED" "------------------------------------------------------------"
}

menu_option() {
  local key="$1"
  local label="$2"
  local color="${3:-$CLR_ACCENT}"
  paint "$color" "  [${key}] ${label}"
}

is_back_command() {
  local raw="$1"
  local cleaned=""
  cleaned="$(echo "$raw" | xargs 2>/dev/null || echo "$raw")"
  case "${cleaned,,}" in
    b|/b|и|/и|back|/back|назад) return 0 ;;
    *) return 1 ;;
  esac
}

show_back_hint() {
  :
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
  paint "$CLR_MUTED" "  BACKUP_ON_CALENDAR: ${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"
  paint "$CLR_MUTED" "  BACKUP_LANG: ${BACKUP_LANG:-$(tr_text "не задан" "not set")}"
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
  local url="${RAW_BASE_RESOLVED}/${src}"
  local sep="?"

  if [[ "$url" == *\?* ]]; then
    sep="&"
  fi

  curl -fsSL "${url}${sep}v=$(date +%s)" -o "$dst"
}

resolve_raw_base() {
  local sha=""
  local candidate=""

  sha="$(curl -fsSL "$REPO_API" 2>/dev/null | sed -n 's/.*"sha":[[:space:]]*"\([a-f0-9]\{40\}\)".*/\1/p' | head -n1 || true)"
  if [[ -z "$sha" ]]; then
    RAW_BASE_RESOLVED="$RAW_BASE"
    return 0
  fi

  candidate="https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/${sha}"
  RAW_BASE_RESOLVED="$candidate"
}

resolve_raw_base

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

normalize_calendar_raw() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

normalize_env_value_raw() {
  local value="$1"
  local i=0

  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  for i in 1 2 3 4; do
    value="${value//\\\"/\"}"
    value="${value//\\\\/\\}"
    if [[ ${#value} -ge 2 ]]; then
      if [[ "${value:0:1}" == "\"" && "${value: -1}" == "\"" ]]; then
        value="${value:1:${#value}-2}"
      elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
        value="${value:1:${#value}-2}"
      fi
    fi
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  done

  printf '%s' "$value"
}

format_schedule_label() {
  local raw="$1"
  local cal=""
  cal="$(normalize_calendar_raw "$raw")"

  case "$cal" in
    "*-*-* 03:40:00 UTC") echo "$(tr_text "Ежедневно 03:40 UTC" "Daily 03:40 UTC")" ;;
    "*-*-* 00,12:00:00 UTC") echo "$(tr_text "Каждые 12 часов" "Every 12 hours")" ;;
    "*-*-* 00,06,12,18:00:00 UTC") echo "$(tr_text "Каждые 6 часов" "Every 6 hours")" ;;
    "hourly") echo "$(tr_text "Каждый час" "Every hour")" ;;
    "") echo "unknown" ;;
    *) echo "$(tr_text "Кастом: " "Custom: ")${cal}" ;;
  esac
}

short_backup_label() {
  local full_name="$1"
  if [[ ${#full_name} -le 48 ]]; then
    echo "$full_name"
    return 0
  fi
  echo "${full_name:0:22}...${full_name: -22}"
}

choose_ui_lang() {
  local choice=""

  normalize_ui_lang
  if [[ "$UI_LANG" == "ru" || "$UI_LANG" == "en" ]]; then
    BACKUP_LANG="$UI_LANG"
    return 0
  fi

  if [[ -n "${LANG:-}" && "${LANG,,}" == ru* ]]; then
    UI_LANG="ru"
  else
    UI_LANG="en"
  fi

  draw_header "Panel Backup Manager" "Выберите язык / Choose language"
  show_back_hint
  menu_option "1" "Русский 🇷🇺"
  menu_option "2" "English (EU) 🇬🇧"
  print_separator
  read -r -p "Choice [1-2]: " choice
  if is_back_command "$choice"; then
    return 0
  fi
  case "$choice" in
    1) UI_LANG="ru" ;;
    2) UI_LANG="en" ;;
  esac
  BACKUP_LANG="$UI_LANG"
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

get_current_timer_calendar() {
  local path=""
  local value=""

  for path in /etc/systemd/system/panel-backup.timer /usr/lib/systemd/system/panel-backup.timer /lib/systemd/system/panel-backup.timer; do
    [[ -f "$path" ]] || continue
    value="$(grep -E '^OnCalendar=' "$path" | head -n1 | cut -d= -f2- || true)"
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  done

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
  local old_calendar=""
  local old_backup_lang=""
  local detected=""

  if [[ -f /etc/panel-backup.env ]]; then
    old_bot="$(grep -E '^TELEGRAM_BOT_TOKEN=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_admin="$(grep -E '^TELEGRAM_ADMIN_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_thread="$(grep -E '^TELEGRAM_THREAD_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_dir="$(grep -E '^REMNAWAVE_DIR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar="$(grep -E '^BACKUP_ON_CALENDAR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar="$(normalize_calendar_raw "$old_calendar")"
    old_backup_lang="$(grep -E '^BACKUP_LANG=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_bot="$(normalize_env_value_raw "$old_bot")"
    old_admin="$(normalize_env_value_raw "$old_admin")"
    old_thread="$(normalize_env_value_raw "$old_thread")"
    old_dir="$(normalize_env_value_raw "$old_dir")"
    old_backup_lang="$(normalize_env_value_raw "$old_backup_lang")"
  fi

  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$old_bot}"
  TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-$old_admin}"
  TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-$old_thread}"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$old_dir}"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-$old_calendar}"
  BACKUP_LANG="${BACKUP_LANG:-$old_backup_lang}"

  detected="$(detect_remnawave_dir || true)"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$detected}"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-$(get_current_timer_calendar || true)}"
  BACKUP_ON_CALENDAR="$(normalize_calendar_raw "$BACKUP_ON_CALENDAR")"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"
  BACKUP_LANG="${BACKUP_LANG:-$UI_LANG}"
  if [[ "$BACKUP_LANG" == "auto" || -z "$BACKUP_LANG" ]]; then
    BACKUP_LANG="ru"
  fi
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

  val="$(ask_value "$(tr_text "[1/5] Токен Telegram-бота (пример: 123456:ABCDEF...)" "[1/5] Telegram bot token (example: 123456:ABCDEF...)")" "$TELEGRAM_BOT_TOKEN")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_BOT_TOKEN="$val"

  val="$(ask_value "$(tr_text "[2/5] ID чата/канала Telegram (пример: 123456789 или -1001234567890)" "[2/5] Telegram chat/channel ID (example: 123456789 or -1001234567890)")" "$TELEGRAM_ADMIN_ID")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_ADMIN_ID="$val"

  val="$(ask_value "$(tr_text "[3/5] ID темы (topic), если нужен (иначе оставьте пусто)" "[3/5] Topic/thread ID if needed (otherwise leave empty)")" "$TELEGRAM_THREAD_ID")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_THREAD_ID="$val"

  val="$(ask_value "$(tr_text "[4/5] Путь к папке панели Remnawave (пример: /opt/remnawave)" "[4/5] Path to Remnawave panel directory (example: /opt/remnawave)")" "$REMNAWAVE_DIR")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  REMNAWAVE_DIR="$val"

  val="$(ask_value "$(tr_text "[5/5] Язык описания backup в Telegram (ru/en)" "[5/5] Backup description language in Telegram (ru/en)")" "$BACKUP_LANG")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  case "${val,,}" in
    en|eu) BACKUP_LANG="en" ;;
    ru|"") BACKUP_LANG="ru" ;;
    *) BACKUP_LANG="$val" ;;
  esac

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
  local escaped_bot=""
  local escaped_admin=""
  local escaped_thread=""
  local escaped_dir=""
  local escaped_calendar=""
  local escaped_backup_lang=""
  load_existing_env_defaults

  escaped_bot="$(escape_env_value "${TELEGRAM_BOT_TOKEN:-}")"
  escaped_admin="$(escape_env_value "${TELEGRAM_ADMIN_ID:-}")"
  escaped_thread="$(escape_env_value "${TELEGRAM_THREAD_ID:-}")"
  escaped_dir="$(escape_env_value "${REMNAWAVE_DIR:-}")"
  escaped_calendar="$(escape_env_value "${BACKUP_ON_CALENDAR:-}")"
  escaped_backup_lang="$(escape_env_value "${BACKUP_LANG:-}")"

  paint "$CLR_ACCENT" "[3/5] $(tr_text "Запись /etc/panel-backup.env" "Writing /etc/panel-backup.env")"
  $SUDO install -d -m 755 /etc
  $SUDO bash -c "cat > /etc/panel-backup.env <<ENV
${TELEGRAM_BOT_TOKEN:+TELEGRAM_BOT_TOKEN=\"${escaped_bot}\"}
${TELEGRAM_ADMIN_ID:+TELEGRAM_ADMIN_ID=\"${escaped_admin}\"}
${TELEGRAM_THREAD_ID:+TELEGRAM_THREAD_ID=\"${escaped_thread}\"}
${REMNAWAVE_DIR:+REMNAWAVE_DIR=\"${escaped_dir}\"}
${BACKUP_ON_CALENDAR:+BACKUP_ON_CALENDAR=\"${escaped_calendar}\"}
${BACKUP_LANG:+BACKUP_LANG=\"${escaped_backup_lang}\"}
ENV"
  $SUDO chmod 600 /etc/panel-backup.env
  $SUDO chown root:root /etc/panel-backup.env

  paint "$CLR_MUTED" "REMNAWAVE_DIR=${REMNAWAVE_DIR:-not-detected}"
  paint "$CLR_MUTED" "BACKUP_ON_CALENDAR=${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"
  paint "$CLR_MUTED" "BACKUP_LANG=${BACKUP_LANG:-ru}"
}

escape_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\$}"
  value="${value//\`/\\\`}"
  printf '%s' "$value"
}

write_timer_unit() {
  local calendar="${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"

  $SUDO bash -c "cat > /etc/systemd/system/panel-backup.timer <<TIMER
[Unit]
Description=Run panel backup by configured schedule

[Timer]
OnCalendar=${calendar}
Persistent=true
Unit=panel-backup.service

[Install]
WantedBy=timers.target
TIMER"
  $SUDO chmod 644 /etc/systemd/system/panel-backup.timer
  $SUDO chown root:root /etc/systemd/system/panel-backup.timer
}

configure_schedule_menu() {
  local choice=""
  local custom=""
  local current="${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"

  while true; do
    draw_header "$(tr_text "Периодичность backup" "Backup schedule")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Текущее расписание:" "Current schedule:") $(format_schedule_label "$current")"
    menu_option "1" "$(tr_text "🕒 Ежедневно 03:40 UTC (по умолчанию)" "🕒 Daily at 03:40 UTC (default)")"
    menu_option "2" "$(tr_text "🕛 Каждые 12 часов" "🕛 Every 12 hours")"
    menu_option "3" "$(tr_text "⌚ Каждые 6 часов" "⌚ Every 6 hours")"
    menu_option "4" "$(tr_text "⏰ Каждый час" "⏰ Every hour")"
    menu_option "5" "$(tr_text "✍️ Свой OnCalendar" "✍️ Custom OnCalendar")"
    menu_option "6" "$(tr_text "🔙 Назад" "🔙 Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      return 1
    fi

    case "$choice" in
      1) BACKUP_ON_CALENDAR="*-*-* 03:40:00 UTC"; return 0 ;;
      2) BACKUP_ON_CALENDAR="*-*-* 00,12:00:00 UTC"; return 0 ;;
      3) BACKUP_ON_CALENDAR="*-*-* 00,06,12,18:00:00 UTC"; return 0 ;;
      4) BACKUP_ON_CALENDAR="hourly"; return 0 ;;
      5)
        custom="$(ask_value "$(tr_text "Введите OnCalendar (пример: *-*-* 02:00:00 UTC)" "Enter OnCalendar (example: *-*-* 02:00:00 UTC)")" "$current")"
        [[ "$custom" == "__PBM_BACK__" ]] && continue
        if [[ -n "$custom" ]]; then
          BACKUP_ON_CALENDAR="$custom"
          return 0
        fi
        ;;
      6) return 1 ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")" ;;
    esac
  done
}

enable_timer() {
  write_timer_unit
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
    from_path="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
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

sync_runtime_scripts() {
  paint "$CLR_ACCENT" "$(tr_text "Обновляю runtime-скрипты backup/restore..." "Updating backup/restore runtime scripts...")"
  fetch "panel-backup.sh" "$TMP_DIR/panel-backup.sh"
  fetch "panel-restore.sh" "$TMP_DIR/panel-restore.sh"
  $SUDO install -m 755 "$TMP_DIR/panel-backup.sh" /usr/local/bin/panel-backup.sh
  $SUDO install -m 755 "$TMP_DIR/panel-restore.sh" /usr/local/bin/panel-restore.sh
}

normalize_env_file_format() {
  local env_path="/etc/panel-backup.env"
  local fix_pattern='^BACKUP_ON_CALENDAR=[^"].* [^"].*$'

  if [[ ! -f "$env_path" ]]; then
    return 0
  fi

  if $SUDO grep -qE "$fix_pattern" "$env_path" 2>/dev/null; then
    $SUDO sed -i -E 's/^BACKUP_ON_CALENDAR=(.*)$/BACKUP_ON_CALENDAR="\1"/' "$env_path"
    paint "$CLR_WARN" "$(tr_text "Исправлен формат BACKUP_ON_CALENDAR в /etc/panel-backup.env" "Fixed BACKUP_ON_CALENDAR format in /etc/panel-backup.env")"
  fi
}

run_backup_now() {
  local backup_cmd

  sync_runtime_scripts
  normalize_env_file_format

  if [[ ! -x /usr/local/bin/panel-backup.sh ]]; then
    install_files
    write_env
    $SUDO systemctl daemon-reload
  fi

  backup_cmd=(/usr/local/bin/panel-backup.sh)
  if [[ -n "$SUDO" ]]; then
    backup_cmd=("$SUDO" "${backup_cmd[@]}")
  fi

  "${backup_cmd[@]}"
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
  local schedule_now=""

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
  schedule_now="$(get_current_timer_calendar || true)"
  echo "$(tr_text "Периодичность backup: $(format_schedule_label "$schedule_now")" "Backup schedule: $(format_schedule_label "$schedule_now")")"

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

  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
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

menu_flow_install_and_setup() {
  draw_header "$(tr_text "Установка и настройка" "Install and configure")"
  paint "$CLR_MUTED" "$(tr_text "Используйте этот пункт при первом запуске или обновлении скриптов." "Use this on first run or when updating scripts.")"
  if ! prompt_install_settings; then
    return 0
  fi
  show_settings_preview
  if ! ask_yes_no "$(tr_text "Применить эти настройки и продолжить установку?" "Apply these settings and continue installation?")" "y"; then
    [[ "$?" == "2" ]] && return 0
    paint "$CLR_WARN" "$(tr_text "Отменено пользователем." "Cancelled by user.")"
    wait_for_enter
    return 0
  fi
  install_files
  write_env
  if ask_yes_no "$(tr_text "Включить таймер backup сейчас?" "Enable backup timer now?")" "y"; then
    enable_timer
  else
    case $? in
      1)
        paint "$CLR_WARN" "$(tr_text "Таймер не включен. Позже можно включить так:" "Timer was not enabled. You can enable later with:")"
        paint "$CLR_MUTED" "  sudo systemctl enable --now panel-backup.timer"
        ;;
      2) paint "$CLR_WARN" "$(tr_text "Пропущено." "Skipped.")" ;;
    esac
  fi
  wait_for_enter
}

menu_flow_edit_settings_only() {
  draw_header "$(tr_text "Настройка Telegram и пути" "Configure Telegram and path")"
  paint "$CLR_MUTED" "$(tr_text "Скрипты не переустанавливаются: меняется только /etc/panel-backup.env." "Scripts are not reinstalled: only /etc/panel-backup.env will be changed.")"
  if ! prompt_install_settings; then
    return 0
  fi
  show_settings_preview
  if ! ask_yes_no "$(tr_text "Сохранить эти настройки?" "Save these settings?")" "y"; then
    [[ "$?" == "2" ]] && return 0
    paint "$CLR_WARN" "$(tr_text "Изменения не сохранены." "Changes were not saved.")"
    wait_for_enter
    return 0
  fi
  write_env
  paint "$CLR_OK" "$(tr_text "Настройки обновлены." "Settings updated.")"
  wait_for_enter
}

menu_section_setup() {
  local choice=""
  while true; do
    draw_header "$(tr_text "Раздел: Установка и настройка" "Section: Setup and configuration")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Здесь первичная установка и изменение конфигурации." "Use this section for initial install and config changes.")"
    menu_option "1" "$(tr_text "🛠 Установить/обновить файлы + первичная настройка" "🛠 Install/update files + initial setup")"
    menu_option "2" "$(tr_text "⚙️ Изменить только текущие настройки" "⚙️ Edit current settings only")"
    menu_option "3" "$(tr_text "🔙 Назад" "🔙 Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_flow_install_and_setup ;;
      2) menu_flow_edit_settings_only ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

list_local_backups() {
  ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null || true
}

render_backup_list() {
  local -a files=("$@")
  local idx=1
  local path=""
  local size=""
  local mtime=""

  if [[ ${#files[@]} -eq 0 ]]; then
    paint "$CLR_WARN" "$(tr_text "В /var/backups/panel нет архивов backup." "No backup archives found in /var/backups/panel.")"
    return 0
  fi

  paint "$CLR_TITLE" "$(tr_text "Доступные backup-файлы" "Available backup files")"
  for path in "${files[@]}"; do
    [[ -f "$path" ]] || continue
    size="$(du -h "$path" 2>/dev/null | awk '{print $1}' || echo "n/a")"
    mtime="$(date -u -r "$path" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || stat -c '%y' "$path" 2>/dev/null || echo "n/a")"
    paint "$CLR_MUTED" "  ${idx}) $(basename "$path") | ${size} | ${mtime}"
    idx=$((idx + 1))
  done
}

select_restore_source() {
  local choice=""
  local selected=""
  local index=""
  local path=""
  local url=""
  local -a files=()

  while true; do
    draw_header "$(tr_text "Источник backup для восстановления" "Restore source selection")"
    mapfile -t files < <(list_local_backups)
    render_backup_list "${files[@]}"
    print_separator
    menu_option "1" "$(tr_text "Выбрать файл из списка (по номеру)" "Select file from list (by number)")"
    menu_option "2" "$(tr_text "Ввести путь к архиву вручную" "Enter archive path manually")"
    menu_option "3" "$(tr_text "Указать URL архива" "Provide archive URL")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      return 1
    fi

    case "$choice" in
      1)
        if [[ ${#files[@]} -eq 0 ]]; then
          paint "$CLR_WARN" "$(tr_text "Список пуст. Выберите путь вручную или URL." "List is empty. Use manual path or URL.")"
          wait_for_enter
          continue
        fi
        selected="$(ask_value "$(tr_text "Введите номер backup из списка" "Enter backup number from list")" "")"
        [[ "$selected" == "__PBM_BACK__" ]] && continue
        if [[ "$selected" =~ ^[0-9]+$ ]] && (( selected >= 1 && selected <= ${#files[@]} )); then
          index=$((selected - 1))
          BACKUP_FILE="${files[$index]}"
          BACKUP_URL=""
          return 0
        fi
        paint "$CLR_WARN" "$(tr_text "Некорректный номер файла." "Invalid file number.")"
        wait_for_enter
        ;;
      2)
        path="$(ask_value "$(tr_text "Путь к backup-архиву (.tar.gz)" "Path to backup archive (.tar.gz)")" "$BACKUP_FILE")"
        [[ "$path" == "__PBM_BACK__" ]] && continue
        if [[ -f "$path" ]]; then
          BACKUP_FILE="$path"
          BACKUP_URL=""
          return 0
        fi
        paint "$CLR_WARN" "$(tr_text "Файл не найден." "File not found.")"
        wait_for_enter
        ;;
      3)
        url="$(ask_value "$(tr_text "URL backup-архива" "Backup archive URL")" "$BACKUP_URL")"
        [[ "$url" == "__PBM_BACK__" ]] && continue
        if [[ -n "$url" ]]; then
          BACKUP_URL="$url"
          BACKUP_FILE=""
          return 0
        fi
        paint "$CLR_WARN" "$(tr_text "URL не может быть пустым." "URL cannot be empty.")"
        wait_for_enter
        ;;
      4) return 1 ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

select_restore_components() {
  local choice=""
  local custom=""
  while true; do
    draw_header "$(tr_text "Выбор данных для восстановления" "Restore components selection")"
    paint "$CLR_MUTED" "$(tr_text "Выберите, что именно восстанавливать из backup." "Choose which data to restore from backup.")"
    menu_option "1" "$(tr_text "Все (db + redis + configs)" "All (db + redis + configs)")"
    menu_option "2" "$(tr_text "Только PostgreSQL (db)" "PostgreSQL only (db)")"
    menu_option "3" "$(tr_text "Только Redis (redis)" "Redis only (redis)")"
    menu_option "4" "$(tr_text "Только конфиги (configs)" "Configs only (configs)")"
    menu_option "5" "$(tr_text "Свой список компонентов" "Custom components list")"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      return 1
    fi
    case "$choice" in
      1) RESTORE_ONLY="all"; return 0 ;;
      2) RESTORE_ONLY="db"; return 0 ;;
      3) RESTORE_ONLY="redis"; return 0 ;;
      4) RESTORE_ONLY="configs"; return 0 ;;
      5)
        custom="$(ask_value "$(tr_text "Компоненты через запятую (all,db,redis,configs,env,compose,caddy,subscription)" "Comma-separated components (all,db,redis,configs,env,compose,caddy,subscription)")" "$RESTORE_ONLY")"
        [[ "$custom" == "__PBM_BACK__" ]] && continue
        if [[ -n "$custom" ]]; then
          RESTORE_ONLY="$custom"
          return 0
        fi
        ;;
      6) return 1 ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

show_restore_summary() {
  paint "$CLR_TITLE" "$(tr_text "Параметры восстановления" "Restore parameters")"
  paint "$CLR_MUTED" "  BACKUP_FILE: ${BACKUP_FILE:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  BACKUP_URL: ${BACKUP_URL:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  RESTORE_ONLY: ${RESTORE_ONLY:-all}"
  paint "$CLR_MUTED" "  RESTORE_DRY_RUN: ${RESTORE_DRY_RUN:-0}"
  paint "$CLR_MUTED" "  RESTORE_NO_RESTART: ${RESTORE_NO_RESTART:-0}"
}

menu_section_operations() {
  local choice=""
  while true; do
    draw_header "$(tr_text "Раздел: Ручное управление backup" "Section: Manual backup control")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Здесь можно вручную: 1) создать backup, 2) восстановить backup." "Manually: 1) create backup, 2) restore backup.")"
    menu_option "1" "$(tr_text "📦 Создать backup сейчас" "📦 Create backup now")"
    menu_option "2" "$(tr_text "♻️ Восстановить backup" "♻️ Restore backup")"
    menu_option "3" "$(tr_text "🔙 Назад" "🔙 Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        draw_header "$(tr_text "Создание backup" "Create backup")"
        run_backup_now
        wait_for_enter
        ;;
      2)
        draw_header "$(tr_text "Восстановление backup" "Restore backup")"
        MODE="restore"
        RESTORE_DRY_RUN=0
        RESTORE_NO_RESTART=0
        RESTORE_ONLY="all"
        if ! select_restore_source; then
          continue
        fi
        if ! select_restore_components; then
          continue
        fi
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
        draw_header "$(tr_text "Подтверждение восстановления" "Restore confirmation")"
        show_restore_summary
        if ! ask_yes_no "$(tr_text "Запустить восстановление с этими параметрами?" "Run restore with these parameters?")" "y"; then
          [[ "$?" == "2" ]] && continue
          paint "$CLR_WARN" "$(tr_text "Восстановление отменено." "Restore cancelled.")"
          wait_for_enter
          continue
        fi
        if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
          install_files
          write_env
          $SUDO systemctl daemon-reload
        fi
        run_restore
        wait_for_enter
        ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_timer() {
  local choice=""
  local schedule_now=""
  while true; do
    draw_header "$(tr_text "Раздел: Таймер и периодичность" "Section: Timer and schedule")"
    show_back_hint
    schedule_now="$(get_current_timer_calendar || true)"
    paint "$CLR_MUTED" "$(tr_text "Текущее расписание:" "Current schedule:") $(format_schedule_label "$schedule_now")"
    menu_option "1" "$(tr_text "🟢 Включить таймер backup" "🟢 Enable backup timer")"
    menu_option "2" "$(tr_text "🟠 Выключить таймер backup" "🟠 Disable backup timer")"
    menu_option "3" "$(tr_text "⏱ Настроить периодичность backup" "⏱ Configure backup schedule")"
    menu_option "4" "$(tr_text "🔙 Назад" "🔙 Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        draw_header "$(tr_text "Включение таймера backup" "Enable backup timer")"
        enable_timer
        wait_for_enter
        ;;
      2)
        draw_header "$(tr_text "Отключение таймера backup" "Disable backup timer")"
        disable_timer
        wait_for_enter
        ;;
      3)
        if configure_schedule_menu; then
          write_env
          write_timer_unit
          $SUDO systemctl daemon-reload
          paint "$CLR_OK" "$(tr_text "Периодичность backup сохранена." "Backup schedule saved.")"
          if $SUDO systemctl is-enabled --quiet panel-backup.timer 2>/dev/null; then
            $SUDO systemctl restart panel-backup.timer || true
          fi
        fi
        wait_for_enter
        ;;
      4) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_status() {
  local choice=""
  while true; do
    draw_header "$(tr_text "Раздел: Статус и диагностика" "Section: Status and diagnostics")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Проверка состояния скриптов, таймера и последних backup." "Check scripts, timer and latest backup details.")"
    menu_option "1" "$(tr_text "📊 Показать полный статус" "📊 Show full status")"
    menu_option "2" "$(tr_text "🔙 Назад" "🔙 Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-2]: " "Choice [1-2]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) show_status; wait_for_enter ;;
      2) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

interactive_menu() {
  local action=""

  setup_colors
  enter_ui_mode
  choose_ui_lang

  while true; do
    draw_header "$(tr_text "Менеджер бэкапа панели" "Panel Backup Manager")"
    show_back_hint
    menu_option "1" "$(tr_text "🛠 Установка и настройка" "🛠 Setup and configuration")"
    menu_option "2" "$(tr_text "📦 Создать или восстановить backup (вручную)" "📦 Create or restore backup (manual)")"
    menu_option "3" "$(tr_text "⏱ Таймер и периодичность" "⏱ Timer and schedule")"
    menu_option "4" "$(tr_text "📊 Статус и диагностика" "📊 Status and diagnostics")"
    menu_option "q" "$(tr_text "🚪 Выход" "🚪 Exit")" "$CLR_DANGER"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4/q]: " "Choice [1-4/q]: ")" action
    if is_back_command "$action"; then
      echo "$(tr_text "Выход." "Cancelled.")"
      break
    fi

    case "$action" in
      1) menu_section_setup ;;
      2) menu_section_operations ;;
      3) menu_section_timer ;;
      4) menu_section_status ;;
      q|Q)
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
  backup)
    run_backup_now
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
