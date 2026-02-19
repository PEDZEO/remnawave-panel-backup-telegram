#!/usr/bin/env bash
# Interactive menu sections for manager.sh

menu_flow_install_and_setup() {
  draw_header "$(tr_text "Установка и настройка" "Install and configure")"
  paint "$CLR_MUTED" "$(tr_text "Используйте этот пункт при первом запуске или обновлении скриптов." "Use this on first run or when updating scripts.")"
  if ! prompt_install_settings; then
    return 0
  fi
  show_settings_preview
  if ! ask_yes_no "$(tr_text "Применить эти настройки и продолжить установку?" "Apply these settings and continue installation?")" "y"; then
    [[ "$?" == "2" ]] && return 0
    paint "$CLR_WARN" "$(tr_text "Отменено пользователем." "Cancelled by user.")"
    wait_for_enter
    return 0
  fi
  if ! preflight_install_environment; then
    paint "$CLR_DANGER" "$(tr_text "Preflight не пройден. Установка остановлена." "Preflight failed. Installation aborted.")"
    wait_for_enter
    return 0
  fi
  install_files
  write_env
  if ask_yes_no "$(tr_text "Включить таймер backup сейчас?" "Enable backup timer now?")" "y"; then
    enable_timer
  else
    case $? in
      1)
        paint "$CLR_WARN" "$(tr_text "Таймер не включен. Позже можно включить так:" "Timer was not enabled. You can enable later with:")"
        paint "$CLR_MUTED" "  sudo systemctl enable --now panel-backup.timer"
        ;;
      2) paint "$CLR_WARN" "$(tr_text "Пропущено." "Skipped.")" ;;
    esac
  fi
  post_install_health_check
  wait_for_enter
}

menu_flow_edit_settings_only() {
  draw_header "$(tr_text "Настройка Telegram и пути" "Configure Telegram and path")"
  paint "$CLR_MUTED" "$(tr_text "Скрипты не переустанавливаются: меняется только /etc/panel-backup.env." "Scripts are not reinstalled: only /etc/panel-backup.env will be changed.")"
  if ! prompt_install_settings; then
    return 0
  fi
  show_settings_preview
  if ! ask_yes_no "$(tr_text "Сохранить эти настройки?" "Save these settings?")" "y"; then
    [[ "$?" == "2" ]] && return 0
    paint "$CLR_WARN" "$(tr_text "Изменения не сохранены." "Changes were not saved.")"
    wait_for_enter
    return 0
  fi
  write_env
  paint "$CLR_OK" "$(tr_text "Настройки обновлены." "Settings updated.")"
  wait_for_enter
}

menu_section_setup() {
  local choice=""
  while true; do
    draw_header "$(tr_text "Раздел: Установка и настройка" "Section: Setup and configuration")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Здесь первичная установка и изменение конфигурации." "Use this section for initial install and config changes.")"
    menu_option "1" "$(tr_text "Установить/обновить файлы + первичная настройка" "Install/update files + initial setup")"
    menu_option "2" "$(tr_text "Изменить только текущие настройки" "Edit current settings only")"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_flow_install_and_setup ;;
      2) menu_flow_edit_settings_only ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

list_local_backups() {
  ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz 2>/dev/null || true
}

render_backup_list() {
  local -a files=("$@")
  local idx=1
  local path=""
  local size=""
  local mtime=""

  if [[ ${#files[@]} -eq 0 ]]; then
    paint "$CLR_WARN" "$(tr_text "В /var/backups/panel нет архивов backup." "No backup archives found in /var/backups/panel.")"
    return 0
  fi

  paint "$CLR_TITLE" "$(tr_text "Доступные backup-файлы" "Available backup files")"
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
    draw_header "$(tr_text "Источник backup для восстановления" "Restore source selection")"
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
        selected="$(ask_value "$(tr_text "Введите номер backup из списка" "Enter backup number from list")" "")"
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
        path="$(ask_value "$(tr_text "Путь к backup-архиву (.tar.gz)" "Path to backup archive (.tar.gz)")" "$BACKUP_FILE")"
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
        url="$(ask_value "$(tr_text "URL backup-архива" "Backup archive URL")" "$BACKUP_URL")"
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
    draw_header "$(tr_text "Выбор данных для восстановления" "Restore components selection")"
    paint "$CLR_MUTED" "$(tr_text "Выберите, что именно восстанавливать из backup." "Choose which data to restore from backup.")"
    menu_option "1" "$(tr_text "Все (db + redis + configs)" "All (db + redis + configs)")"
    menu_option "2" "$(tr_text "Только PostgreSQL (db)" "PostgreSQL only (db)")"
    menu_option "3" "$(tr_text "Только Redis (redis)" "Redis only (redis)")"
    menu_option "4" "$(tr_text "Только конфиги (configs)" "Configs only (configs)")"
    menu_option "5" "$(tr_text "Свой список компонентов" "Custom components list")"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      return 1
    fi
    case "$choice" in
      1) RESTORE_ONLY="all"; return 0 ;;
      2) RESTORE_ONLY="db"; return 0 ;;
      3) RESTORE_ONLY="redis"; return 0 ;;
      4) RESTORE_ONLY="configs"; return 0 ;;
      5)
        custom="$(ask_value "$(tr_text "Компоненты через запятую (all,db,redis,configs,env,compose,caddy,subscription)" "Comma-separated components (all,db,redis,configs,env,compose,caddy,subscription)")" "$RESTORE_ONLY")"
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

show_restore_summary() {
  paint "$CLR_TITLE" "$(tr_text "Параметры восстановления" "Restore parameters")"
  paint "$CLR_MUTED" "  BACKUP_FILE: ${BACKUP_FILE:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  BACKUP_URL: ${BACKUP_URL:-$(tr_text "не задан" "not set")}"
  paint "$CLR_MUTED" "  RESTORE_ONLY: ${RESTORE_ONLY:-all}"
  paint "$CLR_MUTED" "  RESTORE_DRY_RUN: ${RESTORE_DRY_RUN:-0}"
  paint "$CLR_MUTED" "  RESTORE_NO_RESTART: ${RESTORE_NO_RESTART:-0}"
}

draw_restore_step() {
  local step="$1"
  local total="$2"
  local title="$3"
  draw_header "$(tr_text "Мастер восстановления backup" "Backup restore wizard")" "$(tr_text "Шаг" "Step") ${step}/${total}: ${title}"
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

menu_section_operations() {
  local choice=""
  while true; do
    draw_header "$(tr_text "Раздел: Ручное управление backup" "Section: Manual backup control")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Здесь можно вручную: 1) создать backup, 2) восстановить backup." "Manually: 1) create backup, 2) restore backup.")"
    menu_option "1" "$(tr_text "Создать backup сейчас" "Create backup now")"
    menu_option "2" "$(tr_text "Восстановить backup" "Restore backup")"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        draw_header "$(tr_text "Создание backup" "Create backup")"
        if run_backup_now; then
          paint "$CLR_OK" "$(tr_text "Backup выполнен успешно." "Backup completed successfully.")"
        else
          paint "$CLR_DANGER" "$(tr_text "Ошибка создания backup. Проверьте лог выше." "Backup failed. Check the log above.")"
        fi
        wait_for_enter
        ;;
      2)
        draw_restore_step "1" "4" "$(tr_text "Выбор источника backup" "Select backup source")"
        MODE="restore"
        RESTORE_DRY_RUN=0
        RESTORE_NO_RESTART=0
        RESTORE_ONLY="all"
        if ! select_restore_source; then
          continue
        fi
        draw_restore_step "2" "4" "$(tr_text "Выбор компонентов" "Select components")"
        if ! select_restore_components; then
          continue
        fi
        draw_restore_step "3" "4" "$(tr_text "Параметры запуска" "Execution options")"
        if ask_yes_no "$(tr_text "Запустить restore в dry-run режиме?" "Run restore in dry-run mode?")" "n"; then
          RESTORE_DRY_RUN=1
        else
          [[ "$?" == "2" ]] && continue
        fi
        if ask_yes_no "$(tr_text "Пропустить перезапуск сервисов после restore?" "Skip service restart after restore?")" "n"; then
          RESTORE_NO_RESTART=1
        else
          [[ "$?" == "2" ]] && continue
        fi
        draw_restore_step "4" "4" "$(tr_text "Подтверждение и запуск" "Confirm and run")"
        show_restore_summary
        print_separator
        if ! ask_yes_no "$(tr_text "Запустить восстановление с этими параметрами?" "Run restore with these parameters?")" "y"; then
          [[ "$?" == "2" ]] && continue
          paint "$CLR_WARN" "$(tr_text "Восстановление отменено." "Restore cancelled.")"
          wait_for_enter
          continue
        fi
        if [[ "$RESTORE_DRY_RUN" != "1" ]]; then
          if ! confirm_restore_phrase; then
            paint "$CLR_WARN" "$(tr_text "Подтверждение не пройдено. Восстановление отменено." "Confirmation failed. Restore cancelled.")"
            wait_for_enter
            continue
          fi
        fi
        if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
          install_files
          write_env
          $SUDO systemctl daemon-reload
        fi
        if run_restore; then
          paint "$CLR_OK" "$(tr_text "Восстановление завершено." "Restore completed.")"
        else
          paint "$CLR_DANGER" "$(tr_text "Ошибка восстановления. Проверьте лог выше." "Restore failed. Check the log above.")"
        fi
        wait_for_enter
        ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_timer() {
  local choice=""
  local schedule_now=""
  while true; do
    draw_header "$(tr_text "Раздел: Таймер и периодичность" "Section: Timer and schedule")"
    show_back_hint
    schedule_now="$(get_current_timer_calendar || true)"
    paint "$CLR_MUTED" "$(tr_text "Текущее расписание:" "Current schedule:") $(format_schedule_label "$schedule_now")"
    menu_option "1" "$(tr_text "🟢 Включить таймер backup" "🟢 Enable backup timer")"
    menu_option "2" "$(tr_text "🟠 Выключить таймер backup" "🟠 Disable backup timer")"
    menu_option "3" "$(tr_text "Настроить периодичность backup" "Configure backup schedule")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        draw_header "$(tr_text "Включение таймера backup" "Enable backup timer")"
        enable_timer
        wait_for_enter
        ;;
      2)
        draw_header "$(tr_text "Отключение таймера backup" "Disable backup timer")"
        disable_timer
        wait_for_enter
        ;;
      3)
        if configure_schedule_menu; then
          write_env
          write_timer_unit
          $SUDO systemctl daemon-reload
          paint "$CLR_OK" "$(tr_text "Периодичность backup сохранена." "Backup schedule saved.")"
          if $SUDO systemctl is-enabled --quiet panel-backup.timer 2>/dev/null; then
            $SUDO systemctl restart panel-backup.timer || true
          fi
        fi
        wait_for_enter
        ;;
      4) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_status() {
  local choice=""
  while true; do
    draw_header "$(tr_text "Раздел: Статус и диагностика" "Section: Status and diagnostics")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Проверка состояния скриптов, таймера и последних backup." "Check scripts, timer and latest backup details.")"
    menu_option "1" "$(tr_text "Показать полный статус" "Show full status")"
    menu_option "2" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-2]: " "Choice [1-2]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) show_status; wait_for_enter ;;
      2) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

interactive_menu() {
  local action=""

  setup_colors
  enter_ui_mode
  choose_ui_lang

  while true; do
    draw_header "$(tr_text "Менеджер бэкапа панели" "Panel Backup Manager")"
    show_back_hint
    menu_option "1" "$(tr_text "Установка и настройка" "Setup and configuration")"
    menu_option "2" "$(tr_text "Создать или восстановить backup (вручную)" "Create or restore backup (manual)")"
    menu_option "3" "$(tr_text "Таймер и периодичность" "Timer and schedule")"
    menu_option "4" "$(tr_text "Статус и диагностика" "Status and diagnostics")"
    menu_option "0" "$(tr_text "Выход" "Exit")" "$CLR_DANGER"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4/0]: " "Choice [1-4/0]: ")" action
    if is_back_command "$action"; then
      echo "$(tr_text "Выход." "Cancelled.")"
      break
    fi

    case "$action" in
      1) menu_section_setup ;;
      2) menu_section_operations ;;
      3) menu_section_timer ;;
      4) menu_section_status ;;
      0)
        echo "$(tr_text "Выход." "Cancelled.")"
        break
        ;;
      *)
        echo "$(tr_text "Некорректный выбор." "Invalid choice.")"
        ;;
    esac
  done
}
