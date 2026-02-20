#!/usr/bin/env bash
# Shared UI/input/text helpers for manager and interactive modules.

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
  local include_view=""
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
  include_view="${BACKUP_INCLUDE:-all}"
  paint "$CLR_MUTED" "  BACKUP_INCLUDE: ${include_view}"
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

  draw_subheader "Panel Backup Manager" "Выберите язык / Choose language"
  paint "$CLR_ACCENT" "  ____  _____ ____   ___  _        _    ____    _   "
  paint "$CLR_ACCENT" " | __ )| ____|  _ \\ / _ \\| |      / \\  / ___|  / \\  "
  paint "$CLR_ACCENT" " |  _ \\|  _| | | | | | | | |     / _ \\| |  _  / _ \\ "
  paint "$CLR_ACCENT" " | |_) | |___| |_| | |_| | |___ / ___ \\ |_| |/ ___ \\"
  paint "$CLR_ACCENT" " |____/|_____|____/ \\___/|_____/_/   \\_\\____/_/   \\_\\"
  paint "$CLR_MUTED" "  BEDOLAGA"
  print_separator
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
  local old_backup_include=""
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
    old_backup_include="$(grep -E '^BACKUP_INCLUDE=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_bot="$(normalize_env_value_raw "$old_bot")"
    old_admin="$(normalize_env_value_raw "$old_admin")"
    old_thread="$(normalize_env_value_raw "$old_thread")"
    old_dir="$(normalize_env_value_raw "$old_dir")"
    old_backup_lang="$(normalize_env_value_raw "$old_backup_lang")"
    old_backup_encrypt="$(normalize_backup_encrypt_raw "$old_backup_encrypt")"
    old_backup_password="$(normalize_env_value_raw "$old_backup_password")"
    old_backup_include="$(normalize_env_value_raw "$old_backup_include")"
  fi

  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$old_bot}"
  TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-$old_admin}"
  TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-$old_thread}"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$old_dir}"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-$old_calendar}"
  BACKUP_LANG="${BACKUP_LANG:-$old_backup_lang}"
  BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-$old_backup_encrypt}"
  BACKUP_PASSWORD="${BACKUP_PASSWORD:-$old_backup_password}"
  BACKUP_INCLUDE="${BACKUP_INCLUDE:-$old_backup_include}"

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
  BACKUP_INCLUDE="${BACKUP_INCLUDE:-all}"
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
  local normalized=""

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

    normalized="$(echo "$answer" | xargs 2>/dev/null || echo "$answer")"
    case "${normalized,,}" in
      y|yes|д|да) return 0 ;;
      n|no|н|нет) return 1 ;;
      *)
        if is_back_command "$normalized"; then
          return 2
        fi
        echo "$(tr_text "Введите y/n (или д/н)." "Please answer y or n.")"
        ;;
    esac
  done
}
