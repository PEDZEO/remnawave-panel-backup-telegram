#!/usr/bin/env bash
# Runtime backup/restore/status operations for manager.sh

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
    from_path="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  fi

  if [[ -z "$from_path" || ! -f "$from_path" ]]; then
    echo "[restore] Backup archive not found. Set BACKUP_FILE or BACKUP_URL." >&2
    return 1
  fi

  IFS=',' read -r -a only_list <<< "$RESTORE_ONLY"
  for item in "${only_list[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] || continue
    only_args+=("--only" "$item")
  done

  echo "[restore] Using archive: $from_path"
  restore_cmd=(/usr/local/bin/panel-restore.sh --from "$from_path" "${only_args[@]}")

  if [[ "$RESTORE_NO_RESTART" == "1" ]]; then
    restore_cmd+=(--no-restart)
  fi

  if [[ -n "$SUDO" ]]; then
    if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
      restore_cmd=("$SUDO" env "BACKUP_PASSWORD=${BACKUP_PASSWORD}" "${restore_cmd[@]}")
    else
      restore_cmd=("$SUDO" "${restore_cmd[@]}")
    fi
  fi

  "${restore_cmd[@]}"
}

sync_runtime_scripts() {
  local backup_fetched=0
  local restore_fetched=0
  local can_continue=1

  paint "$CLR_ACCENT" "$(tr_text "Обновляю runtime-скрипты backup/restore..." "Updating backup/restore runtime scripts...")"
  if fetch "scripts/bin/panel-backup.sh" "$TMP_DIR/panel-backup.sh"; then
    backup_fetched=1
  else
    paint "$CLR_WARN" "$(tr_text "Не удалось скачать panel-backup.sh, пробую использовать локально установленный файл." "Failed to download panel-backup.sh, trying local installed file.")"
  fi

  if fetch "scripts/bin/panel-restore.sh" "$TMP_DIR/panel-restore.sh"; then
    restore_fetched=1
  else
    paint "$CLR_WARN" "$(tr_text "Не удалось скачать panel-restore.sh, пробую использовать локально установленный файл." "Failed to download panel-restore.sh, trying local installed file.")"
  fi

  if (( backup_fetched == 1 )); then
    $SUDO install -m 755 "$TMP_DIR/panel-backup.sh" /usr/local/bin/panel-backup.sh
  elif [[ ! -x /usr/local/bin/panel-backup.sh ]]; then
    paint "$CLR_DANGER" "$(tr_text "Ошибка: panel-backup.sh недоступен (скачивание не удалось и локальный файл не найден)." "Error: panel-backup.sh unavailable (download failed and local file not found).")"
    can_continue=0
  fi

  if (( restore_fetched == 1 )); then
    $SUDO install -m 755 "$TMP_DIR/panel-restore.sh" /usr/local/bin/panel-restore.sh
  elif [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
    paint "$CLR_DANGER" "$(tr_text "Ошибка: panel-restore.sh недоступен (скачивание не удалось и локальный файл не найден)." "Error: panel-restore.sh unavailable (download failed and local file not found).")"
    can_continue=0
  fi

  if (( can_continue == 0 )); then
    paint "$CLR_DANGER" "$(tr_text "Проверьте доступ к raw.githubusercontent.com или переустановите backup-скрипты вручную." "Check access to raw.githubusercontent.com or reinstall backup scripts manually.")"
    return 1
  fi
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
  local include_quoted=""
  local backup_log="/tmp/panel-backup-last.log"

  if ! sync_runtime_scripts; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось обновить runtime-скрипты backup/restore." "Failed to update backup/restore runtime scripts.")"
    return 1
  fi
  normalize_env_file_format

  if [[ ! -x /usr/local/bin/panel-backup.sh ]]; then
    install_files
    write_env
    $SUDO systemctl daemon-reload
  fi

  backup_cmd=(/usr/local/bin/panel-backup.sh)
  if [[ -n "$SUDO" ]]; then
    if [[ -n "${BACKUP_INCLUDE:-}" ]]; then
      include_quoted="$(printf '%q' "${BACKUP_INCLUDE}")"
      backup_cmd=("$SUDO" bash -lc "BACKUP_INCLUDE_OVERRIDE=${include_quoted} /usr/local/bin/panel-backup.sh")
    else
      backup_cmd=("$SUDO" "${backup_cmd[@]}")
    fi
  elif [[ -n "${BACKUP_INCLUDE:-}" ]]; then
    backup_cmd=(env "BACKUP_INCLUDE_OVERRIDE=${BACKUP_INCLUDE}" /usr/local/bin/panel-backup.sh)
  fi

  : > "$backup_log"
  if "${backup_cmd[@]}" > >(tee -a "$backup_log") 2> >(tee -a "$backup_log" >&2); then
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Подробный лог ошибки (хвост):" "Detailed error log (tail):")"
  tail -n 40 "$backup_log" 2>/dev/null || true
  return 1
}

humanize_systemd_state() {
  local value="${1:-unknown}"
  case "$value" in
    loaded) echo "$(tr_text "загружен" "loaded")" ;;
    enabled) echo "$(tr_text "включен" "enabled")" ;;
    disabled) echo "$(tr_text "выключен" "disabled")" ;;
    active) echo "$(tr_text "активен" "active")" ;;
    inactive) echo "$(tr_text "неактивен" "inactive")" ;;
    waiting) echo "$(tr_text "ожидание" "waiting")" ;;
    running) echo "$(tr_text "выполняется" "running")" ;;
    exited) echo "$(tr_text "завершен" "exited")" ;;
    failed) echo "$(tr_text "ошибка" "failed")" ;;
    dead) echo "$(tr_text "завершен" "completed")" ;;
    success) echo "$(tr_text "успешно" "success")" ;;
    exit-code) echo "$(tr_text "код завершения" "exit code")" ;;
    n/a|"") echo "n/a" ;;
    *) echo "$value" ;;
  esac
}

show_status() {
  local panel_timer_show=""
  local bedolaga_timer_show=""
  local panel_service_show=""
  local bedolaga_service_show=""
  local latest_backup=""
  local latest_backup_time=""
  local latest_backup_size=""
  local panel_timer_load=""
  local panel_timer_unit_file=""
  local panel_timer_active=""
  local panel_timer_sub=""
  local panel_timer_next=""
  local panel_timer_last=""
  local bedolaga_timer_load=""
  local bedolaga_timer_unit_file=""
  local bedolaga_timer_active=""
  local bedolaga_timer_sub=""
  local bedolaga_timer_next=""
  local bedolaga_timer_last=""
  local panel_service_active=""
  local panel_service_sub=""
  local panel_service_result=""
  local panel_service_status=""
  local panel_service_started=""
  local panel_service_finished=""
  local bedolaga_service_active=""
  local bedolaga_service_sub=""
  local bedolaga_service_result=""
  local bedolaga_service_status=""
  local bedolaga_service_started=""
  local bedolaga_service_finished=""
  local schedule_now=""
  local panel_present=0
  local bedolaga_present=0
  local backup_installed="$(tr_text "нет" "no")"
  local restore_installed="$(tr_text "нет" "no")"
  local config_present="$(tr_text "нет" "no")"
  local panel_service_execution=""
  local bedolaga_service_execution=""

  draw_header "$(tr_text "Статус panel backup" "Panel backup status")"

  if [[ -x /usr/local/bin/panel-backup.sh ]]; then
    backup_installed="$(tr_text "да" "yes")"
  fi

  if [[ -x /usr/local/bin/panel-restore.sh ]]; then
    restore_installed="$(tr_text "да" "yes")"
  fi

  if [[ -f /etc/panel-backup.env ]]; then
    config_present="$(tr_text "да" "yes")"
  fi
  has_panel_project && panel_present=1
  has_bedolaga_project && bedolaga_present=1

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Установка" "Installation")"
  paint "$CLR_MUTED" "  $(tr_text "Backup-скрипт:" "Backup script:") ${backup_installed} (/usr/local/bin/panel-backup.sh)"
  paint "$CLR_MUTED" "  $(tr_text "Restore-скрипт:" "Restore script:") ${restore_installed} (/usr/local/bin/panel-restore.sh)"
  paint "$CLR_MUTED" "  $(tr_text "Файл конфигурации:" "Config file:") ${config_present} (/etc/panel-backup.env)"

  if (( panel_present == 1 )); then
    panel_timer_show="$($SUDO systemctl show panel-backup-panel.timer \
      -p LoadState -p UnitFileState -p ActiveState -p SubState \
      -p NextElapseUSecRealtime -p LastTriggerUSecRealtime 2>/dev/null || true)"
    if [[ -n "$panel_timer_show" ]]; then
      panel_timer_load="$(echo "$panel_timer_show" | awk -F= '/^LoadState=/{print $2}')"
      panel_timer_unit_file="$(echo "$panel_timer_show" | awk -F= '/^UnitFileState=/{print $2}')"
      panel_timer_active="$(echo "$panel_timer_show" | awk -F= '/^ActiveState=/{print $2}')"
      panel_timer_sub="$(echo "$panel_timer_show" | awk -F= '/^SubState=/{print $2}')"
      panel_timer_next="$(echo "$panel_timer_show" | awk -F= '/^NextElapseUSecRealtime=/{print $2}')"
      panel_timer_last="$(echo "$panel_timer_show" | awk -F= '/^LastTriggerUSecRealtime=/{print $2}')"
      print_separator
      paint "$CLR_TITLE" "$(tr_text "Таймер панели" "Panel timer")"
      paint "$CLR_MUTED" "  $(tr_text "Состояние unit:" "Unit state:") $(humanize_systemd_state "${panel_timer_load:-unknown}")"
      paint "$CLR_MUTED" "  $(tr_text "Автозапуск:" "Autostart:") $(humanize_systemd_state "${panel_timer_unit_file:-unknown}")"
      paint "$CLR_MUTED" "  $(tr_text "Статус:" "Status:") $(humanize_systemd_state "${panel_timer_active:-unknown}") / $(humanize_systemd_state "${panel_timer_sub:-unknown}")"
      paint "$CLR_MUTED" "  $(tr_text "Следующий запуск:" "Next run:") ${panel_timer_next:-n/a}"
      paint "$CLR_MUTED" "  $(tr_text "Последний запуск:" "Last run:") ${panel_timer_last:-n/a}"
    fi
  fi

  if (( bedolaga_present == 1 )); then
    bedolaga_timer_show="$($SUDO systemctl show panel-backup-bedolaga.timer \
      -p LoadState -p UnitFileState -p ActiveState -p SubState \
      -p NextElapseUSecRealtime -p LastTriggerUSecRealtime 2>/dev/null || true)"
    if [[ -n "$bedolaga_timer_show" ]]; then
      bedolaga_timer_load="$(echo "$bedolaga_timer_show" | awk -F= '/^LoadState=/{print $2}')"
      bedolaga_timer_unit_file="$(echo "$bedolaga_timer_show" | awk -F= '/^UnitFileState=/{print $2}')"
      bedolaga_timer_active="$(echo "$bedolaga_timer_show" | awk -F= '/^ActiveState=/{print $2}')"
      bedolaga_timer_sub="$(echo "$bedolaga_timer_show" | awk -F= '/^SubState=/{print $2}')"
      bedolaga_timer_next="$(echo "$bedolaga_timer_show" | awk -F= '/^NextElapseUSecRealtime=/{print $2}')"
      bedolaga_timer_last="$(echo "$bedolaga_timer_show" | awk -F= '/^LastTriggerUSecRealtime=/{print $2}')"
      print_separator
      paint "$CLR_TITLE" "$(tr_text "Таймер Bedolaga" "Bedolaga timer")"
      paint "$CLR_MUTED" "  $(tr_text "Состояние unit:" "Unit state:") $(humanize_systemd_state "${bedolaga_timer_load:-unknown}")"
      paint "$CLR_MUTED" "  $(tr_text "Автозапуск:" "Autostart:") $(humanize_systemd_state "${bedolaga_timer_unit_file:-unknown}")"
      paint "$CLR_MUTED" "  $(tr_text "Статус:" "Status:") $(humanize_systemd_state "${bedolaga_timer_active:-unknown}") / $(humanize_systemd_state "${bedolaga_timer_sub:-unknown}")"
      paint "$CLR_MUTED" "  $(tr_text "Следующий запуск:" "Next run:") ${bedolaga_timer_next:-n/a}"
      paint "$CLR_MUTED" "  $(tr_text "Последний запуск:" "Last run:") ${bedolaga_timer_last:-n/a}"
    fi
  fi
  if (( panel_present == 1 )); then
    schedule_now="$(get_timer_calendar_for_unit "panel-backup-panel.timer" || true)"
    print_separator
    paint "$CLR_MUTED" "  $(tr_text "Периодичность панели:" "Panel schedule:") $(format_schedule_label "$schedule_now")"
  fi
  if (( bedolaga_present == 1 )); then
    schedule_now="$(get_timer_calendar_for_unit "panel-backup-bedolaga.timer" || true)"
    paint "$CLR_MUTED" "  $(tr_text "Периодичность Bedolaga:" "Bedolaga schedule:") $(format_schedule_label "$schedule_now")"
  fi

  if (( panel_present == 1 )); then
  panel_service_show="$($SUDO systemctl show panel-backup-panel.service \
    -p ActiveState -p SubState -p Result -p ExecMainStatus \
    -p ExecMainStartTimestamp -p ExecMainExitTimestamp 2>/dev/null || true)"
  if [[ -n "$panel_service_show" ]]; then
    panel_service_active="$(echo "$panel_service_show" | awk -F= '/^ActiveState=/{print $2}')"
    panel_service_sub="$(echo "$panel_service_show" | awk -F= '/^SubState=/{print $2}')"
    panel_service_result="$(echo "$panel_service_show" | awk -F= '/^Result=/{print $2}')"
    panel_service_status="$(echo "$panel_service_show" | awk -F= '/^ExecMainStatus=/{print $2}')"
    panel_service_started="$(echo "$panel_service_show" | awk -F= '/^ExecMainStartTimestamp=/{print $2}')"
    panel_service_finished="$(echo "$panel_service_show" | awk -F= '/^ExecMainExitTimestamp=/{print $2}')"
    print_separator
    if [[ "${panel_service_result:-}" == "success" && "${panel_service_status:-}" == "0" ]]; then
      panel_service_execution="$(tr_text "успешно" "successful")"
    else
      panel_service_execution="$(humanize_systemd_state "${panel_service_result:-unknown}")"
    fi
    paint "$CLR_TITLE" "$(tr_text "Сервис backup панели" "Panel backup service")"
    paint "$CLR_MUTED" "  $(tr_text "Статус:" "Status:") $(humanize_systemd_state "${panel_service_active:-unknown}") / $(humanize_systemd_state "${panel_service_sub:-unknown}")"
    paint "$CLR_MUTED" "  $(tr_text "Результат:" "Result:") ${panel_service_execution}"
    paint "$CLR_MUTED" "  $(tr_text "Код завершения:" "Exit code:") ${panel_service_status:-unknown}"
    paint "$CLR_MUTED" "  $(tr_text "Последний старт:" "Last start:") ${panel_service_started:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Последнее завершение:" "Last finish:") ${panel_service_finished:-n/a}"
  else
    print_separator
    paint "$CLR_WARN" "$(tr_text "Сервис backup панели: недоступен" "Panel backup service: not available")"
  fi
  fi

  if (( bedolaga_present == 1 )); then
  bedolaga_service_show="$($SUDO systemctl show panel-backup-bedolaga.service \
    -p ActiveState -p SubState -p Result -p ExecMainStatus \
    -p ExecMainStartTimestamp -p ExecMainExitTimestamp 2>/dev/null || true)"
  if [[ -n "$bedolaga_service_show" ]]; then
    bedolaga_service_active="$(echo "$bedolaga_service_show" | awk -F= '/^ActiveState=/{print $2}')"
    bedolaga_service_sub="$(echo "$bedolaga_service_show" | awk -F= '/^SubState=/{print $2}')"
    bedolaga_service_result="$(echo "$bedolaga_service_show" | awk -F= '/^Result=/{print $2}')"
    bedolaga_service_status="$(echo "$bedolaga_service_show" | awk -F= '/^ExecMainStatus=/{print $2}')"
    bedolaga_service_started="$(echo "$bedolaga_service_show" | awk -F= '/^ExecMainStartTimestamp=/{print $2}')"
    bedolaga_service_finished="$(echo "$bedolaga_service_show" | awk -F= '/^ExecMainExitTimestamp=/{print $2}')"
    print_separator
    if [[ "${bedolaga_service_result:-}" == "success" && "${bedolaga_service_status:-}" == "0" ]]; then
      bedolaga_service_execution="$(tr_text "успешно" "successful")"
    else
      bedolaga_service_execution="$(humanize_systemd_state "${bedolaga_service_result:-unknown}")"
    fi
    paint "$CLR_TITLE" "$(tr_text "Сервис backup Bedolaga" "Bedolaga backup service")"
    paint "$CLR_MUTED" "  $(tr_text "Статус:" "Status:") $(humanize_systemd_state "${bedolaga_service_active:-unknown}") / $(humanize_systemd_state "${bedolaga_service_sub:-unknown}")"
    paint "$CLR_MUTED" "  $(tr_text "Результат:" "Result:") ${bedolaga_service_execution}"
    paint "$CLR_MUTED" "  $(tr_text "Код завершения:" "Exit code:") ${bedolaga_service_status:-unknown}"
    paint "$CLR_MUTED" "  $(tr_text "Последний старт:" "Last start:") ${bedolaga_service_started:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Последнее завершение:" "Last finish:") ${bedolaga_service_finished:-n/a}"
  else
    print_separator
    paint "$CLR_WARN" "$(tr_text "Сервис backup Bedolaga: недоступен" "Bedolaga backup service: not available")"
  fi
  fi

  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  print_separator
  paint "$CLR_TITLE" "$(tr_text "Последний backup" "Latest backup")"
  if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
    latest_backup_time="$(date -u -r "$latest_backup" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || stat -c '%y' "$latest_backup" 2>/dev/null || echo n/a)"
    latest_backup_size="$(du -h "$latest_backup" 2>/dev/null | awk '{print $1}' || echo n/a)"
    paint "$CLR_MUTED" "  $(tr_text "Файл:" "File:") $(basename "$latest_backup")"
    paint "$CLR_MUTED" "  $(tr_text "Дата/время:" "Date/time:") ${latest_backup_time}"
    paint "$CLR_MUTED" "  $(tr_text "Размер:" "Size:") ${latest_backup_size}"
  else
    paint "$CLR_WARN" "$(tr_text "Архивы backup не найдены в /var/backups/panel." "No backup archives found in /var/backups/panel.")"
  fi

  load_existing_env_defaults
  print_separator
  paint "$CLR_TITLE" "$(tr_text "Интеграции" "Integrations")"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_ADMIN_ID" ]]; then
    paint "$CLR_MUTED" "  Telegram: $(tr_text "настроен" "configured")"
  else
    paint "$CLR_WARN" "  Telegram: $(tr_text "настроен не полностью" "not fully configured")"
  fi
  if [[ "${BACKUP_ENCRYPT:-0}" == "1" ]]; then
    if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
      paint "$CLR_MUTED" "  $(tr_text "Шифрование backup:" "Backup encryption:") $(tr_text "включено (GPG)" "enabled (GPG)")"
    else
      paint "$CLR_WARN" "  $(tr_text "Шифрование backup:" "Backup encryption:") $(tr_text "включено, но пароль не задан" "enabled, but password is not set")"
    fi
  else
    paint "$CLR_MUTED" "  $(tr_text "Шифрование backup:" "Backup encryption:") $(tr_text "выключено" "disabled")"
  fi
  paint "$CLR_MUTED" "  $(tr_text "Состав backup:" "Backup scope:") ${BACKUP_INCLUDE:-all}"
  if (( panel_present == 1 )); then
    paint "$CLR_MUTED" "  $(tr_text "Путь Remnawave:" "Remnawave path:") ${REMNAWAVE_DIR:-not-detected}"
  fi
  if (( bedolaga_present == 1 )); then
    paint "$CLR_MUTED" "  $(tr_text "Путь Bedolaga бота:" "Bedolaga bot path:") ${BEDOLAGA_BOT_DIR:-not-detected}"
    paint "$CLR_MUTED" "  $(tr_text "Путь Bedolaga кабинета:" "Bedolaga cabinet path:") ${BEDOLAGA_CABINET_DIR:-not-detected}"
  fi
  print_separator
}

run_doctor_checks() {
  local fail_count=0
  local warn_count=0
  local latest_backup=""
  local checksum_path=""
  local root_free_kb=0
  local backup_root_free_kb=0
  local include_raw=""
  local normalized_include=""
  local item=""
  local include_ok=1
  local -a include_items=()

  doctor_ok() {
    paint "$CLR_OK" "  [OK] $*"
  }

  doctor_warn() {
    warn_count=$((warn_count + 1))
    paint "$CLR_WARN" "  [WARN] $*"
  }

  doctor_fail() {
    fail_count=$((fail_count + 1))
    paint "$CLR_DANGER" "  [FAIL] $*"
  }

  draw_header "$(tr_text "Doctor: проверка backup-системы" "Doctor: backup system check")"
  load_existing_env_defaults

  paint "$CLR_TITLE" "$(tr_text "Файлы" "Files")"
  [[ -x /usr/local/bin/panel-backup.sh ]] && doctor_ok "/usr/local/bin/panel-backup.sh" || doctor_fail "$(tr_text "Не найден executable backup-скрипт" "Backup script executable is missing")"
  [[ -x /usr/local/bin/panel-restore.sh ]] && doctor_ok "/usr/local/bin/panel-restore.sh" || doctor_fail "$(tr_text "Не найден executable restore-скрипт" "Restore script executable is missing")"
  [[ -f /etc/panel-backup.env ]] && doctor_ok "/etc/panel-backup.env" || doctor_warn "$(tr_text "Конфиг /etc/panel-backup.env не найден" "Config /etc/panel-backup.env was not found")"

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Зависимости" "Dependencies")"
  for item in docker tar curl split du stat find awk grep sed flock tail; do
    command -v "$item" >/dev/null 2>&1 && doctor_ok "$item" || doctor_fail "$(tr_text "Не найдена команда" "Missing command"): $item"
  done
  if [[ "${BACKUP_ENCRYPT:-0}" == "1" ]]; then
    command -v gpg >/dev/null 2>&1 && doctor_ok "gpg" || doctor_fail "$(tr_text "Шифрование включено, но gpg не найден" "Encryption is enabled, but gpg is missing")"
  fi
  command -v sha256sum >/dev/null 2>&1 && doctor_ok "sha256sum" || doctor_warn "$(tr_text "sha256sum не найден, checksum не будет создаваться/проверяться" "sha256sum is missing, checksums cannot be created/verified")"
  if command -v docker >/dev/null 2>&1; then
    $SUDO docker compose version >/dev/null 2>&1 && doctor_ok "docker compose" || doctor_fail "$(tr_text "docker compose недоступен" "docker compose is unavailable")"
  fi

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Конфигурация" "Configuration")"
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_ADMIN_ID:-}" ]]; then
    doctor_ok "Telegram"
  elif [[ -n "${TELEGRAM_BOT_TOKEN:-}" || -n "${TELEGRAM_ADMIN_ID:-}" ]]; then
    doctor_fail "$(tr_text "Telegram настроен частично: нужен и токен, и chat_id" "Telegram is partially configured: both token and chat_id are required")"
  else
    doctor_warn "$(tr_text "Telegram не настроен, backup останется только локально" "Telegram is not configured, backup will remain local only")"
  fi
  if [[ "${BACKUP_ENCRYPT:-0}" == "1" ]]; then
    [[ -n "${BACKUP_PASSWORD:-}" ]] && doctor_ok "$(tr_text "Шифрование включено" "Encryption enabled")" || doctor_fail "$(tr_text "Шифрование включено, но BACKUP_PASSWORD пустой" "Encryption is enabled, but BACKUP_PASSWORD is empty")"
  else
    doctor_warn "$(tr_text "Шифрование backup выключено" "Backup encryption is disabled")"
  fi

  include_raw="${BACKUP_INCLUDE:-all}"
  normalized_include="$(normalize_component_list "$include_raw")"
  if [[ -z "$normalized_include" ]]; then
    doctor_fail "$(tr_text "BACKUP_INCLUDE пустой" "BACKUP_INCLUDE is empty")"
  else
    include_ok=1
    IFS=',' read -r -a include_items <<< "$normalized_include"
    for item in "${include_items[@]}"; do
      if [[ -z "$item" ]] || ! is_allowed_component_for_scope "global" "$item"; then
        doctor_fail "$(tr_text "Неизвестный компонент BACKUP_INCLUDE" "Unknown BACKUP_INCLUDE component"): ${item:-empty}"
        include_ok=0
      fi
    done
    (( include_ok == 1 )) && doctor_ok "BACKUP_INCLUDE=${normalized_include}"
  fi

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Проекты" "Projects")"
  has_panel_project && doctor_ok "$(tr_text "Remnawave найден" "Remnawave detected"): ${REMNAWAVE_DIR:-n/a}" || doctor_warn "$(tr_text "Remnawave не найден" "Remnawave was not detected")"
  has_bedolaga_project && doctor_ok "$(tr_text "Bedolaga найден" "Bedolaga detected"): ${BEDOLAGA_BOT_DIR:-n/a} / ${BEDOLAGA_CABINET_DIR:-n/a}" || doctor_warn "$(tr_text "Bedolaga не найден" "Bedolaga was not detected")"

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Таймеры" "Timers")"
  for item in panel-backup-panel.timer panel-backup-bedolaga.timer; do
    if $SUDO systemctl list-unit-files "$item" >/dev/null 2>&1; then
      doctor_ok "$item: $(systemctl_active_state "$item")"
    else
      doctor_warn "$(tr_text "Таймер не установлен" "Timer is not installed"): $item"
    fi
  done

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Архивы и диск" "Backups and disk")"
  latest_backup="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
    doctor_ok "$(tr_text "Последний архив" "Latest archive"): $(basename "$latest_backup")"
    checksum_path="${latest_backup}.sha256"
    if [[ -f "$checksum_path" ]]; then
      if command -v sha256sum >/dev/null 2>&1 && (cd "$(dirname "$latest_backup")" && sha256sum -c "$(basename "$checksum_path")" >/dev/null 2>&1); then
        doctor_ok "$(tr_text "Checksum последнего архива валиден" "Latest archive checksum is valid")"
      else
        doctor_fail "$(tr_text "Checksum последнего архива не прошёл проверку" "Latest archive checksum verification failed")"
      fi
    else
      doctor_warn "$(tr_text "Для последнего архива нет .sha256" "Latest archive has no .sha256 file")"
    fi
  else
    doctor_warn "$(tr_text "Архивы backup не найдены" "No backup archives found")"
  fi
  root_free_kb="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4+0}' || echo 0)"
  backup_root_free_kb="$(df -Pk /var/backups 2>/dev/null | awk 'NR==2 {print $4+0}' || echo 0)"
  (( root_free_kb > 1048576 )) && doctor_ok "$(tr_text "Свободно на / больше 1 GB" "Root filesystem has more than 1 GB free")" || doctor_warn "$(tr_text "На / меньше 1 GB свободного места" "Root filesystem has less than 1 GB free")"
  (( backup_root_free_kb > 1048576 )) && doctor_ok "$(tr_text "Свободно в /var/backups больше 1 GB" "/var/backups has more than 1 GB free")" || doctor_warn "$(tr_text "В /var/backups меньше 1 GB свободного места" "/var/backups has less than 1 GB free")"

  print_separator
  if (( fail_count > 0 )); then
    paint "$CLR_DANGER" "$(tr_text "Doctor завершён: есть ошибки" "Doctor finished: failures found") (${fail_count} fail, ${warn_count} warn)"
    return 1
  fi
  if (( warn_count > 0 )); then
    paint "$CLR_WARN" "$(tr_text "Doctor завершён: есть предупреждения" "Doctor finished: warnings found") (${warn_count} warn)"
    return 0
  fi
  paint "$CLR_OK" "$(tr_text "Doctor завершён: всё в порядке" "Doctor finished: all checks passed")"
  return 0
}

server_check_public_ip() {
  local endpoint=""
  local ip=""

  for endpoint in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
    ip="$(curl -fsSL --connect-timeout 3 --max-time 6 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$ip" =~ ^[0-9A-Fa-f:]+$ ]]; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

server_check_ipinfo_line() {
  local json=""
  local city=""
  local country=""
  local org=""

  json="$(curl -fsSL --connect-timeout 3 --max-time 6 https://ipinfo.io/json 2>/dev/null || true)"
  [[ -n "$json" ]] || return 1
  city="$(printf '%s' "$json" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  country="$(printf '%s' "$json" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  org="$(printf '%s' "$json" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  printf '%s' "${org:-n/a}${city:+ · ${city}}${country:+ [${country}]}"
}

server_check_reverse_ipv4() {
  local ip="$1"
  local a=""
  local b=""
  local c=""
  local d=""

  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS='.' read -r a b c d <<< "$ip"
  printf '%s.%s.%s.%s' "$d" "$c" "$b" "$a"
}

server_check_dns_query() {
  local host="$1"

  if ! command -v getent >/dev/null 2>&1; then
    return 1
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 4 getent ahosts "$host" 2>/dev/null | awk 'NR==1 {print $1}'
  else
    getent ahosts "$host" 2>/dev/null | awk 'NR==1 {print $1}'
  fi
}

server_check_dnsbl_query() {
  local host="$1"

  if ! command -v getent >/dev/null 2>&1; then
    return 1
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 4 getent hosts "$host" >/dev/null 2>&1
  else
    getent hosts "$host" >/dev/null 2>&1
  fi
}

server_check_http_probe() {
  local label="$1"
  local url="$2"
  local result=""
  local code=""
  local connect_time=""
  local total_time=""
  local color="$CLR_DANGER"
  local state=""

  result="$(curl -L -s -o /dev/null -w '%{http_code}|%{time_connect}|%{time_total}' --connect-timeout 5 --max-time 12 "$url" 2>/dev/null || true)"
  IFS='|' read -r code connect_time total_time <<< "$result"
  if [[ -n "$code" && "$code" != "000" ]]; then
    if [[ "$code" =~ ^[0-9]+$ && "$code" -lt 500 ]]; then
      color="$CLR_OK"
      state="$(tr_text "доступен" "reachable")"
    else
      color="$CLR_WARN"
      state="$(tr_text "ответ с ошибкой" "error response")"
    fi
    paint "$color" "  ${label}: ${state} HTTP ${code} · ${total_time:-n/a}s"
  else
    paint "$CLR_DANGER" "  ${label}: $(tr_text "нет доступа/таймаут" "unreachable/timeout")"
  fi
}

server_check_download_speed() {
  local bytes="${1:-10000000}"
  local result=""
  local speed_bps=""
  local total_time=""
  local downloaded=""
  local mbps=""
  local mibps=""

  result="$(curl -L -s -o /dev/null -w '%{speed_download}|%{time_total}|%{size_download}' --connect-timeout 5 --max-time 30 "https://speed.cloudflare.com/__down?bytes=${bytes}" 2>/dev/null || true)"
  IFS='|' read -r speed_bps total_time downloaded <<< "$result"
  if [[ "$speed_bps" =~ ^[0-9]+([.][0-9]+)?$ && "$speed_bps" != "0" ]]; then
    mbps="$(awk -v bps="$speed_bps" 'BEGIN { printf "%.1f", (bps * 8) / 1000000 }')"
    mibps="$(awk -v bps="$speed_bps" 'BEGIN { printf "%.1f", bps / 1048576 }')"
    paint "$CLR_OK" "  $(tr_text "Download:" "Download:") ${mbps} Mbps (${mibps} MiB/s) · ${total_time:-n/a}s · ${downloaded:-0} bytes"
    return 0
  fi
  paint "$CLR_WARN" "  $(tr_text "Download:" "Download:") $(tr_text "не удалось измерить" "failed to measure")"
  return 1
}

run_server_checks() {
  local ip=""
  local ipinfo=""
  local rev_ip=""
  local listed_count=0
  local zone=""
  local lookup=""
  local speed_rc=0
  local -a dns_hosts=(
    "google.com"
    "youtube.com"
    "api.telegram.org"
    "github.com"
    "registry-1.docker.io"
    "raw.githubusercontent.com"
  )
  local -a dnsbl_zones=(
    "zen.spamhaus.org"
    "bl.spamcop.net"
    "dnsbl.sorbs.net"
    "all.s5h.net"
  )

  draw_header "$(tr_text "Проверка сервера" "Server checks")"
  paint "$CLR_MUTED" "$(tr_text "Проверка дает быстрый сигнал по сети и репутации IP. DNSBL не гарантирует, что IP полностью чистый для всех сервисов." "This gives a quick network and IP reputation signal. DNSBL does not guarantee the IP is clean for every service.")"
  print_separator

  if ! command -v curl >/dev/null 2>&1; then
    paint "$CLR_DANGER" "curl $(tr_text "не установлен: проверка сети недоступна." "is not installed: network checks are unavailable.")"
    return 1
  fi

  paint "$CLR_TITLE" "$(tr_text "Публичный IP" "Public IP")"
  if ip="$(server_check_public_ip)"; then
    paint "$CLR_OK" "  IP: ${ip}"
    ipinfo="$(server_check_ipinfo_line || true)"
    paint "$CLR_MUTED" "  $(tr_text "Провайдер/локация:" "Provider/location:") ${ipinfo:-n/a}"
  else
    paint "$CLR_DANGER" "  $(tr_text "Не удалось определить публичный IP." "Failed to detect public IP.")"
  fi

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Репутация IP (DNSBL)" "IP reputation (DNSBL)")"
  if [[ -n "$ip" ]] && rev_ip="$(server_check_reverse_ipv4 "$ip")"; then
    for zone in "${dnsbl_zones[@]}"; do
      if server_check_dnsbl_query "${rev_ip}.${zone}"; then
        listed_count=$((listed_count + 1))
        paint "$CLR_DANGER" "  [LISTED] ${zone}"
      else
        paint "$CLR_OK" "  [OK] ${zone}"
      fi
    done
    if (( listed_count == 0 )); then
      paint "$CLR_OK" "  $(tr_text "В проверенных DNSBL IP не найден." "IP was not found in checked DNSBL zones.")"
    else
      paint "$CLR_DANGER" "  $(tr_text "IP найден в DNSBL:" "IP is listed in DNSBL:") ${listed_count}"
    fi
  else
    paint "$CLR_WARN" "  $(tr_text "DNSBL-проверка доступна только для IPv4." "DNSBL check is available for IPv4 only.")"
  fi

  print_separator
  paint "$CLR_TITLE" "DNS"
  for zone in "${dns_hosts[@]}"; do
    lookup="$(server_check_dns_query "$zone" || true)"
    if [[ -n "$lookup" ]]; then
      paint "$CLR_OK" "  ${zone}: ${lookup}"
    else
      paint "$CLR_DANGER" "  ${zone}: $(tr_text "не резолвится" "does not resolve")"
    fi
  done

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Доступность сайтов/API" "Website/API reachability")"
  server_check_http_probe "Google" "https://www.google.com/generate_204"
  server_check_http_probe "YouTube" "https://www.youtube.com/"
  server_check_http_probe "Telegram API" "https://api.telegram.org/"
  server_check_http_probe "GitHub" "https://github.com/"
  server_check_http_probe "GitHub raw" "https://raw.githubusercontent.com/"
  server_check_http_probe "Docker Hub" "https://registry-1.docker.io/v2/"
  server_check_http_probe "Cloudflare" "https://www.cloudflare.com/cdn-cgi/trace"

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Скорость" "Speed")"
  if ask_yes_no "$(tr_text "Сделать легкий download-тест через Cloudflare (~10 MB)?" "Run a light Cloudflare download test (~10 MB)?")" "y"; then
    server_check_download_speed 10000000 || speed_rc=$?
  else
    speed_rc=$?
    if [[ "$speed_rc" -eq 2 ]]; then
      paint "$CLR_WARN" "$(tr_text "Проверка скорости пропущена." "Speed check skipped.")"
    else
      paint "$CLR_MUTED" "$(tr_text "Проверка скорости пропущена." "Speed check skipped.")"
    fi
  fi

  print_separator
  paint "$CLR_MUTED" "$(tr_text "Если сайты недоступны, проверьте DNS, firewall провайдера, IPv6/WARP/прокси и ограничения датацентра." "If sites are unreachable, check DNS, provider firewall, IPv6/WARP/proxy and datacenter restrictions.")"
}

show_disk_usage_top() {
  local root_df=""
  local path=""
  local label=""
  local top_lines=""

  draw_header "$(tr_text "Анализ диска" "Disk analysis")"
  root_df="$(df -h / 2>/dev/null | awk 'NR==2 {print $3" / "$2" ("$5")"}' || true)"
  paint "$CLR_TITLE" "$(tr_text "Использование корня (/)" "Root filesystem usage (/):")"
  paint "$CLR_MUTED" "  ${root_df:-n/a}"
  print_separator

  for path in /var /opt /home; do
    [[ -d "$path" ]] || continue
    label="$(tr_text "Крупные каталоги в" "Largest directories in")"
    paint "$CLR_TITLE" "${label} ${path}"
    top_lines="$(du -x -h -d 1 "$path" 2>/dev/null | sort -hr | head -n 8 || true)"
    if [[ -n "$top_lines" ]]; then
      echo "$top_lines" | while IFS= read -r line; do
        paint "$CLR_MUTED" "  ${line}"
      done
    else
      paint "$CLR_MUTED" "  n/a"
    fi
    print_separator
  done

  paint "$CLR_MUTED" "$(tr_text "Подсказка: для контейнеров отдельно смотрите \"Docker disk usage\" ниже в разделе очистки." "Tip: for containers, see \"Docker disk usage\" in cleanup section.")"
}

show_safe_cleanup_preview() {
  local apt_cache="n/a"
  local tmp_size="n/a"
  local panel_tmp_size="n/a"
  local journal_usage="n/a"
  local docker_df="n/a"

  draw_header "$(tr_text "Безопасная очистка: предпросмотр" "Safe cleanup: preview")"
  paint "$CLR_TITLE" "$(tr_text "Что можно чистить безопасно" "What can be cleaned safely")"
  paint "$CLR_MUTED" "  - $(tr_text "systemd journal старше 7 дней" "systemd journal older than 7 days")"
  paint "$CLR_MUTED" "  - $(tr_text "apt package cache (autoclean)" "apt package cache (autoclean)")"
  paint "$CLR_MUTED" "  - $(tr_text "временные файлы panel-* во /tmp старше 1 часа" "panel-* temporary files in /tmp older than 1 hour")"
  paint "$CLR_MUTED" "  - $(tr_text "временные файлы в /tmp и /var/tmp старше 7 дней" "temporary files in /tmp and /var/tmp older than 7 days")"
  paint "$CLR_MUTED" "  - $(tr_text "docker dangling images + builder cache" "docker dangling images + builder cache")"
  paint "$CLR_WARN" "  $(tr_text "Тома Docker (volumes) не удаляются." "Docker volumes are not removed.")"
  print_separator

  if [[ -d /var/cache/apt/archives ]]; then
    apt_cache="$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo "n/a")"
  fi
  tmp_size="$(du -sh /tmp /var/tmp 2>/dev/null | awk '{print $2": "$1}' | paste -sd ', ' - || true)"
  [[ -z "$tmp_size" ]] && tmp_size="n/a"
  panel_tmp_size="$(find /tmp -maxdepth 1 \( -name 'panel-backup*' -o -name 'panel-restore*' -o -name 'panel-backup-install.*' \) -mmin +60 -exec du -sh {} + 2>/dev/null | awk '{print $2": "$1}' | paste -sd ', ' - || true)"
  [[ -z "$panel_tmp_size" ]] && panel_tmp_size="n/a"
  if command -v journalctl >/dev/null 2>&1; then
    journal_usage="$($SUDO journalctl --disk-usage 2>/dev/null | sed 's/^Archived and active journals take up //; s/ in the file system.$//' || true)"
    [[ -z "$journal_usage" ]] && journal_usage="n/a"
  fi

  paint "$CLR_MUTED" "  $(tr_text "APT cache:" "APT cache:") ${apt_cache}"
  paint "$CLR_MUTED" "  $(tr_text "/tmp + /var/tmp:" "/tmp + /var/tmp:") ${tmp_size}"
  paint "$CLR_MUTED" "  $(tr_text "Временные файлы panel-*:" "Temporary panel-* files:") ${panel_tmp_size}"
  paint "$CLR_MUTED" "  $(tr_text "System journal:" "System journal:") ${journal_usage}"
  print_separator

  if command -v docker >/dev/null 2>&1; then
    paint "$CLR_TITLE" "Docker disk usage"
    docker_df="$($SUDO docker system df 2>/dev/null || true)"
    if [[ -n "$docker_df" ]]; then
      echo "$docker_df" | while IFS= read -r line; do
        paint "$CLR_MUTED" "  ${line}"
      done
    else
      paint "$CLR_MUTED" "  n/a"
    fi
  else
    paint "$CLR_MUTED" "Docker: n/a"
  fi
  print_separator
}

run_safe_cleanup() {
  local before_used_kb=0
  local after_used_kb=0
  local freed_kb=0
  local panel_tmp_count=0
  local old_tmp_count=0
  local before_df=""
  local after_df=""

  disk_used_kb() {
    df -Pk / 2>/dev/null | awk 'NR==2 {print $3+0}' || echo 0
  }

  kb_to_human() {
    local kb="${1:-0}"
    awk -v kb="$kb" 'BEGIN {
      split("KB MB GB TB", u, " ");
      v=kb+0;
      i=1;
      while (v>=1024 && i<4) { v=v/1024; i++; }
      printf("%.2f %s", v, u[i]);
    }'
  }

  before_used_kb="$(disk_used_kb)"
  before_df="$(df -h / 2>/dev/null | awk 'NR==2 {print $3" / "$2" ("$5")"}' || true)"
  panel_tmp_count="$(find /tmp -maxdepth 1 \( -name 'panel-backup*' -o -name 'panel-restore*' -o -name 'panel-backup-install.*' \) -mmin +60 2>/dev/null | wc -l | awk '{print $1}' || echo 0)"
  old_tmp_count="$(find /tmp /var/tmp -xdev -type f -mtime +7 2>/dev/null | wc -l | awk '{print $1}' || echo 0)"

  paint "$CLR_ACCENT" "$(tr_text "Запуск безопасной очистки..." "Running safe cleanup...")"

  if command -v journalctl >/dev/null 2>&1; then
    paint "$CLR_MUTED" "  - $(tr_text "Очищаю system journal старше 7 дней" "Vacuuming system journal older than 7 days")"
    if ! $SUDO journalctl --vacuum-time=7d >/dev/null 2>&1; then
      paint "$CLR_WARN" "    $(tr_text "Предупреждение: не удалось очистить system journal" "Warning: failed to vacuum system journal")"
    fi
  fi

  if command -v apt-get >/dev/null 2>&1; then
    paint "$CLR_MUTED" "  - $(tr_text "Очищаю apt cache (autoclean)" "Cleaning apt cache (autoclean)")"
    if ! $SUDO apt-get autoclean -y >/dev/null 2>&1; then
      paint "$CLR_WARN" "    $(tr_text "Предупреждение: не удалось выполнить apt autoclean" "Warning: failed to run apt autoclean")"
    fi
  fi

  paint "$CLR_MUTED" "  - $(tr_text "Удаляю временные файлы panel-* в /tmp старше 1 часа" "Removing panel-* temporary files in /tmp older than 1 hour")"
  if ! $SUDO find /tmp -maxdepth 1 \( -name 'panel-backup*' -o -name 'panel-restore*' -o -name 'panel-backup-install.*' \) -mmin +60 -exec rm -rf -- {} + 2>/dev/null; then
    paint "$CLR_WARN" "    $(tr_text "Предупреждение: часть panel-* файлов не удалена" "Warning: some panel-* files were not removed")"
  fi

  paint "$CLR_MUTED" "  - $(tr_text "Удаляю старые файлы (>7 дней) в /tmp и /var/tmp" "Removing old files (>7 days) in /tmp and /var/tmp")"
  if ! $SUDO find /tmp /var/tmp -xdev -type f -mtime +7 -delete 2>/dev/null; then
    paint "$CLR_WARN" "    $(tr_text "Предупреждение: часть старых файлов не удалена" "Warning: some old files were not removed")"
  fi

  if command -v docker >/dev/null 2>&1; then
    paint "$CLR_MUTED" "  - $(tr_text "Docker: image prune (dangling only)" "Docker: image prune (dangling only)")"
    if ! $SUDO docker image prune -f >/dev/null 2>&1; then
      paint "$CLR_WARN" "    $(tr_text "Предупреждение: docker image prune завершился с ошибкой" "Warning: docker image prune failed")"
    fi
    paint "$CLR_MUTED" "  - $(tr_text "Docker: builder prune" "Docker: builder prune")"
    if ! $SUDO docker builder prune -f >/dev/null 2>&1; then
      paint "$CLR_WARN" "    $(tr_text "Предупреждение: docker builder prune завершился с ошибкой" "Warning: docker builder prune failed")"
    fi
  fi

  after_used_kb="$(disk_used_kb)"
  after_df="$(df -h / 2>/dev/null | awk 'NR==2 {print $3" / "$2" ("$5")"}' || true)"
  freed_kb=$((before_used_kb - after_used_kb))
  if (( freed_kb < 0 )); then
    freed_kb=0
  fi

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Отчет по очистке" "Cleanup report")"
  paint "$CLR_MUTED" "  $(tr_text "Удалено устаревших panel-* во временных файлах:" "Removed stale panel-* temporary entries:") ${panel_tmp_count}"
  paint "$CLR_MUTED" "  $(tr_text "Удалено старых файлов (>7 дней) в /tmp и /var/tmp:" "Removed old files (>7 days) in /tmp and /var/tmp:") ${old_tmp_count}"
  paint "$CLR_MUTED" "  $(tr_text "Диск / до:" "Disk / before:") ${before_df:-n/a}"
  paint "$CLR_MUTED" "  $(tr_text "Диск / после:" "Disk / after:") ${after_df:-n/a}"
  paint "$CLR_OK" "  $(tr_text "Освобождено на /:" "Freed on /:") $(kb_to_human "$freed_kb")"

  paint "$CLR_OK" "$(tr_text "Безопасная очистка завершена." "Safe cleanup completed.")"
}
