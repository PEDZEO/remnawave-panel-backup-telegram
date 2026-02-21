#!/usr/bin/env bash
# Restore wizard and result-summary helpers for interactive menu.

list_local_backups() {
  ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null || true
}

render_backup_list() {
  local -a files=("$@")
  local idx=1
  local path=""
  local size=""
  local mtime=""

  if [[ ${#files[@]} -eq 0 ]]; then
    paint "$CLR_WARN" "$(tr_text "В /var/backups/panel нет архивов резервной копии." "No backup archives found in /var/backups/panel.")"
    return 0
  fi

  paint "$CLR_TITLE" "$(tr_text "Доступные архивы резервной копии" "Available backup files")"
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
    draw_subheader "$(tr_text "Источник архива для восстановления" "Restore source selection")"
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
        selected="$(ask_value "$(tr_text "Введите номер архива из списка" "Enter backup number from list")" "")"
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
        path="$(ask_value "$(tr_text "Путь к архиву (.tar.gz или .tar.gz.gpg)" "Path to backup archive (.tar.gz or .tar.gz.gpg)")" "$BACKUP_FILE")"
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
        url="$(ask_value "$(tr_text "URL архива" "Backup archive URL")" "$BACKUP_URL")"
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
    draw_subheader "$(tr_text "Выбор данных для восстановления" "Restore components selection")"
    paint "$CLR_MUTED" "$(tr_text "Выберите, что именно восстанавливать из архива." "Choose which data to restore from backup.")"
    menu_option "1" "$(tr_text "Полный (панель + Bedolaga)" "Full (panel + Bedolaga)")"
    menu_option "2" "$(tr_text "Только PostgreSQL (db)" "PostgreSQL only (db)")"
    menu_option "3" "$(tr_text "Только Redis (redis)" "Redis only (redis)")"
    menu_option "4" "$(tr_text "Только конфиги (панель + Bedolaga)" "Configs only (panel + Bedolaga)")"
    menu_option "5" "$(tr_text "Свой список компонентов" "Custom components list")"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      return 1
    fi
    case "$choice" in
      1) RESTORE_ONLY="all,bedolaga"; return 0 ;;
      2) RESTORE_ONLY="db"; return 0 ;;
      3) RESTORE_ONLY="redis"; return 0 ;;
      4) RESTORE_ONLY="configs,bedolaga-configs"; return 0 ;;
      5)
        custom="$(ask_value "$(tr_text "Компоненты через запятую (all,db,redis,configs,env,compose,caddy,subscription,bedolaga,bedolaga-db,bedolaga-redis,bedolaga-bot,bedolaga-cabinet,bedolaga-configs)" "Comma-separated components (all,db,redis,configs,env,compose,caddy,subscription,bedolaga,bedolaga-db,bedolaga-redis,bedolaga-bot,bedolaga-cabinet,bedolaga-configs)")" "$RESTORE_ONLY")"
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

restore_source_looks_encrypted() {
  if [[ -n "${BACKUP_FILE:-}" && "${BACKUP_FILE}" == *.gpg ]]; then
    return 0
  fi
  if [[ -n "${BACKUP_URL:-}" && "${BACKUP_URL}" == *.gpg* ]]; then
    return 0
  fi
  return 1
}

ensure_restore_password_if_needed() {
  local entered=""
  local masked=""

  load_existing_env_defaults
  if ! restore_source_looks_encrypted; then
    return 0
  fi

  if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
    masked="$(mask_secret "$BACKUP_PASSWORD")"
    paint "$CLR_MUTED" "$(tr_text "Архив зашифрован, пароль найден в настройках:" "Encrypted archive, password found in settings:") ${masked}"
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Архив зашифрован (.gpg). Нужен пароль для восстановления." "Encrypted archive (.gpg). Password is required for restore.")"
  while true; do
    entered="$(ask_secret_value "$(tr_text "Введите пароль от архива" "Enter backup archive password")" "")"
    if [[ "$entered" == "__PBM_BACK__" ]]; then
      return 1
    fi
    if [[ -z "$entered" ]]; then
      paint "$CLR_WARN" "$(tr_text "Пароль не может быть пустым." "Password cannot be empty.")"
      continue
    fi
    BACKUP_PASSWORD="$entered"
    export BACKUP_PASSWORD
    return 0
  done
}

show_restore_summary() {
  local source_label=""
  local components_label=""
  local mode_label=""
  local restart_label=""

  if [[ -n "${BACKUP_FILE:-}" ]]; then
    source_label="$(tr_text "локальный файл" "local file")"
  elif [[ -n "${BACKUP_URL:-}" ]]; then
    source_label="$(tr_text "скачивание по URL" "download by URL")"
  else
    source_label="$(tr_text "не выбран" "not selected")"
  fi

  case "${RESTORE_ONLY:-all}" in
    all,bedolaga|bedolaga,all) components_label="$(tr_text "полный (панель + Bedolaga)" "full (panel + Bedolaga)")" ;;
    all) components_label="$(tr_text "всё (панель: база + redis + конфиги)" "everything (panel: db + redis + configs)")" ;;
    db) components_label="$(tr_text "только база PostgreSQL" "PostgreSQL database only")" ;;
    redis) components_label="$(tr_text "только Redis" "Redis only")" ;;
    configs,bedolaga-configs|bedolaga-configs,configs) components_label="$(tr_text "конфиги (панель + Bedolaga)" "configs (panel + Bedolaga)")" ;;
    configs) components_label="$(tr_text "только конфиги панели (env/compose/caddy/subscription)" "panel configs only (env/compose/caddy/subscription)")" ;;
    *) components_label="$(tr_text "кастом: " "custom: ")${RESTORE_ONLY}" ;;
  esac

  if [[ "${RESTORE_DRY_RUN:-0}" == "1" ]]; then
    mode_label="$(tr_text "тестовый запуск (без изменений)" "test run (no changes)")"
  else
    mode_label="$(tr_text "боевой запуск (изменения будут применены)" "real run (changes will be applied)")"
  fi

  if [[ "${RESTORE_NO_RESTART:-0}" == "1" ]]; then
    restart_label="$(tr_text "перезапуски сервисов отключены" "service restarts are disabled")"
  else
    restart_label="$(tr_text "после restore будут перезапуски сервисов" "services will be restarted after restore")"
  fi

  paint "$CLR_TITLE" "$(tr_text "Параметры восстановления" "Restore parameters")"
  paint "$CLR_MUTED" "  $(tr_text "Источник:" "Source:") ${source_label}"
  if [[ -n "${BACKUP_FILE:-}" ]]; then
    paint "$CLR_MUTED" "  $(tr_text "Файл:" "File:") ${BACKUP_FILE}"
  fi
  if [[ -n "${BACKUP_URL:-}" ]]; then
    paint "$CLR_MUTED" "  URL: ${BACKUP_URL}"
  fi
  paint "$CLR_MUTED" "  $(tr_text "Что восстанавливаем:" "What will be restored:") ${components_label}"
  paint "$CLR_MUTED" "  $(tr_text "Режим:" "Mode:") ${mode_label}"
  paint "$CLR_MUTED" "  $(tr_text "Перезапуски:" "Restarts:") ${restart_label}"
}

show_restore_safety_checklist() {
  local source_ok=0
  local source_label=""
  local latest_local=""
  local latest_age_h="n/a"
  local db_snapshot=""

  if [[ -n "${BACKUP_FILE:-}" && -f "${BACKUP_FILE:-}" ]]; then
    source_ok=1
    source_label="$(tr_text "локальный файл доступен" "local file is available")"
  elif [[ -n "${BACKUP_URL:-}" ]]; then
    source_ok=1
    source_label="$(tr_text "URL указан (файл будет скачан)" "URL is set (file will be downloaded)")"
  else
    source_label="$(tr_text "источник не выбран" "source is not selected")"
  fi

  latest_local="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_local" && -f "$latest_local" ]]; then
    latest_age_h="$(( ( $(date +%s) - $(date -r "$latest_local" +%s) ) / 3600 ))"
  fi

  db_snapshot="$(ls -1t /var/backups/panel/manual-db-snapshots/remnawave-db-pretest-*.dump 2>/dev/null | head -n1 || true)"

  paint "$CLR_TITLE" "$(tr_text "Чеклист перед запуском" "Pre-run checklist")"
  if (( source_ok == 1 )); then
    paint "$CLR_OK" "  [OK] $(tr_text "Источник:" "Source:") ${source_label}"
  else
    paint "$CLR_WARN" "  [WARN] $(tr_text "Источник:" "Source:") ${source_label}"
  fi
  if [[ -n "$latest_local" ]]; then
    paint "$CLR_MUTED" "  [OK] $(tr_text "Последний локальный архив:" "Latest local backup:") $(basename "$latest_local") ($(tr_text "возраст, ч:" "age, h:") ${latest_age_h})"
  else
    paint "$CLR_WARN" "  [WARN] $(tr_text "Локальные архивы не найдены." "No local backup files found.")"
  fi
  if [[ -n "$db_snapshot" ]]; then
    paint "$CLR_MUTED" "  [OK] $(tr_text "Ручной snapshot БД:" "Manual DB snapshot:") $(basename "$db_snapshot")"
  else
    paint "$CLR_WARN" "  [WARN] $(tr_text "Нет ручного снимка БД в /var/backups/panel/manual-db-snapshots." "No manual DB snapshot in /var/backups/panel/manual-db-snapshots.")"
  fi
  if [[ "${RESTORE_DRY_RUN:-0}" == "1" ]]; then
    paint "$CLR_OK" "  [SAFE] $(tr_text "Выбран тестовый режим (без изменений)." "Test mode selected (no changes).")"
  else
    paint "$CLR_WARN" "  [RISK] $(tr_text "Выбран боевой режим (изменения будут применены)." "Real mode selected (changes will be applied).")"
  fi
}

show_operation_result_summary() {
  local action="$1"
  local ok="$2"
  local latest_local=""
  local status_text=""

  latest_local="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  if [[ "$ok" == "1" ]]; then
    status_text="$(tr_text "успешно" "success")"
    paint "$CLR_OK" "$(tr_text "Итог операции" "Operation summary")"
  else
    status_text="$(tr_text "ошибка" "failed")"
    paint "$CLR_DANGER" "$(tr_text "Итог операции" "Operation summary")"
  fi
  paint "$CLR_MUTED" "  $(tr_text "Операция:" "Action:") ${action}"
  paint "$CLR_MUTED" "  $(tr_text "Статус:" "Status:") ${status_text}"
  if [[ -n "$latest_local" ]]; then
    paint "$CLR_MUTED" "  $(tr_text "Последний архив:" "Latest backup:") $(basename "$latest_local")"
  fi
  paint "$CLR_MUTED" "  $(tr_text "Дальше:" "Next:") $(tr_text "можно открыть раздел \"Статус и диагностика\"." "you can open \"Status and diagnostics\".")"
}

draw_restore_step() {
  local step="$1"
  local total="$2"
  local title="$3"
  draw_subheader "$(tr_text "Мастер восстановления" "Backup restore wizard")" "$(tr_text "Шаг" "Step") ${step}/${total}: ${title}"
}

confirm_restore_phrase() {
  local expected=""
  local input=""

  if [[ "$UI_LANG" == "en" ]]; then
    expected="RESTORE"
  else
    expected="ВОССТАНОВИТЬ"
  fi

  paint "$CLR_DANGER" "$(tr_text "Внимание: восстановление изменит текущую систему." "Warning: restore will modify the current system.")"
  paint "$CLR_MUTED" "$(tr_text "Для подтверждения введите слово:" "To confirm, type this word:") ${expected}"
  read -r -p "> " input
  if is_back_command "$input"; then
    return 1
  fi
  [[ "$input" == "$expected" ]]
}
