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

  clear
  paint "$CLR_TITLE" "============================================================"
  paint "$CLR_ACCENT" "  ${title}"
  if [[ -n "$subtitle" ]]; then
    paint "$CLR_MUTED" "  ${subtitle}"
  fi
  paint "$CLR_TITLE" "============================================================"
  echo
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
  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_backup" ]]; then
    latest_label="$(basename "$latest_backup")"
    backup_age_sec="$(( $(date +%s) - $(date -r "$latest_backup" +%s) ))"
    backup_age_h="$(( backup_age_sec / 3600 ))"
  else
    latest_label="$(tr_text "нет" "none")"
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

  service_show="$($SUDO systemctl show panel-backup.service -p Result -p ExecMainStatus -p ExecMainExitTimestamp 2>/dev/null || true)"
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
  next_run_raw="$($SUDO systemctl show panel-backup.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)"
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
  paint "$CLR_ACCENT" "  ${title}"
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
  paint_labeled_value "$(tr_text "Таймер:" "Timer:")" "${timer_state}" "$timer_color"
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
  paint "$CLR_TITLE" "============================================================"
  paint "$CLR_MUTED" "$(tr_text "Выберите действие." "Select an action.")"
  echo
}
