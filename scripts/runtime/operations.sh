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

  if [[ "$RESTORE_DRY_RUN" == "1" ]]; then
    restore_cmd+=(--dry-run)
  fi
  if [[ "$RESTORE_NO_RESTART" == "1" ]]; then
    restore_cmd+=(--no-restart)
  fi

  if [[ -n "$SUDO" ]]; then
    if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
      restore_cmd=("$SUDO" "BACKUP_PASSWORD=${BACKUP_PASSWORD}" "${restore_cmd[@]}")
    else
      restore_cmd=("$SUDO" "${restore_cmd[@]}")
    fi
  fi

  "${restore_cmd[@]}"
}

sync_runtime_scripts() {
  paint "$CLR_ACCENT" "$(tr_text "Обновляю runtime-скрипты backup/restore..." "Updating backup/restore runtime scripts...")"
  fetch "scripts/bin/panel-backup.sh" "$TMP_DIR/panel-backup.sh"
  fetch "scripts/bin/panel-restore.sh" "$TMP_DIR/panel-restore.sh"
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
  local backup_installed="$(tr_text "нет" "no")"
  local restore_installed="$(tr_text "нет" "no")"
  local config_present="$(tr_text "нет" "no")"
  local service_execution=""

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

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Установка" "Installation")"
  paint "$CLR_MUTED" "  $(tr_text "Backup-скрипт:" "Backup script:") ${backup_installed} (/usr/local/bin/panel-backup.sh)"
  paint "$CLR_MUTED" "  $(tr_text "Restore-скрипт:" "Restore script:") ${restore_installed} (/usr/local/bin/panel-restore.sh)"
  paint "$CLR_MUTED" "  $(tr_text "Файл конфигурации:" "Config file:") ${config_present} (/etc/panel-backup.env)"

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
    print_separator
    paint "$CLR_TITLE" "$(tr_text "Таймер" "Timer")"
    paint "$CLR_MUTED" "  $(tr_text "Состояние unit:" "Unit state:") $(humanize_systemd_state "${timer_load:-unknown}")"
    paint "$CLR_MUTED" "  $(tr_text "Автозапуск:" "Autostart:") $(humanize_systemd_state "${timer_unit_file:-unknown}")"
    paint "$CLR_MUTED" "  $(tr_text "Статус:" "Status:") $(humanize_systemd_state "${timer_active:-unknown}") / $(humanize_systemd_state "${timer_sub:-unknown}")"
    paint "$CLR_MUTED" "  $(tr_text "Следующий запуск:" "Next run:") ${timer_next:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Последний запуск:" "Last run:") ${timer_last:-n/a}"
  else
    print_separator
    paint "$CLR_WARN" "$(tr_text "Таймер: недоступен" "Timer: not available")"
  fi
  schedule_now="$(get_current_timer_calendar || true)"
  paint "$CLR_MUTED" "  $(tr_text "Периодичность backup:" "Backup schedule:") $(format_schedule_label "$schedule_now")"

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
    print_separator
    if [[ "${service_result:-}" == "success" && "${service_status:-}" == "0" ]]; then
      service_execution="$(tr_text "успешно" "successful")"
    else
      service_execution="$(humanize_systemd_state "${service_result:-unknown}")"
    fi
    paint "$CLR_TITLE" "$(tr_text "Сервис backup" "Backup service")"
    paint "$CLR_MUTED" "  $(tr_text "Статус:" "Status:") $(humanize_systemd_state "${service_active:-unknown}") / $(humanize_systemd_state "${service_sub:-unknown}")"
    paint "$CLR_MUTED" "  $(tr_text "Результат:" "Result:") ${service_execution}"
    paint "$CLR_MUTED" "  $(tr_text "Код завершения:" "Exit code:") ${service_status:-unknown}"
    paint "$CLR_MUTED" "  $(tr_text "Последний старт:" "Last start:") ${service_started:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Последнее завершение:" "Last finish:") ${service_finished:-n/a}"
  else
    print_separator
    paint "$CLR_WARN" "$(tr_text "Сервис backup: недоступен" "Backup service: not available")"
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
  paint "$CLR_MUTED" "  $(tr_text "Путь Remnawave:" "Remnawave path:") ${REMNAWAVE_DIR:-not-detected}"
  print_separator
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
  paint "$CLR_MUTED" "  - $(tr_text "временные файлы в /tmp и /var/tmp старше 7 дней" "temporary files in /tmp and /var/tmp older than 7 days")"
  paint "$CLR_MUTED" "  - $(tr_text "docker dangling images + builder cache" "docker dangling images + builder cache")"
  paint "$CLR_WARN" "  $(tr_text "Тома Docker (volumes) не удаляются." "Docker volumes are not removed.")"
  print_separator

  if [[ -d /var/cache/apt/archives ]]; then
    apt_cache="$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo "n/a")"
  fi
  tmp_size="$(du -sh /tmp /var/tmp 2>/dev/null | awk '{print $2": "$1}' | paste -sd ', ' - || true)"
  [[ -z "$tmp_size" ]] && tmp_size="n/a"
  panel_tmp_size="$(du -sh /tmp/panel-backup* /tmp/panel-restore* /tmp/panel-backup-install.* 2>/dev/null | awk '{print $2": "$1}' | paste -sd ', ' - || true)"
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
  paint "$CLR_ACCENT" "$(tr_text "Запуск безопасной очистки..." "Running safe cleanup...")"

  if command -v journalctl >/dev/null 2>&1; then
    paint "$CLR_MUTED" "  - $(tr_text "Очищаю system journal старше 7 дней" "Vacuuming system journal older than 7 days")"
    $SUDO journalctl --vacuum-time=7d >/dev/null 2>&1 || true
  fi

  if command -v apt-get >/dev/null 2>&1; then
    paint "$CLR_MUTED" "  - $(tr_text "Очищаю apt cache (autoclean)" "Cleaning apt cache (autoclean)")"
    $SUDO apt-get autoclean -y >/dev/null 2>&1 || true
  fi

  paint "$CLR_MUTED" "  - $(tr_text "Удаляю временные файлы panel-* в /tmp" "Removing panel-* temporary files in /tmp")"
  $SUDO rm -rf /tmp/panel-backup* /tmp/panel-restore* /tmp/panel-backup-install.* 2>/dev/null || true

  paint "$CLR_MUTED" "  - $(tr_text "Удаляю старые файлы (>7 дней) в /tmp и /var/tmp" "Removing old files (>7 days) in /tmp and /var/tmp")"
  $SUDO find /tmp /var/tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true

  if command -v docker >/dev/null 2>&1; then
    paint "$CLR_MUTED" "  - $(tr_text "Docker: image prune (dangling only)" "Docker: image prune (dangling only)")"
    $SUDO docker image prune -f >/dev/null 2>&1 || true
    paint "$CLR_MUTED" "  - $(tr_text "Docker: builder prune" "Docker: builder prune")"
    $SUDO docker builder prune -f >/dev/null 2>&1 || true
  fi

  paint "$CLR_OK" "$(tr_text "Безопасная очистка завершена." "Safe cleanup completed.")"
}
