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
BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-}"
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"
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
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-0}"
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
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "sudo not found. Run as root or install sudo." >&2
    exit 1
  fi
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

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get"
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
    return 0
  fi
  if command -v yum >/dev/null 2>&1; then
    echo "yum"
    return 0
  fi
  if command -v apk >/dev/null 2>&1; then
    echo "apk"
    return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    echo "pacman"
    return 0
  fi
  echo ""
}

install_package() {
  local pkg="$1"
  local pm=""
  pm="$(detect_package_manager)"
  [[ -n "$pm" ]] || return 1

  case "$pm" in
    apt-get) $SUDO apt-get update -y && $SUDO apt-get install -y "$pkg" ;;
    dnf) $SUDO dnf install -y "$pkg" ;;
    yum) $SUDO yum install -y "$pkg" ;;
    apk) $SUDO apk add --no-cache "$pkg" ;;
    pacman) $SUDO pacman -Sy --noconfirm "$pkg" ;;
    *) return 1 ;;
  esac
}

command_package_name() {
  local cmd="$1"
  case "$cmd" in
    curl) echo "curl" ;;
    tar) echo "tar" ;;
    systemctl) echo "systemd" ;;
    install|mktemp|chmod|chown) echo "coreutils" ;;
    awk) echo "gawk" ;;
    sed) echo "sed" ;;
    grep) echo "grep" ;;
    *) echo "" ;;
  esac
}

preflight_install_environment() {
  local required=()
  local missing=()
  local cmd=""
  local pkg=""
  local failed=()

  required=(curl tar systemctl install mktemp chmod chown awk sed grep)
  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    paint "$CLR_OK" "[0/5] $(tr_text "Preflight: окружение готово" "Preflight: environment is ready")"
    return 0
  fi

  paint "$CLR_WARN" "[0/5] $(tr_text "Preflight: отсутствуют команды:" "Preflight: missing commands:") ${missing[*]}"
  if [[ "$AUTO_INSTALL_DEPS" != "1" ]]; then
    paint "$CLR_WARN" "$(tr_text "Установите их вручную или запустите с AUTO_INSTALL_DEPS=1." "Install them manually or run with AUTO_INSTALL_DEPS=1.")"
    return 1
  fi

  for cmd in "${missing[@]}"; do
    pkg="$(command_package_name "$cmd")"
    if [[ -z "$pkg" ]]; then
      failed+=("$cmd")
      continue
    fi
    paint "$CLR_ACCENT" "$(tr_text "Пробую установить пакет для" "Trying to install package for"): $cmd -> $pkg"
    install_package "$pkg" >/dev/null 2>&1 || true
    command -v "$cmd" >/dev/null 2>&1 || failed+=("$cmd")
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось подготовить зависимости:" "Failed to prepare dependencies:") ${failed[*]}"
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Зависимости установлены автоматически." "Dependencies were installed automatically.")"
  return 0
}

container_state() {
  local name="$1"
  local state=""
  state="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    echo "$(tr_text "не найден" "not found")"
  else
    case "$state" in
      running) echo "$(tr_text "работает" "running")" ;;
      exited) echo "$(tr_text "остановлен" "stopped")" ;;
      restarting) echo "$(tr_text "перезапуск" "restarting")" ;;
      created) echo "$(tr_text "создан" "created")" ;;
      paused) echo "$(tr_text "на паузе" "paused")" ;;
      dead) echo "$(tr_text "ошибка" "dead")" ;;
      *) echo "$state" ;;
    esac
  fi
}

container_image_ref() {
  local name="$1"
  docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null || true
}

container_version_label() {
  local name="$1"
  local tail=""
  local image_ref=""
  local image_id=""
  local version=""
  local version_from_tag=""
  local revision=""
  local env_version=""

  image_ref="$(container_image_ref "$name")"
  image_id="$(docker inspect -f '{{.Image}}' "$name" 2>/dev/null || true)"

  if [[ -n "$image_id" ]]; then
    version="$(docker image inspect -f '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$image_id" 2>/dev/null || true)"
    [[ "$version" == "<no value>" ]] && version=""
    if [[ -z "$version" ]]; then
      version="$(docker image inspect -f '{{ index .Config.Labels "org.label-schema.version" }}' "$image_id" 2>/dev/null || true)"
      [[ "$version" == "<no value>" ]] && version=""
    fi
    if [[ -z "$version" ]]; then
      revision="$(docker image inspect -f '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image_id" 2>/dev/null || true)"
      [[ "$revision" == "<no value>" ]] && revision=""
      if [[ -n "$revision" ]]; then
        if [[ ${#revision} -gt 12 ]]; then
          version="${revision:0:12}"
        else
          version="$revision"
        fi
      fi
    fi
  fi

  if [[ -z "$version" && -n "$image_ref" ]]; then
    tail="${image_ref##*/}"
    if [[ "$tail" == *:* ]]; then
      version_from_tag="${tail##*:}"
      if [[ "$version_from_tag" != "latest" ]]; then
        version="$version_from_tag"
      fi
    fi
  fi

  env_version="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null | awk -F= '
    $1=="__RW_METADATA_VERSION" {print $2; exit}
    $1=="REMNAWAVE_VERSION" {print $2; exit}
    $1=="SUBSCRIPTION_VERSION" {print $2; exit}
    $1=="APP_VERSION" {print $2; exit}
  ' || true)"

  # Если tag слишком грубый (например "2"), а env содержит более точную версию
  # (например "2.5.5"), показываем более информативное значение.
  if [[ -n "$env_version" ]]; then
    if [[ -z "$version" ]]; then
      version="$env_version"
    elif [[ "$version" =~ ^[0-9]+$ ]] && [[ "$env_version" =~ [.-] ]]; then
      version="$env_version"
    fi
  fi

  if [[ -n "$version" ]]; then
    echo "$version"
    return 0
  fi

  if [[ -n "$image_id" ]]; then
    image_id="${image_id#sha256:}"
    echo "sha-${image_id:0:12}"
    return 0
  fi

  if [[ -z "$image_ref" ]]; then
    echo "unknown"
    return 0
  fi

  tail="${image_ref##*/}"
  if [[ "$tail" == *:* ]]; then
    echo "${tail##*:}"
    return 0
  fi
  if [[ "$tail" == *@* ]]; then
    echo "${tail##*@}"
    return 0
  fi
  echo "$tail"
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
  local panel_version=""
  local sub_version=""

  clear
  timer_state="$($SUDO systemctl is-active panel-backup.timer 2>/dev/null || echo "inactive")"
  schedule_now="$(get_current_timer_calendar || true)"
  schedule_label="$(format_schedule_label "$schedule_now")"
  panel_state="$(container_state remnawave)"
  sub_state="$(container_state remnawave-subscription-page)"
  panel_version="$(container_version_label remnawave)"
  sub_version="$(container_version_label remnawave-subscription-page)"
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
  paint_labeled_value "$(tr_text "Версия панели:" "Panel version:")" "$panel_version" "$CLR_ACCENT"
  paint_labeled_value "$(tr_text "Подписка:" "Subscription:")" "$sub_state" "$sub_color"
  paint_labeled_value "$(tr_text "Версия подписки:" "Subscription version:")" "$sub_version" "$CLR_ACCENT"
  paint_labeled_value "RAM:" "$ram_label" "$ram_color"
  paint_labeled_value "$(tr_text "Диск:" "Disk:")" "$disk_label" "$disk_color"
  print_separator
  paint "$CLR_MUTED" "  $(tr_text "Таймер:" "Timer:") ${timer_state}   |   $(tr_text "Расписание:" "Schedule:") ${schedule_label}"
  paint "$CLR_MUTED" "  $(tr_text "Последний backup:" "Latest backup:") $(short_backup_label "$latest_label")"
  paint "$CLR_TITLE" "============================================================"
  paint "$CLR_MUTED" "$(tr_text "Выберите действие." "Select an action.")"
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

is_prev_command() {
  local raw="${1:-}"
  local cleaned=""
  cleaned="$(echo "$raw" | xargs 2>/dev/null || echo "$raw")"
  case "${cleaned,,}" in
    p|/p|prev|/prev|назад-шаг|шаг-назад) return 0 ;;
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
  local encrypt_view=""
  local password_view=""
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
  if [[ "${BACKUP_ENCRYPT:-0}" == "1" ]]; then
    encrypt_view="$(tr_text "включено" "enabled")"
  else
    encrypt_view="$(tr_text "выключено" "disabled")"
  fi
  if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
    password_view="$(mask_secret "$BACKUP_PASSWORD")"
  else
    password_view="$(tr_text "не задан" "not set")"
  fi
  paint "$CLR_MUTED" "  BACKUP_ENCRYPT: ${encrypt_view}"
  paint "$CLR_MUTED" "  BACKUP_PASSWORD: ${password_view}"
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

normalize_backup_encrypt_raw() {
  local value="$1"
  value="$(normalize_env_value_raw "$value")"
  case "${value,,}" in
    1|true|yes|on|y|да) printf '1' ;;
    0|false|no|off|n|нет|"") printf '0' ;;
    *) printf '0' ;;
  esac
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
  menu_option "1" "Русский [RU]"
  menu_option "2" "English [EN]"
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
  local old_backup_encrypt=""
  local old_backup_password=""
  local detected=""

  if [[ -f /etc/panel-backup.env ]]; then
    old_bot="$(grep -E '^TELEGRAM_BOT_TOKEN=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_admin="$(grep -E '^TELEGRAM_ADMIN_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_thread="$(grep -E '^TELEGRAM_THREAD_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_dir="$(grep -E '^REMNAWAVE_DIR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar="$(grep -E '^BACKUP_ON_CALENDAR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar="$(normalize_calendar_raw "$old_calendar")"
    old_backup_lang="$(grep -E '^BACKUP_LANG=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_backup_encrypt="$(grep -E '^BACKUP_ENCRYPT=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_backup_password="$(grep -E '^BACKUP_PASSWORD=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_bot="$(normalize_env_value_raw "$old_bot")"
    old_admin="$(normalize_env_value_raw "$old_admin")"
    old_thread="$(normalize_env_value_raw "$old_thread")"
    old_dir="$(normalize_env_value_raw "$old_dir")"
    old_backup_lang="$(normalize_env_value_raw "$old_backup_lang")"
    old_backup_encrypt="$(normalize_backup_encrypt_raw "$old_backup_encrypt")"
    old_backup_password="$(normalize_env_value_raw "$old_backup_password")"
  fi

  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$old_bot}"
  TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-$old_admin}"
  TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-$old_thread}"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$old_dir}"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-$old_calendar}"
  BACKUP_LANG="${BACKUP_LANG:-$old_backup_lang}"
  BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-$old_backup_encrypt}"
  BACKUP_PASSWORD="${BACKUP_PASSWORD:-$old_backup_password}"

  detected="$(detect_remnawave_dir || true)"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$detected}"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-$(get_current_timer_calendar || true)}"
  BACKUP_ON_CALENDAR="$(normalize_calendar_raw "$BACKUP_ON_CALENDAR")"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"
  BACKUP_LANG="${BACKUP_LANG:-$UI_LANG}"
  if [[ "$BACKUP_LANG" == "auto" || -z "$BACKUP_LANG" ]]; then
    BACKUP_LANG="ru"
  fi
  BACKUP_ENCRYPT="$(normalize_backup_encrypt_raw "${BACKUP_ENCRYPT:-0}")"
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

ask_value_nav() {
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
  if is_prev_command "$input"; then
    echo "__PBM_PREV__"
    return 0
  fi

  if [[ -n "$input" ]]; then
    echo "$input"
  else
    echo "$current"
  fi
}

ask_secret_value() {
  local prompt="$1"
  local current="${2:-}"
  local input=""
  local hint=""

  if [[ -n "$current" ]]; then
    hint="$(tr_text "задан" "set")"
  else
    hint="$(tr_text "не задан" "not set")"
  fi

  if [[ "$COLOR" == "1" ]]; then
    printf "%b%s [%s]%b\n" "$CLR_MUTED" "$prompt" "$hint" "$CLR_RESET" >&2
  else
    printf "%s [%s]\n" "$prompt" "$hint" >&2
  fi

  read -r -s -p "> " input
  printf "\n" >&2

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

ask_secret_value_nav() {
  local prompt="$1"
  local current="${2:-}"
  local input=""
  local hint=""

  if [[ -n "$current" ]]; then
    hint="$(tr_text "задан" "set")"
  else
    hint="$(tr_text "не задан" "not set")"
  fi

  if [[ "$COLOR" == "1" ]]; then
    printf "%b%s [%s]%b\n" "$CLR_MUTED" "$prompt" "$hint" "$CLR_RESET" >&2
  else
    printf "%s [%s]\n" "$prompt" "$hint" >&2
  fi

  read -r -s -p "> " input
  printf "\n" >&2

  if is_back_command "$input"; then
    echo "__PBM_BACK__"
    return 0
  fi
  if is_prev_command "$input"; then
    echo "__PBM_PREV__"
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


load_manager_module() {
  local module_path="$1"
  local local_path=""
  local fetched_path=""
  local manager_dir=""

  manager_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local_path="${manager_dir}/${module_path}"

  if [[ -f "$local_path" ]]; then
    # shellcheck source=/dev/null
    source "$local_path"
    return 0
  fi

  fetched_path="${TMP_DIR}/module__${module_path//\//__}"
  fetch "$module_path" "$fetched_path"
  # shellcheck source=/dev/null
  source "$fetched_path"
}

load_manager_modules() {
  load_manager_module "scripts/install/pipeline.sh"
  load_manager_module "scripts/runtime/operations.sh"
  load_manager_module "scripts/menu/interactive.sh"
}

load_manager_modules

if is_interactive; then
  interactive_menu
  exit 0
fi

case "$MODE" in
  install)
    run_install_pipeline
    echo
    echo "$(tr_text "Запустить backup сейчас:" "Run backup now:")"
    echo "  sudo /usr/local/bin/panel-backup.sh"
    echo "$(tr_text "Запустить restore:" "Run restore:")"
    echo "  MODE=restore BACKUP_FILE='/var/backups/panel/<archive>.tar.gz' bash <(curl -fsSL ${RAW_BASE}/install.sh)"
    ;;
  restore)
    if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
      preflight_install_environment
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
