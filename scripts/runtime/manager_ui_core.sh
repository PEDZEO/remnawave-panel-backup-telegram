#!/usr/bin/env bash
# Shared UI/input/text helpers for manager and interactive modules.

print_separator() {
  local char="${1:--}"
  local length="${2:-60}"

  MENU_SEPARATOR_PRINTED=1
  paint "$CLR_MUTED" "$(printf "%*s" "$length" "" | tr ' ' "$char")"
}

menu_option_color() {
  printf '%s' "${CLR_WHITE:-$CLR_MUTED}"
}

menu_is_back_label() {
  local label="${1:-}"
  [[ "$label" == "Назад" || "$label" == "Back" ]]
}

menu_group() {
  local title="$1"
  local color="${2:-$CLR_MUTED}"

  if [[ "${MENU_OPTIONS_STARTED:-0}" == "1" ]]; then
    echo
  fi
  MENU_OPTIONS_STARTED=0
  MENU_SEPARATOR_PRINTED=1

  if [[ "$COLOR" == "1" ]]; then
    printf "  %b╭─%b %b%s%b\n" "$CLR_TITLE" "$CLR_RESET" "$color" "$title" "$CLR_RESET"
  else
    printf "  ╭─ %s\n" "$title"
  fi
}

menu_option() {
  local key="$1"
  local label="$2"
  local color="${3:-}"
  local display_key="$key"

  [[ -n "$color" ]] || color="$(menu_option_color "$key" "$label")"
  if menu_is_back_label "$label"; then
    MENU_HAS_BACK_OPTION=1
    MENU_BACK_ORIGINAL_KEY="$key"
    display_key="b"
    [[ -n "${3:-}" ]] || color="$CLR_MUTED"
  fi

  if [[ "${MENU_OPTIONS_STARTED:-0}" != "1" ]]; then
    if [[ "${MENU_SEPARATOR_PRINTED:-0}" != "1" ]]; then
      print_separator
    fi
    MENU_OPTIONS_STARTED=1
  fi

  if [[ "$COLOR" == "1" ]]; then
    printf "   %b[%s] %b%b\n" "$color" "$display_key" "$label" "$CLR_RESET"
  else
    printf "   [%s] %s\n" "$display_key" "$label"
  fi
}

menu_hint() {
  local text="$1"

  if [[ "$COLOR" == "1" ]]; then
    printf "          %b↳ %b%b\n" "$CLR_MUTED" "$text" "$CLR_RESET"
  else
    printf "          ↳ %s\n" "$text"
  fi
}

ui_set_breadcrumb() {
  UI_BREADCRUMB="$1"
}

ui_clear_breadcrumb() {
  UI_BREADCRUMB=""
}

ui_record_action() {
  PBM_LAST_ACTION_TITLE="$1"
  PBM_LAST_ACTION_STATUS="$2"
}

ui_last_action_label() {
  if [[ -n "${PBM_LAST_ACTION_TITLE:-}" && -n "${PBM_LAST_ACTION_STATUS:-}" ]]; then
    printf '%s: %s' "$PBM_LAST_ACTION_STATUS" "$PBM_LAST_ACTION_TITLE"
  fi
  return 0
}

ui_env_value() {
  local key="$1"
  local value=""

  if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    eval "value=\"\${${key}:-}\""
  fi
  if [[ -z "$value" && -f /etc/panel-backup.env ]]; then
    value="$(grep -E "^${key}=" /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' || true)"
  fi
  printf '%s' "$value"
}

ui_context_summary() {
  local token=""
  local chat=""
  local panel_timer_state=""
  local panel_timer_enabled=""
  local bedolaga_timer_state=""
  local bedolaga_timer_enabled=""
  local latest_backup=""
  local -a parts=()

  token="$(ui_env_value TELEGRAM_BOT_TOKEN)"
  chat="$(ui_env_value TELEGRAM_ADMIN_ID)"
  if [[ -n "$token" && -n "$chat" ]]; then
    parts+=("Telegram: $(tr_text "настроен" "configured")")
  fi

  panel_timer_state="$(systemctl_active_state panel-backup-panel.timer)"
  panel_timer_enabled="$(systemctl_enabled_state panel-backup-panel.timer)"
  if [[ "$panel_timer_state" == "active" || "$panel_timer_enabled" == "enabled" ]]; then
    parts+=("$(tr_text "Панель timer" "Panel timer"): ${panel_timer_state}/${panel_timer_enabled}")
  fi

  bedolaga_timer_state="$(systemctl_active_state panel-backup-bedolaga.timer)"
  bedolaga_timer_enabled="$(systemctl_enabled_state panel-backup-bedolaga.timer)"
  if [[ "$bedolaga_timer_state" == "active" || "$bedolaga_timer_enabled" == "enabled" ]]; then
    parts+=("Bedolaga timer: ${bedolaga_timer_state}/${bedolaga_timer_enabled}")
  fi

  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_backup" ]]; then
    parts+=("Backup: $(short_backup_label "$(basename "$latest_backup")")")
  fi

  local joined=""
  local part=""
  for part in "${parts[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=" · "
    fi
    joined+="$part"
  done
  printf '%s' "$joined"
}

ui_draw_screen_context() {
  local summary=""
  local printed=0

  if [[ -n "${UI_BREADCRUMB:-}" ]]; then
    paint "$CLR_MUTED" "  ${UI_BREADCRUMB}"
    printed=1
  fi

  summary="$(ui_context_summary || true)"
  if [[ -n "$summary" ]]; then
    paint "$CLR_MUTED" "  ${summary}"
    printed=1
  fi

  if (( printed == 1 )); then
    echo
  fi
}

menu_card_option() {
  local key="$1"
  local title="$2"
  local description="$3"
  local color="${4:-$CLR_ACCENT}"

  if [[ "${MENU_OPTIONS_STARTED:-0}" != "1" ]]; then
    if [[ "${MENU_SEPARATOR_PRINTED:-0}" != "1" ]]; then
      print_separator
    fi
    MENU_OPTIONS_STARTED=1
  fi

  if [[ "$COLOR" == "1" ]]; then
    printf "  %b[%s]%b %b%s%b\n" "$color" "$key" "$CLR_RESET" "${CLR_WHITE:-$color}" "$title" "$CLR_RESET"
    printf "      %b%s%b\n" "$CLR_MUTED" "$description" "$CLR_RESET"
  else
    printf "  [%s] %s\n" "$key" "$title"
    printf "      %s\n" "$description"
  fi
}

menu_quick_hint() {
  local text="$1"

  print_separator
  paint "$CLR_MUTED" "  ${text}"
}

show_action_preview() {
  local action_title="$1"
  shift || true

  paint "$CLR_TITLE" "$(tr_text "План действия" "Action plan")"
  paint "$CLR_MUTED" "  ${action_title}"
  while [[ "$#" -gt 0 ]]; do
    paint "$CLR_MUTED" "  - $1"
    shift
  done
}

confirm_action_preview() {
  local action_title="$1"
  shift || true

  draw_subheader "$action_title" "$(tr_text "Подтверждение запуска" "Launch confirmation")"
  show_action_preview "$action_title" "$@"
  print_separator
  ask_yes_no "$(tr_text "Запустить это действие сейчас?" "Run this action now?")" "y"
}

show_operation_failure_menu() {
  local action_title="$1"
  local rc="${2:-1}"
  local choice=""

  MENU_OPTIONS_STARTED=0
  MENU_SEPARATOR_PRINTED=0
  MENU_HAS_BACK_OPTION=0
  MENU_BACK_ORIGINAL_KEY=""
  print_separator
  paint "$CLR_DANGER" "$(tr_text "Операция завершилась с ошибкой:" "Operation failed:") ${action_title} (rc=${rc})"
  paint "$CLR_MUTED" "$(tr_text "Лог выше оставлен на экране. Можно повторить действие или вернуться в меню." "The log above is left on screen. You can retry or return to the menu.")"
  menu_group "$(tr_text "Что сделать дальше" "Next action")" "$CLR_WARN"
  menu_option "1" "$(tr_text "Повторить действие" "Retry action")" "$CLR_WARN"
  menu_option "2" "$(tr_text "Вернуться в меню" "Return to menu")" "$CLR_MUTED"
  print_separator
  read_menu_choice choice "$(tr_text "Выбор [1-2]: " "Choice [1-2]: ")"
  if is_back_command "$choice"; then
    return 1
  fi
  case "$choice" in
    1) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_line() {
  local text="$1"

  if [[ "$COLOR" == "1" ]]; then
    printf "%b%s%b" "$CLR_MUTED" "$text" "$CLR_RESET" >&2
  else
    printf "%s" "$text" >&2
  fi
}

read_prompt_raw() {
  local __var="$1"
  local prompt="$2"
  local display_default="${3:-}"
  local secret="${4:-0}"
  local prompt_full=""
  local rc=0
  local value=""

  if [[ -n "$display_default" ]]; then
    prompt_full="${prompt} [${display_default}]: "
  else
    prompt_full="${prompt}: "
  fi

  if [[ -t 0 ]]; then
    while read -r -t 0; do read -r; done 2>/dev/null || true
  fi

  if [[ "$secret" == "1" ]]; then
    read -r -s -p "$prompt_full" "$__var" || rc=$?
    printf "\n" >&2
  elif [[ -t 0 ]]; then
    read -e -r -p "$prompt_full" "$__var" || rc=$?
  else
    read -r -p "$prompt_full" "$__var" || rc=$?
  fi

  value="${!__var-}"
  value="${value//$'\r'/}"
  value="${value//$'\n'/}"
  printf -v "$__var" '%s' "$value"
  return "$rc"
}

read_menu_choice() {
  local __var="$1"
  local prompt="$2"
  local back_key="${MENU_BACK_ORIGINAL_KEY:-}"
  local back_hint=""
  local upper=0
  local new_range=""

  if [[ "${MENU_HAS_BACK_OPTION:-0}" == "1" && "$back_key" =~ ^[0-9]+$ ]]; then
    back_hint="$(tr_text "b назад" "b back")"
    if [[ "$prompt" =~ ^(.*)\[1-([0-9]+)\](.*)$ && "${BASH_REMATCH[2]}" == "$back_key" ]]; then
      upper=$((back_key - 1))
      if (( upper > 1 )); then
        new_range="1-${upper}, ${back_hint}"
      elif (( upper == 1 )); then
        new_range="1, ${back_hint}"
      else
        new_range="${back_hint}"
      fi
      prompt="${BASH_REMATCH[1]}[${new_range}]${BASH_REMATCH[3]}"
    elif [[ "$prompt" != *"b"* && "$prompt" != *"back"* && "$prompt" != *"назад"* ]]; then
      prompt="${prompt% }"
      prompt="${prompt} (${back_hint})"
    fi
  fi

  prompt="${prompt% }"
  prompt="${prompt%:}"
  read_prompt_raw "$__var" "$prompt"
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

normalize_answer_token() {
  local raw="${1:-}"

  printf '%s' "$raw" \
    | tr -d '\000-\037\177' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

show_back_hint() {
  menu_hint "$(tr_text "Навигация: b/back = назад, номер = открыть." "Navigation: b/back = back, number = open.")"
}

systemctl_value_or_default() {
  local fallback="$1"
  shift
  local value=""

  value="$($SUDO systemctl "$@" 2>/dev/null || true)"
  value="$(printf '%s\n' "$value" | sed -n '1p')"
  printf '%s' "${value:-$fallback}"
}

systemctl_active_state() {
  systemctl_value_or_default "inactive" is-active "$1"
}

systemctl_enabled_state() {
  systemctl_value_or_default "disabled" is-enabled "$1"
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
  paint "$CLR_MUTED" "  TELEGRAM_THREAD_ID_PANEL: ${TELEGRAM_THREAD_ID_PANEL:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  TELEGRAM_THREAD_ID_BEDOLAGA: ${TELEGRAM_THREAD_ID_BEDOLAGA:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  REMNAWAVE_DIR: ${REMNAWAVE_DIR:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  BACKUP_ON_CALENDAR_PANEL: ${BACKUP_ON_CALENDAR_PANEL:-${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}}"
  paint "$CLR_MUTED" "  BACKUP_ON_CALENDAR_BEDOLAGA: ${BACKUP_ON_CALENDAR_BEDOLAGA:-${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}}"
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

is_safe_project_path() {
  local value="$1"
  local trimmed=""

  [[ -z "$value" ]] && return 0
  case "$value" in
    *[[:space:]]*|*"'"*|*'"'*|*'`'*|*'$'*|*\\*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*) return 1 ;;
    *'/../'*|*'/..'|*'/./'*|*'/.') return 1 ;;
  esac
  [[ "$value" == /* ]] || return 1

  trimmed="${value%/}"
  [[ -n "$trimmed" ]] || trimmed="/"
  case "$trimmed" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      return 1
      ;;
  esac

  return 0
}

validate_project_path_or_warn() {
  local label="$1"
  local value="$2"

  if is_safe_project_path "$value"; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Некорректный путь" "Invalid path"): ${label}. $(tr_text "Укажите абсолютный путь к папке проекта без пробелов/служебных символов, не системный корень." "Use an absolute project directory path without spaces/shell characters, not a system root.")"
  return 1
}

is_valid_domain_name() {
  local value="$1"

  [[ ${#value} -le 253 ]] || return 1
  [[ "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

validate_domain_or_warn() {
  local label="$1"
  local value="$2"

  if is_valid_domain_name "$value"; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Некорректный домен" "Invalid domain"): ${label}. $(tr_text "Введите домен без http://, https://, пробелов и пути." "Enter a domain without http://, https://, spaces or path.")"
  return 1
}

is_valid_tcp_port() {
  local value="$1"

  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 && value <= 65535 ))
}

validate_tcp_port_or_warn() {
  local label="$1"
  local value="$2"

  if is_valid_tcp_port "$value"; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Некорректный порт" "Invalid port"): ${label}. $(tr_text "Введите число от 1 до 65535." "Enter a number from 1 to 65535.")"
  return 1
}

is_safe_ssh_token() {
  local value="$1"

  [[ -n "$value" ]] || return 1
  [[ "$value" != -* ]] || return 1
  case "$value" in
    *[[:space:]]*|*'/'*|*\\*|*"'"*|*'"'*|*'`'*|*'$'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*)
      return 1
      ;;
  esac

  return 0
}

validate_ssh_token_or_warn() {
  local label="$1"
  local value="$2"

  if is_safe_ssh_token "$value"; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Некорректное SSH-значение" "Invalid SSH value"): ${label}. $(tr_text "Не используйте пробелы, /, shell-символы или значение с начальным '-'." "Do not use spaces, /, shell characters, or a value starting with '-'.")"
  return 1
}

is_safe_oncalendar_value() {
  local value="$1"

  [[ -n "$value" ]] || return 1
  case "$value" in
    *$'\n'*|*$'\r'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'`'*|*'$'*)
      return 1
      ;;
  esac

  return 0
}

validate_oncalendar_or_warn() {
  local value="$1"

  if is_safe_oncalendar_value "$value"; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Некорректное расписание OnCalendar." "Invalid OnCalendar value.")"
  return 1
}

is_allowed_component_for_scope() {
  local scope="$1"
  local component="$2"

  case "$scope" in
    panel)
      case "$component" in
        all|db|redis|configs|env|compose|caddy|subscription) return 0 ;;
      esac
      ;;
    bedolaga)
      case "$component" in
        bedolaga|bedolaga-official|bedolaga-fork|bedolaga-db|bedolaga-redis|bedolaga-official-db|bedolaga-fork-db|bedolaga-official-redis|bedolaga-fork-redis|bedolaga-bot|bedolaga-cabinet|bedolaga-configs) return 0 ;;
      esac
      ;;
    *)
      case "$component" in
        all|db|redis|configs|env|compose|caddy|subscription|bedolaga|bedolaga-official|bedolaga-fork|bedolaga-db|bedolaga-redis|bedolaga-official-db|bedolaga-fork-db|bedolaga-official-redis|bedolaga-fork-redis|bedolaga-bot|bedolaga-cabinet|bedolaga-configs) return 0 ;;
      esac
      ;;
  esac

  return 1
}

normalize_component_list() {
  local raw="$1"
  printf '%s' "${raw,,}" | tr -d '[:space:]'
}

validate_component_list_or_warn() {
  local scope="$1"
  local raw="$2"
  local normalized=""
  local item=""
  local -a component_items=()

  normalized="$(normalize_component_list "$raw")"
  [[ -n "$normalized" ]] || {
    paint "$CLR_WARN" "$(tr_text "Список компонентов не может быть пустым." "Component list cannot be empty.")"
    return 1
  }

  IFS=',' read -r -a component_items <<< "$normalized"
  for item in "${component_items[@]}"; do
    if [[ -z "$item" ]] || ! is_allowed_component_for_scope "$scope" "$item"; then
      paint "$CLR_WARN" "$(tr_text "Неизвестный компонент" "Unknown component"): ${item:-empty}"
      return 1
    fi
  done

  return 0
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
  print_separator
  show_back_hint
  menu_option "1" "Русский [RU]"
  menu_option "2" "English [EN]"
  print_separator
  read_menu_choice choice "$(tr_text "Выбор [1-2]" "Choice [1-2]")"
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
  local compose_file=""
  local name=""

  is_remnawave_panel_dir() {
    local d="$1"
    compose_file="$d/docker-compose.yml"
    [[ -f "$d/.env" && -f "$compose_file" ]] || return 1

    if grep -Eq 'container_name:[[:space:]]*remnawave_bot(_db|_redis)?([[:space:]]|$)' "$compose_file"; then
      return 1
    fi

    if grep -Eq 'container_name:[[:space:]]*remnawave-(db|redis|caddy|subscription-page)([[:space:]]|$)' "$compose_file"; then
      return 0
    fi

    [[ -d "$d/caddy" || -d "$d/subscription" ]] || return 1
    return 0
  }

  detect_compose_workdir_by_container_names() {
    local n=""
    local wd=""
    for n in "$@"; do
      [[ -n "$n" ]] || continue
      wd="$(docker inspect "$n" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
      [[ -n "$wd" ]] || continue
      echo "$wd"
      return 0
    done
    return 1
  }

  for guessed in \
    "${REMNAWAVE_DIR}" \
    "/opt/remnawave" \
    "/srv/remnawave" \
    "/root/remnawave" \
    "/home/remnawave"; do
    [[ -n "$guessed" ]] || continue
    if is_remnawave_panel_dir "$guessed"; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(detect_compose_workdir_by_container_names \
    remnawave remnawave-db remnawave-redis remnawave-caddy remnawave-subscription-page \
    remnawave_db remnawave_redis remnawave_caddy remnawave_subscription_page || true)"
  if [[ -n "$guessed" ]] && is_remnawave_panel_dir "$guessed"; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /opt /srv /root /home -maxdepth 4 -type f -name '.env' 2>/dev/null | while read -r f; do d="$(dirname "$f")"; is_remnawave_panel_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  return 1
}

detect_bedolaga_bot_dir() {
  local guessed=""
  local compose_file=""

  detect_compose_workdir_by_container_names() {
    local name=""
    local wd=""
    for name in "$@"; do
      [[ -n "$name" ]] || continue
      wd="$(docker inspect "$name" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
      [[ -n "$wd" ]] || continue
      echo "$wd"
      return 0
    done
    return 1
  }
  for guessed in "${BEDOLAGA_BOT_DIR:-}" "/root/remnawave-bedolaga-telegram-bot" "/opt/remnawave-bedolaga-telegram-bot"; do
    [[ -n "$guessed" ]] || continue
    if [[ -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(detect_compose_workdir_by_container_names remnawave_bot remnawave-bot remnawave_bot_db remnawave_bot_redis || true)"
  if [[ -n "$guessed" && -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 6 -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do [[ -f "$d/.env" && -f "$d/docker-compose.yml" ]] || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 7 -type f -name 'docker-compose.yml' 2>/dev/null | while read -r compose_file; do d="$(dirname "$compose_file")"; grep -Eq 'container_name:[[:space:]]*(remnawave_bot|remnawave-bot|remnawave_bot_db|remnawave_bot_redis)([[:space:]]|$)' "$compose_file" || continue; [[ -f "$d/.env" ]] || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  if [[ "${PBM_DEEP_AUTODETECT:-0}" == "1" ]]; then
    guessed="$(find / -xdev -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do [[ -f "$d/.env" && -f "$d/docker-compose.yml" ]] || continue; echo "$d"; break; done)"
    [[ -n "$guessed" ]] && echo "$guessed"
  fi
}

detect_bedolaga_cabinet_dir() {
  is_bedolaga_cabinet_dir() {
    local d="$1"
    [[ -f "$d/.env" ]] || return 1
    [[ -f "$d/docker-compose.yml" || -f "$d/package.json" ]] || return 1
    return 0
  }

  local guessed=""
  local compose_file=""

  detect_compose_workdir_by_container_names() {
    local name=""
    local wd=""
    for name in "$@"; do
      [[ -n "$name" ]] || continue
      wd="$(docker inspect "$name" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
      [[ -n "$wd" ]] || continue
      echo "$wd"
      return 0
    done
    return 1
  }
  for guessed in "${BEDOLAGA_CABINET_DIR:-}" "/root/bedolaga-cabinet" "/root/cabinet-frontend" "/opt/bedolaga-cabinet" "/opt/bedolaga-cabine" "/opt/cabinet-frontend"; do
    [[ -n "$guessed" ]] || continue
    if is_bedolaga_cabinet_dir "$guessed"; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(detect_compose_workdir_by_container_names cabinet_frontend cabinet-frontend bedolaga-cabinet || true)"
  if [[ -n "$guessed" ]] && is_bedolaga_cabinet_dir "$guessed"; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 7 -type f -name 'docker-compose.yml' 2>/dev/null | while read -r compose_file; do d="$(dirname "$compose_file")"; grep -Eq 'container_name:[[:space:]]*(cabinet_frontend|cabinet-frontend|bedolaga-cabinet)([[:space:]]|$)' "$compose_file" || continue; is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 6 -type d \( -name 'cabinet-frontend' -o -name 'bedolaga-cabinet' -o -name 'bedolaga-cabine' \) 2>/dev/null | while read -r d; do is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  if [[ "${PBM_DEEP_AUTODETECT:-0}" == "1" ]]; then
    guessed="$(find / -xdev -type d \( -name 'cabinet-frontend' -o -name 'bedolaga-cabinet' -o -name 'bedolaga-cabine' \) 2>/dev/null | while read -r d; do is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
    [[ -n "$guessed" ]] && echo "$guessed"
  fi
}

get_current_timer_calendar() {
  local path=""
  local value=""

  for path in \
    /etc/systemd/system/panel-backup-panel.timer \
    /etc/systemd/system/panel-backup-bedolaga.timer \
    /etc/systemd/system/panel-backup.timer \
    /usr/lib/systemd/system/panel-backup-panel.timer \
    /usr/lib/systemd/system/panel-backup-bedolaga.timer \
    /usr/lib/systemd/system/panel-backup.timer \
    /lib/systemd/system/panel-backup-panel.timer \
    /lib/systemd/system/panel-backup-bedolaga.timer \
    /lib/systemd/system/panel-backup.timer; do
    [[ -f "$path" ]] || continue
    value="$(grep -E '^OnCalendar=' "$path" | head -n1 | cut -d= -f2- || true)"
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  done

  return 1
}

get_timer_calendar_for_unit() {
  local unit_name="$1"
  local path=""
  local value=""
  for path in \
    "/etc/systemd/system/${unit_name}" \
    "/usr/lib/systemd/system/${unit_name}" \
    "/lib/systemd/system/${unit_name}"; do
    [[ -f "$path" ]] || continue
    value="$(grep -E '^OnCalendar=' "$path" | head -n1 | cut -d= -f2- || true)"
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  done
  return 1
}

has_panel_project() {
  [[ -n "$(detect_remnawave_dir || true)" ]]
}

has_bedolaga_project() {
  local bot_dir=""
  local cabinet_dir=""
  bot_dir="$(detect_bedolaga_bot_dir || true)"
  cabinet_dir="$(detect_bedolaga_cabinet_dir || true)"
  [[ -n "$bot_dir" && -n "$cabinet_dir" ]]
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

show_bedolaga_autodetect() {
  local bot_dir="$1"
  local cabinet_dir="$2"

  paint "$CLR_TITLE" "$(tr_text "Автопоиск Bedolaga" "Bedolaga path autodetect")"
  if [[ -n "$bot_dir" ]]; then
    paint "$CLR_OK" "$(tr_text "Найден путь бота" "Detected bot path"): ${bot_dir}"
  else
    paint "$CLR_WARN" "$(tr_text "Путь бота не найден автоматически." "Bot path was not auto-detected.")"
  fi

  if [[ -n "$cabinet_dir" ]]; then
    paint "$CLR_OK" "$(tr_text "Найден путь кабинета" "Detected cabinet path"): ${cabinet_dir}"
  else
    paint "$CLR_WARN" "$(tr_text "Путь кабинета не найден автоматически." "Cabinet path was not auto-detected.")"
  fi
}

load_existing_env_defaults() {
  local old_bot=""
  local old_admin=""
  local old_thread=""
  local old_thread_panel=""
  local old_thread_bedolaga=""
  local old_dir=""
  local old_bedolaga_bot_dir=""
  local old_bedolaga_cabinet_dir=""
  local old_calendar=""
  local old_calendar_panel=""
  local old_calendar_bedolaga=""
  local old_backup_lang=""
  local old_backup_encrypt=""
  local old_backup_password=""
  local old_backup_include=""
  local detected=""

  if [[ -f /etc/panel-backup.env ]]; then
    old_bot="$(grep -E '^TELEGRAM_BOT_TOKEN=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_admin="$(grep -E '^TELEGRAM_ADMIN_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_thread="$(grep -E '^TELEGRAM_THREAD_ID=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_thread_panel="$(grep -E '^TELEGRAM_THREAD_ID_PANEL=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_thread_bedolaga="$(grep -E '^TELEGRAM_THREAD_ID_BEDOLAGA=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_dir="$(grep -E '^REMNAWAVE_DIR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_bedolaga_bot_dir="$(grep -E '^BEDOLAGA_BOT_DIR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_bedolaga_cabinet_dir="$(grep -E '^BEDOLAGA_CABINET_DIR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar="$(grep -E '^BACKUP_ON_CALENDAR=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar_panel="$(grep -E '^BACKUP_ON_CALENDAR_PANEL=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar_bedolaga="$(grep -E '^BACKUP_ON_CALENDAR_BEDOLAGA=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_calendar="$(normalize_calendar_raw "$old_calendar")"
    old_calendar_panel="$(normalize_calendar_raw "$old_calendar_panel")"
    old_calendar_bedolaga="$(normalize_calendar_raw "$old_calendar_bedolaga")"
    old_backup_lang="$(grep -E '^BACKUP_LANG=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_backup_encrypt="$(grep -E '^BACKUP_ENCRYPT=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_backup_password="$(grep -E '^BACKUP_PASSWORD=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_backup_include="$(grep -E '^BACKUP_INCLUDE=' /etc/panel-backup.env | head -n1 | cut -d= -f2- || true)"
    old_bot="$(normalize_env_value_raw "$old_bot")"
    old_admin="$(normalize_env_value_raw "$old_admin")"
    old_thread="$(normalize_env_value_raw "$old_thread")"
    old_thread_panel="$(normalize_env_value_raw "$old_thread_panel")"
    old_thread_bedolaga="$(normalize_env_value_raw "$old_thread_bedolaga")"
    old_dir="$(normalize_env_value_raw "$old_dir")"
    old_bedolaga_bot_dir="$(normalize_env_value_raw "$old_bedolaga_bot_dir")"
    old_bedolaga_cabinet_dir="$(normalize_env_value_raw "$old_bedolaga_cabinet_dir")"
    old_backup_lang="$(normalize_env_value_raw "$old_backup_lang")"
    old_backup_encrypt="$(normalize_backup_encrypt_raw "$old_backup_encrypt")"
    old_backup_password="$(normalize_env_value_raw "$old_backup_password")"
    old_backup_include="$(normalize_env_value_raw "$old_backup_include")"
  fi

  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-$old_bot}"
  TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-$old_admin}"
  TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-$old_thread}"
  TELEGRAM_THREAD_ID_PANEL="${TELEGRAM_THREAD_ID_PANEL:-$old_thread_panel}"
  TELEGRAM_THREAD_ID_BEDOLAGA="${TELEGRAM_THREAD_ID_BEDOLAGA:-$old_thread_bedolaga}"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$old_dir}"
  BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-$old_bedolaga_bot_dir}"
  BEDOLAGA_CABINET_DIR="${BEDOLAGA_CABINET_DIR:-$old_bedolaga_cabinet_dir}"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-$old_calendar}"
  BACKUP_ON_CALENDAR_PANEL="${BACKUP_ON_CALENDAR_PANEL:-$old_calendar_panel}"
  BACKUP_ON_CALENDAR_BEDOLAGA="${BACKUP_ON_CALENDAR_BEDOLAGA:-$old_calendar_bedolaga}"
  BACKUP_LANG="${BACKUP_LANG:-$old_backup_lang}"
  BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-$old_backup_encrypt}"
  BACKUP_PASSWORD="${BACKUP_PASSWORD:-$old_backup_password}"
  BACKUP_INCLUDE="${BACKUP_INCLUDE:-$old_backup_include}"

  detected="$(detect_remnawave_dir || true)"
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$detected}"
  detected="$(detect_bedolaga_bot_dir || true)"
  BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-$detected}"
  detected="$(detect_bedolaga_cabinet_dir || true)"
  BEDOLAGA_CABINET_DIR="${BEDOLAGA_CABINET_DIR:-$detected}"
  BACKUP_ON_CALENDAR_PANEL="${BACKUP_ON_CALENDAR_PANEL:-$(get_timer_calendar_for_unit "panel-backup-panel.timer" || true)}"
  BACKUP_ON_CALENDAR_BEDOLAGA="${BACKUP_ON_CALENDAR_BEDOLAGA:-$(get_timer_calendar_for_unit "panel-backup-bedolaga.timer" || true)}"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-$(get_current_timer_calendar || true)}"
  BACKUP_ON_CALENDAR="$(normalize_calendar_raw "$BACKUP_ON_CALENDAR")"
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"
  BACKUP_ON_CALENDAR_PANEL="$(normalize_calendar_raw "${BACKUP_ON_CALENDAR_PANEL:-}")"
  BACKUP_ON_CALENDAR_BEDOLAGA="$(normalize_calendar_raw "${BACKUP_ON_CALENDAR_BEDOLAGA:-}")"
  BACKUP_ON_CALENDAR_PANEL="${BACKUP_ON_CALENDAR_PANEL:-$BACKUP_ON_CALENDAR}"
  BACKUP_ON_CALENDAR_BEDOLAGA="${BACKUP_ON_CALENDAR_BEDOLAGA:-$BACKUP_ON_CALENDAR}"
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

  read_prompt_raw input "$prompt" "$current" || return 130

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

  read_prompt_raw input "$prompt" "$current" || return 130

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

ask_value_clearable() {
  local prompt="$1"
  local current="${2:-}"
  local input=""

  read_prompt_raw input "${prompt} (- = $(tr_text "очистить" "clear"))" "$current" || return 130

  if is_back_command "$input"; then
    echo "__PBM_BACK__"
    return 0
  fi

  if [[ "$input" == "-" ]]; then
    echo ""
  elif [[ -n "$input" ]]; then
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

  read_prompt_raw input "$prompt" "$hint" "1" || return 130

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

  read_prompt_raw input "$prompt" "$hint" "1" || return 130

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
      read_prompt_raw answer "$prompt" "Y/n" || return 130
      answer="${answer:-y}"
    else
      read_prompt_raw answer "$prompt" "y/N" || return 130
      answer="${answer:-n}"
    fi

    normalized="$(normalize_answer_token "$answer")"
    case "$normalized" in
      y|Y|yes|YES|Yes|1|д|Д|да|Да|ДА)
        return 0
        ;;
      n|N|no|NO|No|0|н|Н|нет|Нет|НЕТ)
        return 1
        ;;
      *)
        if is_back_command "$normalized"; then
          return 2
        fi
        echo "$(tr_text "Введите y/n, yes/no, да/нет или 1/0." "Please answer y/n, yes/no, da/net or 1/0.")"
        ;;
    esac
  done
}
