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
    from_path="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
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

