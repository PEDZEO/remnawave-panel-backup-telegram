#!/usr/bin/env bash
# UI header rendering helpers for main menu and section screens.

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

draw_subheader() {
  local title="$1"
  local subtitle="${2:-}"
  local width="${MENU_BOX_WIDTH:-60}"
  local line=""

  MENU_OPTIONS_STARTED=0
  MENU_SEPARATOR_PRINTED=0
  MENU_HAS_BACK_OPTION=0
  MENU_BACK_ORIGINAL_KEY=""
  clear
  line="$(printf '═%.0s' $(seq 1 "$width"))"
  paint "$CLR_TITLE" "╔${line}"
  paint "${CLR_WHITE:-$CLR_ACCENT}" "║ ${title}"
  if [[ -n "$subtitle" ]]; then
    paint "$CLR_MUTED" "║ ${subtitle}"
  fi
  paint "$CLR_TITLE" "╚${line}"
  echo
  if declare -F ui_draw_screen_context >/dev/null 2>&1; then
    ui_draw_screen_context
  fi
}

draw_header_full() {
  local title="$1"
  local subtitle="${2:-}"
  local timer_state=""
  local timer_panel_state=""
  local timer_bedolaga_state=""
  local timer_status_label=""
  local schedule_now=""
  local schedule_label=""
  local latest_backup=""
  local latest_label=""
  local panel_state=""
  local sub_state=""
  local bot_state=""
  local cabinet_state=""
  local bot_profile=""
  local cabinet_profile=""
  local ram_label=""
  local disk_label=""
  local ram_percent=""
  local disk_percent=""
  local ram_color=""
  local disk_color=""
  local panel_color=""
  local sub_color=""
  local bot_color=""
  local cabinet_color=""
  local panel_version=""
  local sub_version=""
  local bot_version=""
  local cabinet_version=""
  local backup_age_h=-1
  local service_show=""
  local service_result=""
  local service_code=""
  local service_finish=""
  local last_run_label=""
  local encrypt_state=""
  local tg_state=""
  local env_token=""
  local env_chat=""
  local backup_age_label=""
  local backup_age_sec=-1
  local next_run_raw=""
  local next_run_label=""
  local next_run_color=""
  local now_ts=0
  local next_ts=0
  local next_left_sec=0
  local timer_color=""
  local backup_age_color=""
  local last_run_color=""
  local encrypt_color=""
  local tg_color=""
  local panel_dir_detected=""
  local show_full_header="0"
  local show_bedolaga_header="0"

  MENU_OPTIONS_STARTED=0
  MENU_SEPARATOR_PRINTED=0
  MENU_HAS_BACK_OPTION=0
  MENU_BACK_ORIGINAL_KEY=""
  clear
  timer_panel_state="$(systemctl_active_state panel-backup-panel.timer)"
  timer_bedolaga_state="$(systemctl_active_state panel-backup-bedolaga.timer)"
  if [[ "$timer_panel_state" == "active" || "$timer_bedolaga_state" == "active" ]]; then
    timer_state="active"
  else
    timer_state="inactive"
  fi
  timer_status_label="panel:${timer_panel_state} / bedolaga:${timer_bedolaga_state}"
  schedule_now="$(get_current_timer_calendar || true)"
  schedule_label="$(format_schedule_label "$schedule_now")"
  panel_state="$(container_state remnawave)"
  sub_state="$(container_state remnawave-subscription-page)"
  bot_state="$(container_state remnawave_bot)"
  cabinet_state="$(container_state cabinet_frontend)"
  bot_color="$(state_color "$bot_state")"
  cabinet_color="$(state_color "$cabinet_state")"
  bot_profile="$(dashboard_bedolaga_repo_profile "$(detect_bedolaga_bot_dir || true)" "bot")"
  cabinet_profile="$(dashboard_bedolaga_repo_profile "$(detect_bedolaga_cabinet_dir || true)" "cabinet")"
  bot_state="$(dashboard_status_with_profile "$bot_state" "$bot_profile")"
  cabinet_state="$(dashboard_status_with_profile "$cabinet_state" "$cabinet_profile")"
  panel_version="$(container_version_label remnawave)"
  sub_version="$(container_version_label remnawave-subscription-page)"
  bot_version="$(container_version_label remnawave_bot)"
  cabinet_version="$(container_version_label cabinet_frontend)"
  ram_label="$(memory_usage_label)"
  disk_label="$(disk_usage_label)"
  ram_percent="$(memory_usage_percent)"
  disk_percent="$(disk_usage_percent)"
  ram_color="$(metric_color_ram "$ram_percent")"
  disk_color="$(metric_color_disk "$disk_percent")"
  panel_color="$(state_color "$panel_state")"
  sub_color="$(state_color "$sub_state")"
  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_backup" ]]; then
    latest_label="$(basename "$latest_backup")"
    backup_age_sec="$(( $(date +%s) - $(date -r "$latest_backup" +%s) ))"
    backup_age_h="$(( backup_age_sec / 3600 ))"
  else
    latest_label="$(tr_text "нет" "none")"
  fi
  panel_dir_detected="$(detect_remnawave_dir || true)"
  if [[ -n "$panel_dir_detected" && -n "$latest_backup" ]]; then
    show_full_header="1"
  fi
  if docker inspect remnawave_bot >/dev/null 2>&1 || docker inspect cabinet_frontend >/dev/null 2>&1; then
    show_bedolaga_header="1"
  fi
  if [[ "$backup_age_sec" =~ ^[0-9]+$ && "$backup_age_sec" -ge 0 ]]; then
    if (( backup_age_sec < 60 )); then
      backup_age_label="$(tr_text "меньше минуты" "<1 min")"
    elif (( backup_age_sec < 3600 )); then
      backup_age_label="$((backup_age_sec / 60)) $(tr_text "мин" "min")"
    elif (( backup_age_sec < 86400 )); then
      backup_age_label="$((backup_age_sec / 3600)) $(tr_text "ч" "h") $(((backup_age_sec % 3600) / 60)) $(tr_text "мин" "min")"
    else
      backup_age_label="$((backup_age_sec / 86400)) $(tr_text "д" "d") $(((backup_age_sec % 86400) / 3600)) $(tr_text "ч" "h")"
    fi
  else
    backup_age_label="n/a"
  fi
  if [[ "$backup_age_sec" =~ ^[0-9]+$ && "$backup_age_sec" -ge 0 ]]; then
    if (( backup_age_h <= 6 )); then
      backup_age_color="$CLR_OK"
    elif (( backup_age_h <= 24 )); then
      backup_age_color="$CLR_WARN"
    else
      backup_age_color="$CLR_DANGER"
    fi
  else
    backup_age_color="$CLR_MUTED"
  fi

  service_show="$($SUDO systemctl show panel-backup-panel.service -p Result -p ExecMainStatus -p ExecMainExitTimestamp 2>/dev/null || true)"
  if [[ -z "$service_show" || "$service_show" != *"Result="* ]]; then
    service_show="$($SUDO systemctl show panel-backup-bedolaga.service -p Result -p ExecMainStatus -p ExecMainExitTimestamp 2>/dev/null || true)"
  fi
  service_result="$(echo "$service_show" | awk -F= '/^Result=/{print $2}')"
  service_code="$(echo "$service_show" | awk -F= '/^ExecMainStatus=/{print $2}')"
  service_finish="$(echo "$service_show" | awk -F= '/^ExecMainExitTimestamp=/{print $2}')"
  case "${service_result:-}" in
    success)
      if [[ "${service_code:-}" == "0" ]]; then
        last_run_label="$(tr_text "успешно" "success")"
        last_run_color="$CLR_OK"
      else
        last_run_label="$(tr_text "код ${service_code}" "code ${service_code}")"
        last_run_color="$CLR_WARN"
      fi
      ;;
    failed|exit-code|timeout)
      last_run_label="$(tr_text "ошибка" "failed")"
      last_run_color="$CLR_DANGER"
      ;;
    *)
      last_run_label="${service_result:-n/a}"
      last_run_color="$CLR_MUTED"
      ;;
  esac

  env_token="$(grep -E '^TELEGRAM_BOT_TOKEN=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  env_chat="$(grep -E '^TELEGRAM_ADMIN_ID=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  if [[ -n "$env_token" && -n "$env_chat" ]]; then
    tg_state="$(tr_text "настроен" "configured")"
    tg_color="$CLR_OK"
  else
    tg_state="$(tr_text "не настроен" "not configured")"
    tg_color="$CLR_WARN"
  fi
  if [[ "$(grep -E '^BACKUP_ENCRYPT=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\"' || true)" == "1" ]]; then
    encrypt_state="$(tr_text "включено" "enabled")"
    encrypt_color="$CLR_OK"
  else
    encrypt_state="$(tr_text "выключено" "disabled")"
    encrypt_color="$CLR_WARN"
  fi
  next_run_raw="$($SUDO systemctl show panel-backup-panel.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)"
  if [[ -z "$next_run_raw" || "$next_run_raw" == "n/a" ]]; then
    next_run_raw="$($SUDO systemctl show panel-backup-bedolaga.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)"
  fi
  if [[ -n "$next_run_raw" && "$next_run_raw" != "n/a" ]]; then
    now_ts="$(date +%s)"
    next_ts="$(date -d "$next_run_raw" +%s 2>/dev/null || echo 0)"
    if [[ "$next_ts" =~ ^[0-9]+$ ]] && (( next_ts > 0 )); then
      next_left_sec=$((next_ts - now_ts))
      if (( next_left_sec <= 0 )); then
        next_run_label="$(tr_text "меньше минуты" "<1 min")"
        next_run_color="$CLR_WARN"
      elif (( next_left_sec < 3600 )); then
        next_run_label="$((next_left_sec / 60)) $(tr_text "мин" "min")"
        next_run_color="$CLR_OK"
      elif (( next_left_sec < 86400 )); then
        next_run_label="$((next_left_sec / 3600)) $(tr_text "ч" "h") $(((next_left_sec % 3600) / 60)) $(tr_text "мин" "min")"
        next_run_color="$CLR_OK"
      else
        next_run_label="$((next_left_sec / 86400)) $(tr_text "д" "d") $(((next_left_sec % 86400) / 3600)) $(tr_text "ч" "h")"
        next_run_color="$CLR_OK"
      fi
    else
      next_run_label="n/a"
      next_run_color="$CLR_MUTED"
    fi
  else
    next_run_label="n/a"
    next_run_color="$CLR_MUTED"
  fi
  timer_color="$(state_color "$timer_state")"

  paint "$CLR_TITLE" "============================================================"
  paint "${CLR_WHITE:-$CLR_ACCENT}" "  ${title}"
  if [[ -n "$subtitle" ]]; then
    paint "$CLR_MUTED" "  ${subtitle}"
  fi
  print_separator
  paint_labeled_value "RAM:" "$ram_label" "$ram_color"
  paint_labeled_value "$(tr_text "Диск:" "Disk:")" "$disk_label" "$disk_color"
  if [[ "$show_full_header" == "1" ]]; then
    print_separator
    paint_labeled_value "$(tr_text "Панель (remnawave):" "Panel (remnawave):")" "$panel_state" "$panel_color"
    paint_labeled_value "$(tr_text "Версия панели:" "Panel version:")" "$panel_version" "$CLR_ACCENT"
    paint_labeled_value "$(tr_text "Подписка:" "Subscription:")" "$sub_state" "$sub_color"
    paint_labeled_value "$(tr_text "Версия подписки:" "Subscription version:")" "$sub_version" "$CLR_ACCENT"
    print_separator
    paint_labeled_value "$(tr_text "Таймеры:" "Timers:")" "${timer_status_label}" "$timer_color"
    paint_labeled_value "$(tr_text "Расписание:" "Schedule:")" "${schedule_label}" "$CLR_ACCENT"
    paint_labeled_value "$(tr_text "До следующего backup:" "Until next backup:")" "${next_run_label}" "$next_run_color"
    paint_labeled_value "$(tr_text "Последний backup:" "Latest backup:")" "$(short_backup_label "$latest_label")" "$CLR_ACCENT"
    paint_labeled_value "$(tr_text "Возраст backup:" "Backup age:")" "${backup_age_label}" "$backup_age_color"
    paint_labeled_value "$(tr_text "Последний запуск сервиса:" "Last service run:")" "${last_run_label}" "$last_run_color"
    if [[ -n "${service_finish:-}" ]]; then
      paint_labeled_value "$(tr_text "Время последнего запуска:" "Last run time:")" "${service_finish}" "$CLR_MUTED"
    fi
    paint_labeled_value "$(tr_text "Шифрование:" "Encryption:")" "${encrypt_state}" "$encrypt_color"
    paint_labeled_value "Telegram:" "${tg_state}" "$tg_color"
  fi
  if [[ "$show_bedolaga_header" == "1" ]]; then
    print_separator
    paint_labeled_value "$(tr_text "Бот (bedolaga):" "Bot (bedolaga):")" "$bot_state" "$bot_color"
    paint_labeled_value "$(tr_text "Версия бота:" "Bot version:")" "$bot_version" "$CLR_ACCENT"
    paint_labeled_value "$(tr_text "Кабинет (bedolaga):" "Cabinet (bedolaga):")" "$cabinet_state" "$cabinet_color"
    paint_labeled_value "$(tr_text "Версия кабинета:" "Cabinet version:")" "$cabinet_version" "$CLR_ACCENT"
  fi
  paint "$CLR_TITLE" "============================================================"
  paint "$CLR_MUTED" "  $(tr_text "Контакт:" "Contact:") @pedzeo"
  paint "$CLR_MUTED" "$(tr_text "Выберите действие." "Select an action.")"
  echo
}

format_duration_compact() {
  local seconds="${1:-}"

  if [[ ! "$seconds" =~ ^[0-9]+$ ]] || (( seconds < 0 )); then
    echo "n/a"
    return 0
  fi

  if (( seconds < 60 )); then
    echo "$(tr_text "меньше минуты" "<1 min")"
  elif (( seconds < 3600 )); then
    echo "$((seconds / 60)) $(tr_text "мин" "min")"
  elif (( seconds < 86400 )); then
    echo "$((seconds / 3600)) $(tr_text "ч" "h") $(((seconds % 3600) / 60)) $(tr_text "мин" "min")"
  else
    echo "$((seconds / 86400)) $(tr_text "д" "d") $(((seconds % 86400) / 3600)) $(tr_text "ч" "h")"
  fi
}

dashboard_line() {
  local label="$1"
  local value="$2"
  local color="${3:-$CLR_MUTED}"
  local label_color="${4:-$CLR_MUTED}"
  local width=20
  local len=0
  local pad=1
  local padding=""

  len="${#label}"
  if (( len < width )); then
    pad=$((width - len))
  fi
  padding="$(printf '%*s' "$pad" '')"

  if [[ "$COLOR" == "1" ]]; then
    printf "%b║%b %b%s%s%b : %b%s%b\n" "$CLR_TITLE" "$CLR_RESET" "$label_color" "$label" "$padding" "$CLR_RESET" "$color" "$value" "$CLR_RESET"
  else
    printf "║ %s%s : %s\n" "$label" "$padding" "$value"
  fi
}

dashboard_section() {
  local title="$1"
  local color="${2:-$CLR_ACCENT}"
  paint "$color" "╠═[ ${title} ]"
}

dashboard_gap() {
  paint "$CLR_TITLE" "║"
}

dashboard_bedolaga_repo_profile() {
  local repo_dir="$1"
  local component="$2"
  local origin=""
  local normalized=""

  [[ -n "$repo_dir" && -d "${repo_dir}/.git" ]] || return 0
  command -v git >/dev/null 2>&1 || return 0
  origin="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  [[ -n "$origin" ]] || return 0
  normalized="${origin,,}"

  case "${component}:${normalized}" in
    bot:*github.com/pedzeo/remnawave-bedolaga-telegram-bot*|bot:*github.com:pedzeo/remnawave-bedolaga-telegram-bot*|cabinet:*github.com/pedzeo/cabinet-frontend*|cabinet:*github.com:pedzeo/cabinet-frontend*)
      printf '%s' "fork"
      return 0
      ;;
    bot:*github.com/bedolaga-dev/remnawave-bedolaga-telegram-bot*|bot:*github.com:bedolaga-dev/remnawave-bedolaga-telegram-bot*|cabinet:*github.com/bedolaga-dev/bedolaga-cabinet*|cabinet:*github.com:bedolaga-dev/bedolaga-cabinet*)
      printf '%s' "official"
      return 0
      ;;
  esac

  printf '%s' "custom"
}

dashboard_bedolaga_profile_label() {
  case "${1:-}" in
    fork) tr_text "fork PEDZEO" "PEDZEO fork" ;;
    official) tr_text "official" "official" ;;
    custom) tr_text "custom repo" "custom repo" ;;
    *) return 0 ;;
  esac
}

dashboard_status_with_profile() {
  local status="$1"
  local profile="$2"
  local profile_label=""

  profile_label="$(dashboard_bedolaga_profile_label "$profile")"
  if [[ -n "$profile_label" ]]; then
    printf '%s (%s)' "$status" "$profile_label"
  else
    printf '%s' "$status"
  fi
}

dashboard_bar() {
  local percent="${1:-0}"
  local filled=0
  local empty=0
  local out=""

  [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
  (( percent < 0 )) && percent=0
  (( percent > 100 )) && percent=100
  filled=$((percent / 10))
  empty=$((10 - filled))
  out="["
  while (( filled > 0 )); do out="${out}■"; filled=$((filled - 1)); done
  while (( empty > 0 )); do out="${out}□"; empty=$((empty - 1)); done
  out="${out}]"
  printf '%s' "$out"
}

dashboard_metric_color() {
  local percent="${1:-}"
  local warn="${2:-70}"
  local danger="${3:-90}"

  if [[ "$percent" =~ ^[0-9]+$ ]]; then
    if (( percent >= danger )); then
      printf '%s' "$CLR_DANGER"
    elif (( percent >= warn )); then
      printf '%s' "$CLR_WARN"
    else
      printf '%s' "$CLR_OK"
    fi
  else
    printf '%s' "$CLR_MUTED"
  fi
}

human_mb_compact() {
  local mb="${1:-0}"
  if [[ ! "$mb" =~ ^[0-9]+$ ]]; then
    printf '%s' "n/a"
    return 0
  fi
  if (( mb >= 1024 )); then
    awk -v m="$mb" 'BEGIN { printf "%.1fG", m / 1024 }'
  else
    printf '%sM' "$mb"
  fi
}

dashboard_os_kernel() {
  local pretty=""
  local kernel=""

  pretty="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")"
  kernel="$(uname -r 2>/dev/null | cut -d- -f1)"
  printf '%s (%s)' "${pretty:-Linux}" "${kernel:-unknown}"
}

dashboard_uptime() {
  local uptime_seconds=0
  local days=0
  local weeks=0
  local hours=0
  local mins=0
  local users=0
  local label=""

  uptime_seconds="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
  [[ "$uptime_seconds" =~ ^[0-9]+$ ]] || uptime_seconds=0
  weeks=$((uptime_seconds / 604800))
  days=$(((uptime_seconds % 604800) / 86400))
  hours=$(((uptime_seconds % 86400) / 3600))
  mins=$(((uptime_seconds % 3600) / 60))
  (( weeks > 0 )) && label="${label}${weeks}$(tr_text "нед" "w") "
  (( days > 0 )) && label="${label}${days}$(tr_text "д" "d") "
  label="${label}${hours}$(tr_text "ч" "h") ${mins}$(tr_text "мин" "m")"
  users="$(who 2>/dev/null | wc -l | awk '{print $1}')"
  printf '%s (%s: %s)' "$label" "$(tr_text "Юзеров" "Users")" "${users:-0}"
}

dashboard_virt() {
  local virt=""
  virt="$(systemd-detect-virt 2>/dev/null || true)"
  case "$virt" in
    none|"") printf '%s' "$(tr_text "Bare metal" "Bare metal")" ;;
    kvm) printf '%s' "KVM ($(tr_text "виртуализация" "virtualized"))" ;;
    *) printf '%s' "$virt" ;;
  esac
}

dashboard_cpu_percent() {
  local line1=""
  local line2=""
  local _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 rest1
  local user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 rest2
  local idle_all1=0
  local idle_all2=0
  local non_idle1=0
  local non_idle2=0
  local total1=0
  local total2=0
  local total_delta=0
  local idle_delta=0

  line1="$(grep '^cpu ' /proc/stat 2>/dev/null || true)"
  sleep 0.03
  line2="$(grep '^cpu ' /proc/stat 2>/dev/null || true)"
  if [[ -z "$line1" || -z "$line2" ]]; then
    printf '%s' "0"
    return 0
  fi
  read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 rest1 <<<"$line1"
  read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 rest2 <<<"$line2"
  user1=${user1:-0}; nice1=${nice1:-0}; system1=${system1:-0}; idle1=${idle1:-0}; iowait1=${iowait1:-0}; irq1=${irq1:-0}; softirq1=${softirq1:-0}; steal1=${steal1:-0}
  user2=${user2:-0}; nice2=${nice2:-0}; system2=${system2:-0}; idle2=${idle2:-0}; iowait2=${iowait2:-0}; irq2=${irq2:-0}; softirq2=${softirq2:-0}; steal2=${steal2:-0}
  idle_all1=$((idle1 + iowait1))
  idle_all2=$((idle2 + iowait2))
  non_idle1=$((user1 + nice1 + system1 + irq1 + softirq1 + steal1))
  non_idle2=$((user2 + nice2 + system2 + irq2 + softirq2 + steal2))
  total1=$((idle_all1 + non_idle1))
  total2=$((idle_all2 + non_idle2))
  total_delta=$((total2 - total1))
  idle_delta=$((idle_all2 - idle_all1))
  if (( total_delta <= 0 )); then
    printf '%s' "0"
  else
    awk -v total="$total_delta" -v idle="$idle_delta" 'BEGIN { printf "%.0f", (1 - idle / total) * 100 }'
  fi
}

dashboard_memory_metric() {
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
    printf '%s|%s|%s' "$percent" "$(human_mb_compact "$used_mb")" "$(human_mb_compact "$total_mb")"
  else
    printf '%s' "0|n/a|n/a"
  fi
}

dashboard_disk_metric() {
  local raw=""
  local used=""
  local total=""
  local percent=""

  raw="$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5"|"$3"|"$2}' || true)"
  if [[ -n "$raw" ]]; then
    printf '%s' "$raw"
  else
    printf '%s' "0|n/a|n/a"
  fi
}

dashboard_public_net_refresh() {
  local cache="/tmp/panel-backup-dashboard-ip.cache"

  cache="${1:-$cache}"
  nohup bash -c '
cache="$1"
cache_tmp="${cache}.$$"
lock="${cache}.lock"
trap '\''rm -f "$lock" "$cache_tmp"'\'' EXIT
json=""
ip=""
country=""
org=""
ping_ms=""
if command -v curl >/dev/null 2>&1; then
  json="$(curl -fsSL --connect-timeout 0.5 --max-time 0.5 https://ipinfo.io/json 2>/dev/null || true)"
fi
ip="$(printf "%s" "$json" | sed -n "s/.*\"ip\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")"
country="$(printf "%s" "$json" | sed -n "s/.*\"country\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")"
org="$(printf "%s" "$json" | sed -n "s/.*\"org\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")"
[[ -n "$ip" ]] || ip="n/a"
[[ -n "$country" ]] || country="--"
[[ -n "$org" ]] || org="unknown"
[[ -n "$ping_ms" ]] && ping_ms="${ping_ms} ms" || ping_ms="n/a"
printf "%s|%s|%s|%s" "$ip" "$ping_ms" "$country" "$org" >"$cache_tmp"
mv -f "$cache_tmp" "$cache"
' dashboard-public-net "$cache" >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
}

dashboard_public_net_start_refresh() {
  local cache="$1"
  local ttl="${2:-0}"
  local lock="${cache}.lock"
  local now=0
  local cache_mtime=0
  local lock_mtime=0

  now="$(date +%s)"
  if [[ "$ttl" =~ ^[0-9]+$ && "$ttl" -gt 0 && -f "$cache" ]]; then
    cache_mtime="$(date -r "$cache" +%s 2>/dev/null || echo 0)"
    if [[ "$cache_mtime" =~ ^[0-9]+$ ]] && (( now - cache_mtime < ttl )); then
      return 0
    fi
  fi
  if [[ -f "$lock" ]]; then
    lock_mtime="$(date -r "$lock" +%s 2>/dev/null || echo 0)"
    if [[ "$lock_mtime" =~ ^[0-9]+$ ]] && (( now - lock_mtime < 60 )); then
      return 0
    fi
  fi
  printf '%s' "$now" >"$lock" 2>/dev/null || return 0
  dashboard_public_net_refresh "$cache"
}

dashboard_public_net() {
  local cache="/tmp/panel-backup-dashboard-ip.cache"
  local now=0
  local mtime=0
  local cached=""

  now="$(date +%s)"
  if [[ -f "$cache" ]]; then
    mtime="$(date -r "$cache" +%s 2>/dev/null || echo 0)"
    cached="$(cat "$cache" 2>/dev/null || true)"
    if [[ "$mtime" =~ ^[0-9]+$ ]] && (( now - mtime < 600 )); then
      [[ -n "$cached" ]] && { printf '%s' "$cached"; return 0; }
    fi
    [[ -n "$cached" ]] && { printf '%s' "$cached"; return 0; }
  fi

  printf '%s|%s|%s|%s' "n/a" "n/a" "--" "$(tr_text "загрузка..." "loading...")"
}

dashboard_usd_rub_refresh() {
  local cache="/tmp/panel-backup-dashboard-usdrub.cache"

  cache="${1:-$cache}"
  nohup bash -c '
cache="$1"
cache_tmp="${cache}.$$"
lock="${cache}.lock"
trap '\''rm -f "$lock" "$cache_tmp"'\'' EXIT
json=""
usd_block=""
value=""
previous=""
change=""
rate_date=""
if command -v curl >/dev/null 2>&1; then
  json="$(curl -fsSL --connect-timeout 0.8 --max-time 0.8 https://www.cbr-xml-daily.ru/daily_json.js 2>/dev/null || true)"
fi
json="$(printf "%s" "$json" | tr "\n" " ")"
usd_block="$(printf "%s" "$json" | sed -n "s/.*\"USD\"[[:space:]]*:{\([^}]*\)}.*/\1/p")"
value="$(printf "%s" "$usd_block" | sed -n "s/.*\"Value\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p")"
previous="$(printf "%s" "$usd_block" | sed -n "s/.*\"Previous\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p")"
rate_date="$(printf "%s" "$json" | sed -n "s/.*\"Date\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")"
rate_date="${rate_date%%T*}"
if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  value="$(awk -v value="$value" "BEGIN { printf \"%.2f\", value }")"
  if [[ "$previous" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    change="$(awk -v value="$value" -v previous="$previous" "BEGIN { diff = value - previous; if (diff > 0) printf \"+%.2f\", diff; else printf \"%.2f\", diff }")"
  else
    change="n/a"
  fi
  printf "%s|%s|%s" "$value" "$change" "${rate_date:-CBR}" >"$cache_tmp"
  mv -f "$cache_tmp" "$cache"
fi
' dashboard-usd-rub "$cache" >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
}

dashboard_usd_rub_start_refresh() {
  local cache="$1"
  local ttl="${2:-0}"
  local lock="${cache}.lock"
  local now=0
  local cache_mtime=0
  local lock_mtime=0

  now="$(date +%s)"
  if [[ "$ttl" =~ ^[0-9]+$ && "$ttl" -gt 0 && -f "$cache" ]]; then
    cache_mtime="$(date -r "$cache" +%s 2>/dev/null || echo 0)"
    if [[ "$cache_mtime" =~ ^[0-9]+$ ]] && (( now - cache_mtime < ttl )); then
      return 0
    fi
  fi
  if [[ -f "$lock" ]]; then
    lock_mtime="$(date -r "$lock" +%s 2>/dev/null || echo 0)"
    if [[ "$lock_mtime" =~ ^[0-9]+$ ]] && (( now - lock_mtime < 60 )); then
      return 0
    fi
  fi
  printf '%s' "$now" >"$lock" 2>/dev/null || return 0
  dashboard_usd_rub_refresh "$cache"
}

dashboard_usd_rub() {
  local cache="/tmp/panel-backup-dashboard-usdrub.cache"
  local now=0
  local mtime=0
  local cached=""

  now="$(date +%s)"
  if [[ -f "$cache" ]]; then
    mtime="$(date -r "$cache" +%s 2>/dev/null || echo 0)"
    cached="$(cat "$cache" 2>/dev/null || true)"
    if [[ "$mtime" =~ ^[0-9]+$ ]] && (( now - mtime < 21600 )); then
      [[ -n "$cached" ]] && { printf '%s' "$cached"; return 0; }
    fi
    [[ -n "$cached" ]] && { printf '%s' "$cached"; return 0; }
  fi

  printf '%s|%s|%s' "$(tr_text "загрузка..." "loading...")" "" ""
}

dashboard_version_label() {
  local version="${1:-}"

  version="${version//$'\r'/}"
  version="${version//$'\n'/}"
  case "$version" in
    ""|"unknown"|"<no value>"|"latest")
      printf '%s' ""
      return 0
      ;;
    v*)
      printf '%s' "$version"
      return 0
      ;;
    sha-*)
      printf '%s' ""
      return 0
      ;;
  esac

  if [[ "$version" =~ ^[[:xdigit:]]{7,64}$ ]]; then
    printf '%s' ""
  elif [[ "$version" =~ ^[0-9]+([.][0-9]+)*([._-][0-9A-Za-z.-]+)?$ ]]; then
    printf 'v%s' "$version"
  else
    printf '%s' "$version"
  fi
}

dashboard_next_run_label() {
  local raw="$1"
  local now_ts=0
  local next_ts=0
  local left=0

  if [[ -z "$raw" || "$raw" == "n/a" ]]; then
    printf '%s' "n/a"
    return 0
  fi
  now_ts="$(date +%s)"
  next_ts="$(date -d "$raw" +%s 2>/dev/null || echo 0)"
  if [[ "$next_ts" =~ ^[0-9]+$ ]] && (( next_ts > now_ts )); then
    left=$((next_ts - now_ts))
    printf '%s' "$(format_duration_compact "$left")"
  else
    printf '%s' "$raw"
  fi
}

dashboard_next_run_for_unit() {
  local unit="$1"
  local raw=""

  raw="$($SUDO systemctl show "$unit" -p NextElapseUSecRealtime --value 2>/dev/null | sed -n '1p' || true)"
  dashboard_next_run_label "$raw"
}

dashboard_timer_info() {
  local unit="$1"
  local raw=""
  local active_state=""
  local enabled_state=""
  local next_raw=""

  raw="$($SUDO systemctl show "$unit" -p ActiveState -p UnitFileState -p NextElapseUSecRealtime 2>/dev/null || true)"
  active_state="$(printf '%s\n' "$raw" | awk -F= '$1=="ActiveState" {print $2; exit}')"
  enabled_state="$(printf '%s\n' "$raw" | awk -F= '$1=="UnitFileState" {print $2; exit}')"
  next_raw="$(printf '%s\n' "$raw" | awk -F= '$1=="NextElapseUSecRealtime" {print $2; exit}')"
  printf '%s|%s|%s' "${active_state:-inactive}" "${enabled_state:-disabled}" "$(dashboard_next_run_label "$next_raw")"
}

dashboard_schedule_for_unit() {
  local unit="$1"
  local fallback="$2"
  local value=""
  value="$(get_timer_calendar_for_unit "$unit" || true)"
  printf '%s' "${value:-$fallback}"
}

draw_header() {
  local title="$1"
  local subtitle="${2:-}"
  local os_kernel=""
  local uptime_label=""
  local virt_label=""
  local net_info=""
  local public_ip=""
  local public_ping=""
  local public_country=""
  local public_org=""
  local cpu_model=""
  local cpu_percent=0
  local cpu_cores=0
  local mem_metric=""
  local mem_percent=0
  local mem_used=""
  local mem_total=""
  local disk_metric=""
  local disk_percent=0
  local disk_used=""
  local disk_total=""
  local panel_status=""
  local panel_version=""
  local panel_version_label=""
  local sub_version=""
  local sub_version_label=""
  local bot_status=""
  local cabinet_status=""
  local bot_profile=""
  local cabinet_profile=""
  local bot_status_color=""
  local cabinet_status_color=""
  local caddy_status=""
  local caddy_version=""
  local caddy_version_label=""
  local capacity_label=""
  local has_panel=0
  local has_bot=0
  local has_cabinet=0
  local has_caddy=0
  local has_panel_backup=0
  local has_bedolaga_backup=0
  local has_latest_backup=0
  local has_tg_config=0
  local has_encrypt_enabled=0
  local has_backup_section=0
  local status_rows=0
  local panel_timer_state=""
  local panel_timer_enabled=""
  local panel_timer_info=""
  local bedolaga_timer_state=""
  local bedolaga_timer_enabled=""
  local bedolaga_timer_info=""
  local panel_schedule=""
  local bedolaga_schedule=""
  local panel_next=""
  local bedolaga_next=""
  local latest_backup=""
  local latest_label=""
  local backup_age_sec=-1
  local backup_age_label="n/a"
  local backup_age_color="$CLR_MUTED"
  local env_token=""
  local env_chat=""
  local tg_state=""
  local tg_color=""
  local encrypt_state=""
  local encrypt_color=""
  local backup_script_state=""
  local config_state=""
  local panel_calendar_env=""
  local bedolaga_calendar_env=""
  local default_calendar_env=""
  local usd_rub_info=""
  local usd_rub_value=""
  local usd_rub_change=""
  local usd_rub_date=""
  local usd_rub_label=""
  local usd_rub_color="$CLR_MUTED"

  MENU_OPTIONS_STARTED=0
  MENU_SEPARATOR_PRINTED=0
  MENU_HAS_BACK_OPTION=0
  MENU_BACK_ORIGINAL_KEY=""
  clear

  os_kernel="$(dashboard_os_kernel)"
  uptime_label="$(dashboard_uptime)"
  virt_label="$(dashboard_virt)"
  dashboard_public_net_start_refresh "/tmp/panel-backup-dashboard-ip.cache" 600
  dashboard_usd_rub_start_refresh "/tmp/panel-backup-dashboard-usdrub.cache" 21600
  net_info="$(dashboard_public_net)"
  IFS='|' read -r public_ip public_ping public_country public_org <<< "$net_info"

  cpu_model="$(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  [[ -n "$cpu_model" ]] || cpu_model="$(awk -F: '/Hardware|Processor/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  [[ -n "$cpu_model" ]] || cpu_model="$(tr_text "неизвестно" "unknown")"
  cpu_percent="$(dashboard_cpu_percent)"
  cpu_cores="$(nproc 2>/dev/null || echo 0)"

  mem_metric="$(dashboard_memory_metric)"
  IFS='|' read -r mem_percent mem_used mem_total <<< "$mem_metric"
  disk_metric="$(dashboard_disk_metric)"
  IFS='|' read -r disk_percent disk_used disk_total <<< "$disk_metric"

  if docker inspect remnawave >/dev/null 2>&1; then
    has_panel=1
    panel_version="$(container_version_label remnawave)"
    panel_version_label="$(dashboard_version_label "$panel_version")"
    panel_status="$(tr_text "Панель" "Panel")"
    [[ -n "$panel_version_label" ]] && panel_status+=" (${panel_version_label})"
    if docker inspect remnawave-subscription-page >/dev/null 2>&1; then
      sub_version="$(container_version_label remnawave-subscription-page)"
      sub_version_label="$(dashboard_version_label "$sub_version")"
      panel_status+=" + Sub-page"
      [[ -n "$sub_version_label" ]] && panel_status+=" (${sub_version_label})"
    fi
  else
    panel_status=""
  fi

  if docker inspect remnawave_bot >/dev/null 2>&1; then
    has_bot=1
    bot_status="$(container_state remnawave_bot)"
    bot_status_color="$(state_color "$bot_status")"
    bot_profile="$(dashboard_bedolaga_repo_profile "$(detect_bedolaga_bot_dir || true)" "bot")"
    bot_status="$(dashboard_status_with_profile "$bot_status" "$bot_profile")"
  fi
  if docker inspect cabinet_frontend >/dev/null 2>&1; then
    has_cabinet=1
    cabinet_status="$(container_state cabinet_frontend)"
    cabinet_status_color="$(state_color "$cabinet_status")"
    cabinet_profile="$(dashboard_bedolaga_repo_profile "$(detect_bedolaga_cabinet_dir || true)" "cabinet")"
    cabinet_status="$(dashboard_status_with_profile "$cabinet_status" "$cabinet_profile")"
  fi
  if docker inspect remnawave-caddy >/dev/null 2>&1; then
    has_caddy=1
    caddy_version="$(container_version_label remnawave-caddy)"
    caddy_version_label="$(dashboard_version_label "$caddy_version")"
    caddy_status="Caddy"
    [[ -n "$caddy_version_label" ]] && caddy_status+=" (${caddy_version_label})"
    caddy_status+=" ($(tr_text "в Docker" "Docker"))"
  else
    caddy_status=""
  fi
  capacity_label="$(tr_text "n/a (запустите speedtest в Reshala)" "n/a (run speedtest in Reshala)")"

  panel_timer_info="$(dashboard_timer_info panel-backup-panel.timer)"
  IFS='|' read -r panel_timer_state panel_timer_enabled panel_next <<< "$panel_timer_info"
  bedolaga_timer_info="$(dashboard_timer_info panel-backup-bedolaga.timer)"
  IFS='|' read -r bedolaga_timer_state bedolaga_timer_enabled bedolaga_next <<< "$bedolaga_timer_info"
  if (( has_panel == 1 )) && [[ "$panel_timer_state" == "active" || "$panel_timer_enabled" == "enabled" ]]; then
    has_panel_backup=1
  fi
  if (( has_bot == 1 || has_cabinet == 1 )) && [[ "$bedolaga_timer_state" == "active" || "$bedolaga_timer_enabled" == "enabled" ]]; then
    has_bedolaga_backup=1
  fi
  default_calendar_env="$(grep -E '^BACKUP_ON_CALENDAR=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  panel_calendar_env="$(grep -E '^BACKUP_ON_CALENDAR_PANEL=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  bedolaga_calendar_env="$(grep -E '^BACKUP_ON_CALENDAR_BEDOLAGA=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  default_calendar_env="$(normalize_calendar_raw "$default_calendar_env")"
  panel_calendar_env="$(normalize_calendar_raw "$panel_calendar_env")"
  bedolaga_calendar_env="$(normalize_calendar_raw "$bedolaga_calendar_env")"
  default_calendar_env="${default_calendar_env:-*-*-* 03:40:00 UTC}"
  panel_schedule="$(dashboard_schedule_for_unit "panel-backup-panel.timer" "${panel_calendar_env:-$default_calendar_env}")"
  bedolaga_schedule="$(dashboard_schedule_for_unit "panel-backup-bedolaga.timer" "${bedolaga_calendar_env:-$default_calendar_env}")"

  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_backup" ]]; then
    has_latest_backup=1
    latest_label="$(short_backup_label "$(basename "$latest_backup")")"
    backup_age_sec="$(( $(date +%s) - $(date -r "$latest_backup" +%s) ))"
    backup_age_label="$(format_duration_compact "$backup_age_sec")"
    if (( backup_age_sec <= 21600 )); then
      backup_age_color="$CLR_OK"
    elif (( backup_age_sec <= 86400 )); then
      backup_age_color="$CLR_WARN"
    else
      backup_age_color="$CLR_DANGER"
    fi
  else
    latest_label="$(tr_text "нет архивов" "no backups")"
  fi

  env_token="$(grep -E '^TELEGRAM_BOT_TOKEN=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  env_chat="$(grep -E '^TELEGRAM_ADMIN_ID=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  if [[ -n "$env_token" && -n "$env_chat" ]]; then
    has_tg_config=1
    tg_state="$(tr_text "настроен" "configured")"
    tg_color="$CLR_OK"
  else
    tg_state="$(tr_text "не настроен" "not configured")"
    tg_color="$CLR_WARN"
  fi

  if [[ "$(grep -E '^BACKUP_ENCRYPT=' /etc/panel-backup.env 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\"' || true)" == "1" ]]; then
    has_encrypt_enabled=1
    encrypt_state="$(tr_text "включено" "enabled")"
    encrypt_color="$CLR_OK"
  else
    encrypt_state="$(tr_text "выключено" "disabled")"
    encrypt_color="$CLR_WARN"
  fi

  [[ -x /usr/local/bin/panel-backup.sh ]] && backup_script_state="$(tr_text "установлен" "installed")" || backup_script_state="$(tr_text "не установлен" "not installed")"
  [[ -f /etc/panel-backup.env ]] && config_state="$(tr_text "есть" "present")" || config_state="$(tr_text "нет" "missing")"
  if (( has_panel_backup == 1 || has_bedolaga_backup == 1 || has_latest_backup == 1 || has_tg_config == 1 || has_encrypt_enabled == 1 )); then
    has_backup_section=1
  fi

  usd_rub_info="$(dashboard_usd_rub)"
  IFS='|' read -r usd_rub_value usd_rub_change usd_rub_date <<< "$usd_rub_info"
  if [[ "$usd_rub_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    usd_rub_label="${usd_rub_value} ₽"
    [[ -n "$usd_rub_change" && "$usd_rub_change" != "n/a" ]] && usd_rub_label+=" (${usd_rub_change})"
    [[ -n "$usd_rub_date" ]] && usd_rub_label+=" · ЦБ ${usd_rub_date}"
    if [[ "$usd_rub_change" == -* ]]; then
      usd_rub_color="$CLR_OK"
    elif [[ "$usd_rub_change" == +* ]]; then
      usd_rub_color="$CLR_WARN"
    else
      usd_rub_color="$CLR_ACCENT"
    fi
  else
    usd_rub_label="${usd_rub_value:-$(tr_text "загрузка..." "loading...")}"
    usd_rub_color="$CLR_MUTED"
  fi

  paint "$CLR_TITLE" "╔════════════════════════════════════════════════════════════"
  paint "${CLR_WHITE:-$CLR_ACCENT}" "║ ${title}"
  if [[ -n "$subtitle" ]]; then
    paint "$CLR_MUTED" "║ ${subtitle}"
  fi
  dashboard_section "$(tr_text "СИСТЕМА" "SYSTEM")" "$CLR_ACCENT"
  dashboard_line "$(tr_text "ОС / Ядро" "OS / Kernel")" "$os_kernel" "$CLR_ACCENT" "$CLR_ACCENT"
  dashboard_line "$(tr_text "Аптайм" "Uptime")" "$uptime_label" "$CLR_MUTED" "$CLR_ACCENT"
  dashboard_line "$(tr_text "Виртуалка" "Virtualization")" "$virt_label" "$CLR_MUTED" "$CLR_ACCENT"
  dashboard_line "$(tr_text "IP Адрес" "IP Address")" "${public_ip} (${public_ping}) [${public_country}]" "$CLR_ACCENT" "$CLR_ACCENT"
  dashboard_line "$(tr_text "Хостер" "Provider")" "${public_org}" "$CLR_MUTED" "$CLR_ACCENT"
  dashboard_gap

  dashboard_section "$(tr_text "ЖЕЛЕЗО" "HARDWARE")" "$CLR_WARN"
  dashboard_line "$(tr_text "CPU Модель" "CPU Model")" "$cpu_model" "$CLR_MUTED" "$CLR_WARN"
  dashboard_line "$(tr_text "Загрузка CPU" "CPU Load")" "$(dashboard_bar "$cpu_percent") ${cpu_percent}% (${cpu_cores} vCore)" "$(dashboard_metric_color "$cpu_percent" 70 90)" "$CLR_WARN"
  dashboard_line "$(tr_text "Память (RAM)" "Memory (RAM)")" "$(dashboard_bar "$mem_percent") ${mem_percent}% (${mem_used} / ${mem_total})" "$(dashboard_metric_color "$mem_percent" 75 90)" "$CLR_WARN"
  dashboard_line "$(tr_text "Диск (HDD)" "Disk (HDD)")" "$(dashboard_bar "$disk_percent") ${disk_percent}% (${disk_used}/${disk_total})" "$(dashboard_metric_color "$disk_percent" 70 85)" "$CLR_WARN"
  dashboard_gap

  dashboard_section "STATUS" "$CLR_OK"
  if (( has_panel == 1 )); then
    dashboard_line "Remnawave" "$panel_status" "$CLR_OK" "$CLR_OK"
    status_rows=$((status_rows + 1))
  fi
  if (( has_bot == 1 )); then
    dashboard_line "Bedolaga Bot" "$bot_status" "$bot_status_color" "$CLR_OK"
    status_rows=$((status_rows + 1))
  fi
  if (( has_cabinet == 1 )); then
    dashboard_line "Bedolaga Cabinet" "$cabinet_status" "$cabinet_status_color" "$CLR_OK"
    status_rows=$((status_rows + 1))
  fi
  if (( has_caddy == 1 )); then
    dashboard_line "Web-Server" "$caddy_status" "$CLR_MUTED" "$CLR_OK"
    status_rows=$((status_rows + 1))
  fi
  if [[ "$capacity_label" != n/a* ]]; then
    dashboard_line "$(tr_text "Вместимость юзеров" "User capacity")" "$capacity_label" "$CLR_MUTED" "$CLR_OK"
    status_rows=$((status_rows + 1))
  fi
  if (( status_rows == 0 )); then
    dashboard_line "$(tr_text "Сервисы" "Services")" "$(tr_text "не найдены" "not found")" "$CLR_WARN" "$CLR_OK"
  fi
  dashboard_gap

  if (( has_backup_section == 1 )); then
    dashboard_section "BACKUP" "$CLR_WARN"
    if [[ -x /usr/local/bin/panel-backup.sh || -f /etc/panel-backup.env ]]; then
      dashboard_line "$(tr_text "Скрипт / конфиг" "Script / config")" "${backup_script_state} / ${config_state}" "$CLR_ACCENT" "$CLR_WARN"
    fi
    if (( has_panel_backup == 1 )); then
      dashboard_line "$(tr_text "Панель timer" "Panel timer")" "${panel_timer_state} / ${panel_timer_enabled}" "$(state_color "$panel_timer_state")" "$CLR_WARN"
      dashboard_line "$(tr_text "Панель расписание" "Panel schedule")" "$(format_schedule_label "$panel_schedule")" "$CLR_ACCENT" "$CLR_WARN"
      dashboard_line "$(tr_text "Панель следующий" "Panel next")" "$panel_next" "$CLR_MUTED" "$CLR_WARN"
    fi
    if (( has_bedolaga_backup == 1 )); then
      dashboard_line "$(tr_text "Bedolaga timer" "Bedolaga timer")" "${bedolaga_timer_state} / ${bedolaga_timer_enabled}" "$(state_color "$bedolaga_timer_state")" "$CLR_WARN"
      dashboard_line "$(tr_text "Bedolaga распис." "Bedolaga schedule")" "$(format_schedule_label "$bedolaga_schedule")" "$CLR_ACCENT" "$CLR_WARN"
      dashboard_line "$(tr_text "Bedolaga след." "Bedolaga next")" "$bedolaga_next" "$CLR_MUTED" "$CLR_WARN"
    fi
    if (( has_latest_backup == 1 )); then
      dashboard_line "$(tr_text "Последний backup" "Latest backup")" "$latest_label" "$CLR_ACCENT" "$CLR_WARN"
      dashboard_line "$(tr_text "Возраст backup" "Backup age")" "$backup_age_label" "$backup_age_color" "$CLR_WARN"
    fi
    if (( has_tg_config == 1 )); then
      dashboard_line "Telegram" "$tg_state" "$tg_color" "$CLR_WARN"
    fi
    if (( has_encrypt_enabled == 1 )); then
      dashboard_line "$(tr_text "Шифрование" "Encryption")" "$encrypt_state" "$encrypt_color" "$CLR_WARN"
    fi
    dashboard_gap
  fi

  dashboard_section "WIDGETS" "$CLR_ACCENT"
  dashboard_line "USD/RUB" "$usd_rub_label" "$usd_rub_color" "$CLR_ACCENT"
  paint "$CLR_TITLE" "╚════════════════════════════════════════════════════════════"
  paint "$CLR_MUTED" "  $(tr_text "Навигация: цифра = открыть, b/back = назад или выход." "Navigation: number = open, b/back = back or exit.")"
  echo
}
