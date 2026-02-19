#!/usr/bin/env bash
# Interactive menu sections for manager.sh

menu_flow_install_and_setup() {
  local old_bot=""
  local old_admin=""
  local old_thread=""
  local old_dir=""
  local old_lang=""
  local old_encrypt=""
  local old_password=""
  local old_calendar=""
  local old_include=""

  load_existing_env_defaults
  old_bot="$TELEGRAM_BOT_TOKEN"
  old_admin="$TELEGRAM_ADMIN_ID"
  old_thread="$TELEGRAM_THREAD_ID"
  old_dir="$REMNAWAVE_DIR"
  old_lang="$BACKUP_LANG"
  old_encrypt="$BACKUP_ENCRYPT"
  old_password="$BACKUP_PASSWORD"
  old_calendar="$BACKUP_ON_CALENDAR"
  old_include="$BACKUP_INCLUDE"

  draw_header "$(tr_text "Установка и настройка" "Install and configure")"
  paint "$CLR_MUTED" "$(tr_text "Используйте этот пункт при первом запуске или обновлении скриптов." "Use this on first run or when updating scripts.")"
  if ! prompt_install_settings; then
    return 0
  fi
  show_quick_setup_summary "$old_bot" "$old_admin" "$old_thread" "$old_dir" "$old_lang" "$old_encrypt" "$old_password" "$old_calendar" "$old_include"
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

render_change_line() {
  local label="$1"
  local before="$2"
  local after="$3"
  local display_before="$before"
  local display_after="$after"

  [[ "$label" == "TELEGRAM_BOT_TOKEN" || "$label" == "BACKUP_PASSWORD" ]] && display_before="$( [[ -n "$before" ]] && mask_secret "$before" || echo "$(tr_text "не задан" "not set")" )"
  [[ "$label" == "TELEGRAM_BOT_TOKEN" || "$label" == "BACKUP_PASSWORD" ]] && display_after="$( [[ -n "$after" ]] && mask_secret "$after" || echo "$(tr_text "не задан" "not set")" )"
  [[ -z "$display_before" ]] && display_before="$(tr_text "не задан" "not set")"
  [[ -z "$display_after" ]] && display_after="$(tr_text "не задан" "not set")"

  if [[ "$before" == "$after" ]]; then
    paint "$CLR_MUTED" "  = ${label}: ${display_after}"
  else
    paint "$CLR_OK" "  * ${label}: ${display_before} -> ${display_after}"
  fi
}

show_quick_setup_summary() {
  local old_bot="$1"
  local old_admin="$2"
  local old_thread="$3"
  local old_dir="$4"
  local old_lang="$5"
  local old_encrypt="$6"
  local old_password="$7"
  local old_calendar="$8"
  local old_include="$9"

  draw_header "$(tr_text "Краткий итог изменений" "Quick changes summary")"
  paint "$CLR_MUTED" "$(tr_text "Легенда: * изменено, = без изменений." "Legend: * changed, = unchanged.")"
  print_separator
  render_change_line "TELEGRAM_BOT_TOKEN" "$old_bot" "$TELEGRAM_BOT_TOKEN"
  render_change_line "TELEGRAM_ADMIN_ID" "$old_admin" "$TELEGRAM_ADMIN_ID"
  render_change_line "TELEGRAM_THREAD_ID" "$old_thread" "$TELEGRAM_THREAD_ID"
  render_change_line "REMNAWAVE_DIR" "$old_dir" "$REMNAWAVE_DIR"
  render_change_line "BACKUP_LANG" "$old_lang" "$BACKUP_LANG"
  render_change_line "BACKUP_ENCRYPT" "$old_encrypt" "$BACKUP_ENCRYPT"
  render_change_line "BACKUP_PASSWORD" "$old_password" "$BACKUP_PASSWORD"
  render_change_line "BACKUP_ON_CALENDAR" "$old_calendar" "$BACKUP_ON_CALENDAR"
  render_change_line "BACKUP_INCLUDE" "$old_include" "$BACKUP_INCLUDE"
  print_separator
}

menu_flow_quick_setup() {
  local step=1
  local input=""
  local confirm=""
  local old_bot=""
  local old_admin=""
  local old_thread=""
  local old_dir=""
  local old_lang=""
  local old_encrypt=""
  local old_password=""
  local old_calendar=""
  local old_include=""
  local prev_password=""

  load_existing_env_defaults
  old_bot="$TELEGRAM_BOT_TOKEN"
  old_admin="$TELEGRAM_ADMIN_ID"
  old_thread="$TELEGRAM_THREAD_ID"
  old_dir="$REMNAWAVE_DIR"
  old_lang="$BACKUP_LANG"
  old_encrypt="$BACKUP_ENCRYPT"
  old_password="$BACKUP_PASSWORD"
  old_calendar="$BACKUP_ON_CALENDAR"
  old_include="$BACKUP_INCLUDE"

  while true; do
    case "$step" in
      1)
        draw_header "$(tr_text "Быстрая настройка" "Quick setup")" "$(tr_text "Шаг 1/3: Telegram и путь" "Step 1/3: Telegram and path")"
        paint "$CLR_MUTED" "$(tr_text "Команды: b = выход из мастера, p = предыдущий шаг." "Commands: b = exit wizard, p = previous step.")"

        while true; do
          input="$(ask_value_nav "$(tr_text "Токен Telegram-бота" "Telegram bot token")" "$TELEGRAM_BOT_TOKEN")"
          [[ "$input" == "__PBM_BACK__" ]] && return 0
          if [[ "$input" == "__PBM_PREV__" ]]; then
            paint "$CLR_WARN" "$(tr_text "Это первый шаг." "This is the first step.")"
            continue
          fi
          if [[ -n "$input" ]] && ! is_valid_telegram_token "$input"; then
            paint "$CLR_WARN" "$(tr_text "Некорректный токен Telegram." "Invalid Telegram token.")"
            continue
          fi
          TELEGRAM_BOT_TOKEN="$input"
          break
        done

        while true; do
          input="$(ask_value_nav "$(tr_text "ID чата/канала Telegram" "Telegram chat/channel ID")" "$TELEGRAM_ADMIN_ID")"
          [[ "$input" == "__PBM_BACK__" ]] && return 0
          if [[ "$input" == "__PBM_PREV__" ]]; then
            step=1
            continue 2
          fi
          if [[ -n "$input" ]] && ! is_valid_telegram_id "$input"; then
            paint "$CLR_WARN" "$(tr_text "ID чата должен быть числом." "Chat ID must be numeric.")"
            continue
          fi
          TELEGRAM_ADMIN_ID="$input"
          break
        done

        while true; do
          input="$(ask_value_nav "$(tr_text "ID темы (опционально)" "Thread ID (optional)")" "$TELEGRAM_THREAD_ID")"
          [[ "$input" == "__PBM_BACK__" ]] && return 0
          if [[ "$input" == "__PBM_PREV__" ]]; then
            step=1
            continue 2
          fi
          if [[ -n "$input" ]] && ! is_valid_telegram_id "$input"; then
            paint "$CLR_WARN" "$(tr_text "ID темы должен быть числом." "Thread ID must be numeric.")"
            continue
          fi
          TELEGRAM_THREAD_ID="$input"
          break
        done

        while true; do
          input="$(ask_value_nav "$(tr_text "Путь к Remnawave" "Remnawave path")" "$REMNAWAVE_DIR")"
          [[ "$input" == "__PBM_BACK__" ]] && return 0
          if [[ "$input" == "__PBM_PREV__" ]]; then
            step=1
            continue 2
          fi
          REMNAWAVE_DIR="$input"
          break
        done

        while true; do
          input="$(ask_value_nav "$(tr_text "Язык backup (ru/en)" "Backup language (ru/en)")" "$BACKUP_LANG")"
          [[ "$input" == "__PBM_BACK__" ]] && return 0
          if [[ "$input" == "__PBM_PREV__" ]]; then
            step=1
            continue 2
          fi
          case "${input,,}" in
            ru|"") BACKUP_LANG="ru"; break ;;
            en|eu) BACKUP_LANG="en"; break ;;
            *) paint "$CLR_WARN" "$(tr_text "Допустимо только ru или en." "Only ru or en are allowed.")" ;;
          esac
        done

        step=2
        ;;
      2)
        draw_header "$(tr_text "Быстрая настройка" "Quick setup")" "$(tr_text "Шаг 2/3: Шифрование" "Step 2/3: Encryption")"
        paint "$CLR_MUTED" "$(tr_text "1) Включить шифрование  2) Выключить шифрование" "1) Enable encryption  2) Disable encryption")"
        read -r -p "$(tr_text "Выбор [1-2], p назад, b выход: " "Choice [1-2], p back, b exit: ")" input
        if is_back_command "$input"; then
          return 0
        fi
        if is_prev_command "$input"; then
          step=1
          continue
        fi
        case "$input" in
          1) BACKUP_ENCRYPT="1" ;;
          2) BACKUP_ENCRYPT="0"; BACKUP_PASSWORD="" ;;
          *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; continue ;;
        esac

        if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
          while true; do
            prev_password="$BACKUP_PASSWORD"
            input="$(ask_secret_value_nav "$(tr_text "Пароль шифрования (мин. 8 символов)" "Encryption password (min. 8 chars)")" "$BACKUP_PASSWORD")"
            [[ "$input" == "__PBM_BACK__" ]] && return 0
            if [[ "$input" == "__PBM_PREV__" ]]; then
              step=1
              continue 2
            fi
            if [[ -n "$prev_password" && "$input" == "$prev_password" ]]; then
              BACKUP_PASSWORD="$input"
              break
            fi
            if [[ ${#input} -lt 8 ]]; then
              paint "$CLR_WARN" "$(tr_text "Пароль слишком короткий." "Password is too short.")"
              continue
            fi
            confirm="$(ask_secret_value_nav "$(tr_text "Подтвердите пароль" "Confirm password")" "")"
            [[ "$confirm" == "__PBM_BACK__" ]] && return 0
            if [[ "$confirm" == "__PBM_PREV__" ]]; then
              continue
            fi
            if [[ "$confirm" != "$input" ]]; then
              paint "$CLR_WARN" "$(tr_text "Пароли не совпадают." "Passwords do not match.")"
              continue
            fi
            BACKUP_PASSWORD="$input"
            break
          done
        fi

        step=3
        ;;
      3)
        draw_header "$(tr_text "Быстрая настройка" "Quick setup")" "$(tr_text "Шаг 3/3: Расписание" "Step 3/3: Schedule")"
        paint "$CLR_MUTED" "$(tr_text "1) Ежедневно 03:40 UTC  2) Каждые 12 часов  3) Каждые 6 часов  4) Каждый час  5) Свой OnCalendar" "1) Daily 03:40 UTC  2) Every 12h  3) Every 6h  4) Hourly  5) Custom OnCalendar")"
        read -r -p "$(tr_text "Выбор [1-5], p назад, b выход: " "Choice [1-5], p back, b exit: ")" input
        if is_back_command "$input"; then
          return 0
        fi
        if is_prev_command "$input"; then
          step=2
          continue
        fi
        case "$input" in
          1) BACKUP_ON_CALENDAR="*-*-* 03:40:00 UTC" ;;
          2) BACKUP_ON_CALENDAR="*-*-* 00,12:00:00 UTC" ;;
          3) BACKUP_ON_CALENDAR="*-*-* 00,06,12,18:00:00 UTC" ;;
          4) BACKUP_ON_CALENDAR="hourly" ;;
          5)
            input="$(ask_value_nav "$(tr_text "Введите OnCalendar" "Enter OnCalendar")" "$BACKUP_ON_CALENDAR")"
            [[ "$input" == "__PBM_BACK__" ]] && return 0
            if [[ "$input" == "__PBM_PREV__" ]]; then
              step=2
              continue
            fi
            [[ -n "$input" ]] && BACKUP_ON_CALENDAR="$input"
            ;;
          *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; continue ;;
        esac

        show_quick_setup_summary "$old_bot" "$old_admin" "$old_thread" "$old_dir" "$old_lang" "$old_encrypt" "$old_password" "$old_calendar" "$old_include"
        if ! ask_yes_no "$(tr_text "Сохранить эти изменения?" "Save these changes?")" "y"; then
          [[ "$?" == "2" ]] && { step=2; continue; }
          paint "$CLR_WARN" "$(tr_text "Изменения отменены." "Changes cancelled.")"
          wait_for_enter
          return 0
        fi

        write_env
        write_timer_unit
        $SUDO systemctl daemon-reload
        if $SUDO systemctl is-enabled --quiet panel-backup.timer 2>/dev/null; then
          $SUDO systemctl restart panel-backup.timer || true
        fi
        paint "$CLR_OK" "$(tr_text "Быстрая настройка применена." "Quick setup applied.")"
        wait_for_enter
        return 0
        ;;
    esac
  done
}

menu_flow_encryption_settings() {
  local choice=""
  local val=""
  local confirm_val=""
  local previous_password=""
  local encrypt_state=""
  local password_state=""

  while true; do
    load_existing_env_defaults
    if [[ "${BACKUP_ENCRYPT:-0}" == "1" ]]; then
      encrypt_state="$(tr_text "включено (GPG)" "enabled (GPG)")"
    else
      encrypt_state="$(tr_text "выключено" "disabled")"
    fi
    if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
      password_state="$(mask_secret "$BACKUP_PASSWORD")"
    else
      password_state="$(tr_text "не задан" "not set")"
    fi

    draw_header "$(tr_text "Настройки шифрования backup" "Backup encryption settings")"
    show_back_hint
    paint "$CLR_MUTED" "  $(tr_text "Шифрование:" "Encryption:") ${encrypt_state}"
    paint "$CLR_MUTED" "  $(tr_text "Пароль:" "Password:") ${password_state}"
    print_separator
    menu_option "1" "$(tr_text "Включить шифрование и задать пароль" "Enable encryption and set password")"
    menu_option "2" "$(tr_text "Изменить пароль шифрования" "Change encryption password")"
    menu_option "3" "$(tr_text "Выключить шифрование" "Disable encryption")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      break
    fi

    case "$choice" in
      1)
        val="$(ask_secret_value "$(tr_text "Введите пароль шифрования (минимум 8 символов)" "Enter encryption password (minimum 8 characters)")" "$BACKUP_PASSWORD")"
        [[ "$val" == "__PBM_BACK__" ]] && continue
        previous_password="$BACKUP_PASSWORD"
        if [[ -n "$previous_password" && "$val" == "$previous_password" ]]; then
          BACKUP_ENCRYPT="1"
          BACKUP_PASSWORD="$val"
          write_env
          paint "$CLR_OK" "$(tr_text "Шифрование включено, текущий пароль сохранен." "Encryption enabled, current password retained.")"
          wait_for_enter
          continue
        fi
        if [[ ${#val} -lt 8 ]]; then
          paint "$CLR_WARN" "$(tr_text "Пароль должен быть не короче 8 символов." "Password must be at least 8 characters long.")"
          wait_for_enter
          continue
        fi
        confirm_val="$(ask_secret_value "$(tr_text "Подтвердите пароль шифрования" "Confirm encryption password")" "")"
        [[ "$confirm_val" == "__PBM_BACK__" ]] && continue
        if [[ "$confirm_val" != "$val" ]]; then
          paint "$CLR_WARN" "$(tr_text "Пароли не совпадают." "Passwords do not match.")"
          wait_for_enter
          continue
        fi
        BACKUP_ENCRYPT="1"
        BACKUP_PASSWORD="$val"
        write_env
        paint "$CLR_OK" "$(tr_text "Шифрование включено, пароль сохранен." "Encryption enabled, password saved.")"
        wait_for_enter
        ;;
      2)
        if [[ "${BACKUP_ENCRYPT:-0}" != "1" ]]; then
          paint "$CLR_WARN" "$(tr_text "Сначала включите шифрование." "Enable encryption first.")"
          wait_for_enter
          continue
        fi
        val="$(ask_secret_value "$(tr_text "Новый пароль шифрования (минимум 8 символов)" "New encryption password (minimum 8 characters)")" "$BACKUP_PASSWORD")"
        [[ "$val" == "__PBM_BACK__" ]] && continue
        previous_password="$BACKUP_PASSWORD"
        if [[ -n "$previous_password" && "$val" == "$previous_password" ]]; then
          paint "$CLR_OK" "$(tr_text "Пароль не изменен." "Password unchanged.")"
          wait_for_enter
          continue
        fi
        if [[ ${#val} -lt 8 ]]; then
          paint "$CLR_WARN" "$(tr_text "Пароль должен быть не короче 8 символов." "Password must be at least 8 characters long.")"
          wait_for_enter
          continue
        fi
        confirm_val="$(ask_secret_value "$(tr_text "Подтвердите новый пароль" "Confirm new password")" "")"
        [[ "$confirm_val" == "__PBM_BACK__" ]] && continue
        if [[ "$confirm_val" != "$val" ]]; then
          paint "$CLR_WARN" "$(tr_text "Пароли не совпадают." "Passwords do not match.")"
          wait_for_enter
          continue
        fi
        BACKUP_PASSWORD="$val"
        write_env
        paint "$CLR_OK" "$(tr_text "Пароль шифрования обновлен." "Encryption password updated.")"
        wait_for_enter
        ;;
      3)
        if ask_yes_no "$(tr_text "Выключить шифрование и удалить пароль из конфигурации?" "Disable encryption and remove password from config?")" "y"; then
          BACKUP_ENCRYPT="0"
          BACKUP_PASSWORD=""
          write_env
          paint "$CLR_OK" "$(tr_text "Шифрование выключено." "Encryption disabled.")"
        fi
        wait_for_enter
        ;;
      4) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_setup() {
  local choice=""
  local tg_state=""
  local enc_state=""
  local include_state=""
  while true; do
    load_existing_env_defaults
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_ADMIN_ID:-}" ]]; then
      tg_state="$(tr_text "настроен" "configured")"
    else
      tg_state="$(tr_text "не настроен" "not configured")"
    fi
    if [[ "${BACKUP_ENCRYPT:-0}" == "1" ]]; then
      enc_state="$(tr_text "включено" "enabled")"
    else
      enc_state="$(tr_text "выключено" "disabled")"
    fi
    include_state="${BACKUP_INCLUDE:-all}"
    draw_header "$(tr_text "Раздел: Установка и настройка" "Section: Setup and configuration")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Здесь первичная установка и изменение конфигурации." "Use this section for initial install and config changes.")"
    paint "$CLR_MUTED" "$(tr_text "Текущее состояние:" "Current state:") Telegram=${tg_state}, $(tr_text "шифрование" "encryption")=${enc_state}, $(tr_text "состав" "scope")=${include_state}"
    menu_option "1" "$(tr_text "Установить/обновить файлы + первичная настройка" "Install/update files + initial setup")"
    menu_option "2" "$(tr_text "Быстрая настройка (3 шага)" "Quick setup (3 steps)")"
    menu_option "3" "$(tr_text "Настройки шифрования backup" "Backup encryption settings")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_flow_install_and_setup ;;
      2) menu_flow_quick_setup ;;
      3) menu_flow_encryption_settings ;;
      4) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

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
        path="$(ask_value "$(tr_text "Путь к backup-архиву (.tar.gz или .tar.gz.gpg)" "Path to backup archive (.tar.gz or .tar.gz.gpg)")" "$BACKUP_FILE")"
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
    menu_option "1" "$(tr_text "Включить таймер backup" "Enable backup timer")"
    menu_option "2" "$(tr_text "Выключить таймер backup" "Disable backup timer")"
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
