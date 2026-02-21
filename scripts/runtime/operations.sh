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
  local include_quoted=""

  sync_runtime_scripts
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

  print_separator
  paint "$CLR_TITLE" "$(tr_text "Установка" "Installation")"
  paint "$CLR_MUTED" "  $(tr_text "Backup-скрипт:" "Backup script:") ${backup_installed} (/usr/local/bin/panel-backup.sh)"
  paint "$CLR_MUTED" "  $(tr_text "Restore-скрипт:" "Restore script:") ${restore_installed} (/usr/local/bin/panel-restore.sh)"
  paint "$CLR_MUTED" "  $(tr_text "Файл конфигурации:" "Config file:") ${config_present} (/etc/panel-backup.env)"

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
  else
    print_separator
    paint "$CLR_WARN" "$(tr_text "Таймер панели: недоступен" "Panel timer: not available")"
  fi

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
  else
    print_separator
    paint "$CLR_WARN" "$(tr_text "Таймер Bedolaga: недоступен" "Bedolaga timer: not available")"
  fi
  schedule_now="$(get_current_timer_calendar || true)"
  paint "$CLR_MUTED" "  $(tr_text "Периодичность backup:" "Backup schedule:") $(format_schedule_label "$schedule_now")"

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
  panel_tmp_count="$(find /tmp -maxdepth 1 \( -name 'panel-backup*' -o -name 'panel-restore*' -o -name 'panel-backup-install.*' \) 2>/dev/null | wc -l | awk '{print $1}' || echo 0)"
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

  paint "$CLR_MUTED" "  - $(tr_text "Удаляю временные файлы panel-* в /tmp" "Removing panel-* temporary files in /tmp")"
  if ! $SUDO rm -rf /tmp/panel-backup* /tmp/panel-restore* /tmp/panel-backup-install.* 2>/dev/null; then
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
  paint "$CLR_MUTED" "  $(tr_text "Удалено panel-* во временных файлах:" "Removed panel-* temporary entries:") ${panel_tmp_count}"
  paint "$CLR_MUTED" "  $(tr_text "Удалено старых файлов (>7 дней) в /tmp и /var/tmp:" "Removed old files (>7 days) in /tmp and /var/tmp:") ${old_tmp_count}"
  paint "$CLR_MUTED" "  $(tr_text "Диск / до:" "Disk / before:") ${before_df:-n/a}"
  paint "$CLR_MUTED" "  $(tr_text "Диск / после:" "Disk / after:") ${after_df:-n/a}"
  paint "$CLR_OK" "  $(tr_text "Освобождено на /:" "Freed on /:") $(kb_to_human "$freed_kb")"

  paint "$CLR_OK" "$(tr_text "Безопасная очистка завершена." "Safe cleanup completed.")"
}
