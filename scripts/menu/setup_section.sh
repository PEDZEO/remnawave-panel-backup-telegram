#!/usr/bin/env bash
# Setup and configuration section flows for interactive menu.

menu_flow_install_and_setup() {
  local old_bot=""
  local old_admin=""
  local old_thread=""
  local old_dir=""
  local old_bedolaga_bot_dir=""
  local old_bedolaga_cabinet_dir=""
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
  old_bedolaga_bot_dir="${BEDOLAGA_BOT_DIR:-}"
  old_bedolaga_cabinet_dir="${BEDOLAGA_CABINET_DIR:-}"
  old_lang="$BACKUP_LANG"
  old_encrypt="$BACKUP_ENCRYPT"
  old_password="$BACKUP_PASSWORD"
  old_calendar="$BACKUP_ON_CALENDAR"
  old_include="$BACKUP_INCLUDE"

  draw_subheader "$(tr_text "Установка и настройка" "Install and configure")"
  paint "$CLR_MUTED" "$(tr_text "Используйте этот пункт при первом запуске или обновлении скриптов." "Use this on first run or when updating scripts.")"
  if ! prompt_install_settings; then
    return 0
  fi
  show_quick_setup_summary "$old_bot" "$old_admin" "$old_thread" "$old_dir" "$old_bedolaga_bot_dir" "$old_bedolaga_cabinet_dir" "$old_lang" "$old_encrypt" "$old_password" "$old_calendar" "$old_include"
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
  if ask_yes_no "$(tr_text "Включить таймер резервного копирования сейчас?" "Enable backup timer now?")" "y"; then
    enable_timer
  else
    case $? in
      1)
        paint "$CLR_WARN" "$(tr_text "Таймер не включен. Позже можно включить так:" "Timer was not enabled. You can enable later with:")"
        paint "$CLR_MUTED" "  sudo systemctl enable --now panel-backup-panel.timer"
        paint "$CLR_MUTED" "  sudo systemctl enable --now panel-backup-bedolaga.timer"
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
  local old_bedolaga_bot_dir="$5"
  local old_bedolaga_cabinet_dir="$6"
  local old_lang="$7"
  local old_encrypt="$8"
  local old_password="$9"
  local old_calendar="${10}"
  local old_include="${11}"

  draw_subheader "$(tr_text "Краткий итог изменений" "Quick changes summary")"
  paint "$CLR_MUTED" "$(tr_text "Легенда: * изменено, = без изменений." "Legend: * changed, = unchanged.")"
  print_separator
  render_change_line "TELEGRAM_BOT_TOKEN" "$old_bot" "$TELEGRAM_BOT_TOKEN"
  render_change_line "TELEGRAM_ADMIN_ID" "$old_admin" "$TELEGRAM_ADMIN_ID"
  render_change_line "TELEGRAM_THREAD_ID" "$old_thread" "$TELEGRAM_THREAD_ID"
  render_change_line "REMNAWAVE_DIR" "$old_dir" "$REMNAWAVE_DIR"
  render_change_line "BEDOLAGA_BOT_DIR" "$old_bedolaga_bot_dir" "${BEDOLAGA_BOT_DIR:-}"
  render_change_line "BEDOLAGA_CABINET_DIR" "$old_bedolaga_cabinet_dir" "${BEDOLAGA_CABINET_DIR:-}"
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
  local old_bedolaga_bot_dir=""
  local old_bedolaga_cabinet_dir=""
  local old_lang=""
  local old_encrypt=""
  local old_password=""
  local old_calendar=""
  local old_include=""
  local prev_password=""
  local setup_scope="${BACKUP_SETUP_SCOPE:-global}"

  load_existing_env_defaults
  old_bot="$TELEGRAM_BOT_TOKEN"
  old_admin="$TELEGRAM_ADMIN_ID"
  old_thread="$TELEGRAM_THREAD_ID"
  old_dir="$REMNAWAVE_DIR"
  old_bedolaga_bot_dir="${BEDOLAGA_BOT_DIR:-}"
  old_bedolaga_cabinet_dir="${BEDOLAGA_CABINET_DIR:-}"
  old_lang="$BACKUP_LANG"
  old_encrypt="$BACKUP_ENCRYPT"
  old_password="$BACKUP_PASSWORD"
  old_calendar="$BACKUP_ON_CALENDAR"
  old_include="$BACKUP_INCLUDE"

  while true; do
    case "$step" in
      1)
        draw_subheader "$(tr_text "Быстрая настройка" "Quick setup")" "$(tr_text "Шаг 1/3: Telegram и пути проектов" "Step 1/3: Telegram and project paths")"
        paint "$CLR_MUTED" "$(tr_text "Команды: b = выход из мастера, p = предыдущий шаг." "Commands: b = exit wizard, p = previous step.")"
        if [[ "$setup_scope" == "panel" ]]; then
          paint "$CLR_MUTED" "$(tr_text "Раздел панели: укажите путь к Remnawave." "Panel section: provide the Remnawave path.")"
        elif [[ "$setup_scope" == "bedolaga" ]]; then
          paint "$CLR_MUTED" "$(tr_text "Раздел Bedolaga: укажите путь бота и путь кабинета." "Bedolaga section: provide bot and cabinet paths.")"
        else
          paint "$CLR_MUTED" "$(tr_text "Глобальный раздел: можно задать путь панели, бота и кабинета." "Global section: you can set panel, bot and cabinet paths.")"
        fi

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

        if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_ADMIN_ID:-}" ]]; then
          if ask_yes_no "$(tr_text "Проверить отправку в Telegram сейчас?" "Test Telegram delivery now?")" "y"; then
            while ! test_telegram_delivery "$setup_scope"; do
              paint "$CLR_WARN" "$(tr_text "Telegram не прошел проверку. Исправьте токен/chat_id/topic или продолжите без проверки." "Telegram check failed. Fix token/chat_id/topic or continue without verification.")"
              menu_option "1" "$(tr_text "Исправить Telegram" "Fix Telegram")"
              menu_option "2" "$(tr_text "Продолжить без проверки" "Continue without verification")"
              menu_option "3" "$(tr_text "Отключить Telegram" "Disable Telegram")"
              print_separator
              read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" input
              case "$input" in
                1) menu_flow_telegram_settings "$setup_scope" ;;
                2) break ;;
                3)
                  TELEGRAM_DELIVERY_MODE="local"
                  TELEGRAM_BOT_TOKEN=""
                  TELEGRAM_ADMIN_ID=""
                  TELEGRAM_THREAD_ID=""
                  TELEGRAM_THREAD_ID_PANEL=""
                  TELEGRAM_THREAD_ID_BEDOLAGA=""
                  break
                  ;;
                *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")" ;;
              esac
            done
          fi
        fi

        if [[ "$setup_scope" != "bedolaga" ]]; then
          while true; do
            input="$(ask_value_nav "$(tr_text "Путь к Remnawave (панель)" "Remnawave path (panel)")" "$REMNAWAVE_DIR")"
            [[ "$input" == "__PBM_BACK__" ]] && return 0
            if [[ "$input" == "__PBM_PREV__" ]]; then
              step=1
              continue 2
            fi
            if ! validate_project_path_or_warn "REMNAWAVE_DIR" "$input"; then
              continue
            fi
            REMNAWAVE_DIR="$input"
            break
          done
        fi

        if [[ "$setup_scope" != "panel" ]]; then
          while true; do
            input="$(ask_value_nav "$(tr_text "Путь к Bedolaga боту" "Bedolaga bot path")" "${BEDOLAGA_BOT_DIR:-}")"
            [[ "$input" == "__PBM_BACK__" ]] && return 0
            if [[ "$input" == "__PBM_PREV__" ]]; then
              step=1
              continue 2
            fi
            if ! validate_project_path_or_warn "BEDOLAGA_BOT_DIR" "$input"; then
              continue
            fi
            BEDOLAGA_BOT_DIR="$input"
            break
          done

          while true; do
            input="$(ask_value_nav "$(tr_text "Путь к Bedolaga кабинету (docker или npm)" "Bedolaga cabinet path (docker or npm)")" "${BEDOLAGA_CABINET_DIR:-}")"
            [[ "$input" == "__PBM_BACK__" ]] && return 0
            if [[ "$input" == "__PBM_PREV__" ]]; then
              step=1
              continue 2
            fi
            if ! validate_project_path_or_warn "BEDOLAGA_CABINET_DIR" "$input"; then
              continue
            fi
            BEDOLAGA_CABINET_DIR="$input"
            break
          done
        fi

        while true; do
          input="$(ask_value_nav "$(tr_text "Язык описания резервной копии (ru/en)" "Backup language (ru/en)")" "$BACKUP_LANG")"
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
        draw_subheader "$(tr_text "Быстрая настройка" "Quick setup")" "$(tr_text "Шаг 2/3: Шифрование" "Step 2/3: Encryption")"
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
        draw_subheader "$(tr_text "Быстрая настройка" "Quick setup")" "$(tr_text "Шаг 3/3: Расписание" "Step 3/3: Schedule")"
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
            [[ -n "$input" ]] || continue
            if ! validate_oncalendar_or_warn "$input"; then
              continue
            fi
            BACKUP_ON_CALENDAR="$input"
            ;;
          *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; continue ;;
        esac
        if [[ "${BACKUP_SETUP_SCOPE:-global}" == "panel" ]]; then
          BACKUP_ON_CALENDAR_PANEL="$BACKUP_ON_CALENDAR"
        elif [[ "${BACKUP_SETUP_SCOPE:-global}" == "bedolaga" ]]; then
          BACKUP_ON_CALENDAR_BEDOLAGA="$BACKUP_ON_CALENDAR"
        else
          BACKUP_ON_CALENDAR_PANEL="$BACKUP_ON_CALENDAR"
          BACKUP_ON_CALENDAR_BEDOLAGA="$BACKUP_ON_CALENDAR"
        fi

        show_quick_setup_summary "$old_bot" "$old_admin" "$old_thread" "$old_dir" "$old_bedolaga_bot_dir" "$old_bedolaga_cabinet_dir" "$old_lang" "$old_encrypt" "$old_password" "$old_calendar" "$old_include"
        if ! ask_yes_no "$(tr_text "Сохранить эти изменения?" "Save these changes?")" "y"; then
          [[ "$?" == "2" ]] && { step=2; continue; }
          paint "$CLR_WARN" "$(tr_text "Изменения отменены." "Changes cancelled.")"
          wait_for_enter
          return 0
        fi

        write_env
        write_timer_unit
        $SUDO systemctl daemon-reload
        if $SUDO systemctl is-enabled --quiet panel-backup-panel.timer 2>/dev/null; then
          if ! $SUDO systemctl restart panel-backup-panel.timer; then
            paint "$CLR_WARN" "$(tr_text "Не удалось перезапустить timer панели после изменений." "Failed to restart panel timer after changes.")"
          fi
        fi
        if $SUDO systemctl is-enabled --quiet panel-backup-bedolaga.timer 2>/dev/null; then
          if ! $SUDO systemctl restart panel-backup-bedolaga.timer; then
            paint "$CLR_WARN" "$(tr_text "Не удалось перезапустить timer Bedolaga после изменений." "Failed to restart Bedolaga timer after changes.")"
          fi
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

    draw_subheader "$(tr_text "Настройки шифрования резервной копии" "Backup encryption settings")"
    show_back_hint
    paint "$CLR_MUTED" "  $(tr_text "Шифрование:" "Encryption:") ${encrypt_state}"
    paint "$CLR_MUTED" "  $(tr_text "Пароль:" "Password:") ${password_state}"
    print_separator
    menu_group "$(tr_text "Шифрование" "Encryption")" "$CLR_OK"
    menu_option "1" "$(tr_text "Включить шифрование и задать пароль" "Enable encryption and set password")"
    menu_option "2" "$(tr_text "Изменить пароль шифрования" "Change encryption password")"
    menu_group "$(tr_text "Отключение" "Disable")" "$CLR_DANGER"
    menu_option "3" "$(tr_text "Выключить шифрование" "Disable encryption")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
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

format_backup_scope_label() {
  local raw="${1:-all}"
  case "${raw,,}" in
    all,bedolaga|bedolaga,all) echo "$(tr_text "полный (панель + бот + кабинет)" "full (panel + bot + cabinet)")" ;;
    all) echo "$(tr_text "всё (панель: db + redis + конфиги)" "all (panel: db + redis + configs)")" ;;
    db) echo "$(tr_text "только PostgreSQL (db)" "PostgreSQL only (db)")" ;;
    redis) echo "$(tr_text "только Redis (redis)" "Redis only (redis)")" ;;
    configs,bedolaga-configs|bedolaga-configs,configs) echo "$(tr_text "конфиги (панель + бот + кабинет)" "configs (panel + bot + cabinet)")" ;;
    configs) echo "$(tr_text "только конфиги панели (configs)" "panel configs only (configs)")" ;;
    bedolaga) echo "$(tr_text "только Bedolaga (db + redis + bot + cabinet)" "Bedolaga only (db + redis + bot + cabinet)")" ;;
    bedolaga-fork|bedolaga-fork-db|bedolaga-fork-db,bedolaga-fork-redis) echo "$(tr_text "Bedolaga fork: DB" "Bedolaga fork: DB")" ;;
    bedolaga-official|bedolaga-official-db|bedolaga-official-db,bedolaga-official-redis) echo "$(tr_text "Bedolaga official: DB" "Bedolaga official: DB")" ;;
    bedolaga-bot,bedolaga-cabinet|bedolaga-cabinet,bedolaga-bot|bedolaga-configs) echo "$(tr_text "файлы Bedolaga (бот + кабинет, без DB)" "Bedolaga files (bot + cabinet, no DB)")" ;;
    *) echo "${raw}" ;;
  esac
}

telegram_thread_for_scope() {
  local scope="${1:-panel}"

  case "$scope" in
    bedolaga)
      if [[ -n "${TELEGRAM_THREAD_ID_BEDOLAGA:-}" ]]; then
        printf '%s' "$TELEGRAM_THREAD_ID_BEDOLAGA"
        return 0
      fi
      ;;
    panel)
      if [[ -n "${TELEGRAM_THREAD_ID_PANEL:-}" ]]; then
        printf '%s' "$TELEGRAM_THREAD_ID_PANEL"
        return 0
      fi
      ;;
  esac

  printf '%s' "${TELEGRAM_THREAD_ID:-}"
}

telegram_chat_id_for_send() {
  local raw="${TELEGRAM_ADMIN_ID:-}"
  local thread_id="${1:-}"

  [[ -n "$raw" ]] || return 0
  if [[ "$raw" =~ ^-100[0-9]+$ ]]; then
    printf '%s' "$raw"
  elif [[ "$raw" =~ ^[0-9]+$ && -n "$thread_id" ]]; then
    printf '%s' "-100${raw}"
  else
    printf '%s' "$raw"
  fi
}

test_telegram_delivery() {
  local scope="${1:-panel}"
  local thread_id=""
  local chat_id=""
  local response=""
  local response_desc=""
  local test_text=""
  local -a thread_args=()

  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_ADMIN_ID:-}" ]]; then
    paint "$CLR_WARN" "$(tr_text "Сначала укажите токен бота и chat_id." "Set bot token and chat_id first.")"
    return 1
  fi
  if ! is_valid_telegram_token "$TELEGRAM_BOT_TOKEN"; then
    paint "$CLR_WARN" "$(tr_text "Токен выглядит неверно. Откройте пункт редактирования токена." "Token format looks invalid. Open token edit first.")"
    return 1
  fi
  if ! is_valid_telegram_id "$TELEGRAM_ADMIN_ID"; then
    paint "$CLR_WARN" "$(tr_text "chat_id должен быть числом." "chat_id must be numeric.")"
    return 1
  fi

  thread_id="$(telegram_thread_for_scope "$scope")"
  if [[ -n "$thread_id" ]]; then
    if ! is_valid_telegram_id "$thread_id"; then
      paint "$CLR_WARN" "$(tr_text "ID темы должен быть числом." "Thread ID must be numeric.")"
      return 1
    fi
    thread_args+=(-d "message_thread_id=${thread_id}")
  fi
  chat_id="$(telegram_chat_id_for_send "$thread_id")"
  test_text="$(tr_text "Проверка Telegram для backup. Если видите это сообщение, токен и chat_id работают." "Telegram backup test. If you see this message, token and chat_id work.")"

  response="$(curl -sS --max-time 20 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${chat_id}" \
    "${thread_args[@]}" \
    --data-urlencode "text=${test_text}")" || {
      paint "$CLR_WARN" "$(tr_text "Не удалось подключиться к Telegram API." "Could not reach Telegram API.")"
      return 1
    }

  if echo "$response" | grep -q '"ok":true'; then
    paint "$CLR_OK" "$(tr_text "Telegram проверен: сообщение отправлено." "Telegram verified: message sent.")"
    return 0
  fi

  response_desc="$(echo "$response" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')"
  [[ -n "$response_desc" ]] || response_desc="$response"
  paint "$CLR_WARN" "$(tr_text "Telegram не принял сообщение:" "Telegram rejected the message:") ${response_desc}"
  case "${response_desc,,}" in
    *"unauthorized"*|*"not found"*)
      paint "$CLR_MUTED" "$(tr_text "Проверьте токен бота: чаще всего ошибка именно в нем." "Check the bot token: this is the most common cause.")"
      ;;
    *"chat not found"*|*"forbidden"*|*"not enough rights"*|*"have no rights"*)
      paint "$CLR_MUTED" "$(tr_text "Проверьте chat_id и добавьте бота в чат/канал с правом отправки." "Check chat_id and add the bot to the chat/channel with send permission.")"
      ;;
    *"message thread not found"*)
      paint "$CLR_MUTED" "$(tr_text "Проверьте ID темы или очистите поле topic." "Check the topic ID or clear the topic field.")"
      ;;
  esac
  return 1
}

menu_flow_telegram_settings() {
  local scope="${1:-global}"
  local choice=""
  local val=""
  local token_state=""
  local chat_state=""
  local thread_state=""
  local thread_label=""
  local title=""

  while true; do
    load_existing_env_defaults
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
      token_state="$(mask_secret "$TELEGRAM_BOT_TOKEN")"
    else
      token_state="$(tr_text "не задан" "not set")"
    fi
    chat_state="${TELEGRAM_ADMIN_ID:-$(tr_text "не задан" "not set")}"
    thread_state="$(telegram_thread_for_scope "$scope")"
    thread_state="${thread_state:-$(tr_text "не задан" "not set")}"
    case "$scope" in
      panel)
        title="$(tr_text "Telegram для backup панели" "Telegram for panel backup")"
        thread_label="$(tr_text "Topic панели" "Panel topic")"
        ;;
      bedolaga)
        title="$(tr_text "Telegram для backup Bedolaga" "Telegram for Bedolaga backup")"
        thread_label="$(tr_text "Topic Bedolaga" "Bedolaga topic")"
        ;;
      *)
        title="$(tr_text "Telegram для backup" "Telegram for backup")"
        thread_label="$(tr_text "Topic по умолчанию" "Default topic")"
        ;;
    esac

    draw_subheader "$title"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Локальный архив создается всегда. Telegram нужен только для отправки копии в чат." "A local archive is always created. Telegram only sends an extra copy to chat.")"
    paint "$CLR_TITLE" "$(tr_text "Текущие значения" "Current values")"
    paint "$CLR_MUTED" "  TELEGRAM_BOT_TOKEN: ${token_state}"
    paint "$CLR_MUTED" "  TELEGRAM_ADMIN_ID: ${chat_state}"
    paint "$CLR_MUTED" "  ${thread_label}: ${thread_state}"
    print_separator
    menu_group "$(tr_text "Данные Telegram" "Telegram details")" "$CLR_ACCENT"
    menu_option "1" "$(tr_text "Изменить токен бота" "Edit bot token")"
    menu_option "2" "$(tr_text "Изменить chat_id" "Edit chat_id")"
    menu_option "3" "$(tr_text "Изменить topic/thread_id (необязательно)" "Edit topic/thread_id (optional)")"
    menu_group "$(tr_text "Проверка" "Check")" "$CLR_WARN"
    menu_option "4" "$(tr_text "Проверить отправку в Telegram" "Check Telegram delivery")"
    menu_group "$(tr_text "Отключение" "Disable")" "$CLR_DANGER"
    menu_option "5" "$(tr_text "Отключить Telegram-отправку" "Disable Telegram delivery")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      break
    fi

    case "$choice" in
      1)
        while true; do
          val="$(ask_value "$(tr_text "Токен Telegram-бота" "Telegram bot token")" "$TELEGRAM_BOT_TOKEN")"
          [[ "$val" == "__PBM_BACK__" ]] && break
          if [[ -z "$val" ]] || ! is_valid_telegram_token "$val"; then
            paint "$CLR_WARN" "$(tr_text "Некорректный токен. Формат должен быть вида 123456:ABCDEF..." "Invalid token. Format must look like 123456:ABCDEF...")"
            continue
          fi
          TELEGRAM_BOT_TOKEN="$val"
          TELEGRAM_DELIVERY_MODE="telegram"
          write_env
          paint "$CLR_OK" "$(tr_text "Токен сохранен." "Token saved.")"
          wait_for_enter
          break
        done
        ;;
      2)
        while true; do
          val="$(ask_value "$(tr_text "ID чата/канала Telegram" "Telegram chat/channel ID")" "$TELEGRAM_ADMIN_ID")"
          [[ "$val" == "__PBM_BACK__" ]] && break
          if [[ -z "$val" ]] || ! is_valid_telegram_id "$val"; then
            paint "$CLR_WARN" "$(tr_text "chat_id должен быть числом, например 123456789 или -1001234567890." "chat_id must be numeric, for example 123456789 or -1001234567890.")"
            continue
          fi
          TELEGRAM_ADMIN_ID="$val"
          TELEGRAM_DELIVERY_MODE="telegram"
          write_env
          paint "$CLR_OK" "$(tr_text "chat_id сохранен." "chat_id saved.")"
          wait_for_enter
          break
        done
        ;;
      3)
        while true; do
          val="$(ask_value_clearable "$(tr_text "ID темы/topic (- очистить)" "Topic/thread ID (- to clear)")" "$(telegram_thread_for_scope "$scope")")"
          [[ "$val" == "__PBM_BACK__" ]] && break
          if [[ -n "$val" ]] && ! is_valid_telegram_id "$val"; then
            paint "$CLR_WARN" "$(tr_text "ID темы должен быть числом." "Thread ID must be numeric.")"
            continue
          fi
          case "$scope" in
            panel) TELEGRAM_THREAD_ID_PANEL="${val:-__PBM_CLEAR__}" ;;
            bedolaga) TELEGRAM_THREAD_ID_BEDOLAGA="${val:-__PBM_CLEAR__}" ;;
            *) TELEGRAM_THREAD_ID="${val:-__PBM_CLEAR__}" ;;
          esac
          TELEGRAM_DELIVERY_MODE="telegram"
          write_env
          paint "$CLR_OK" "$(tr_text "Topic сохранен." "Topic saved.")"
          wait_for_enter
          break
        done
        ;;
      4)
        test_telegram_delivery "$scope" || true
        wait_for_enter
        ;;
      5)
        if ask_yes_no "$(tr_text "Отключить Telegram и удалить токен/chat_id из конфига?" "Disable Telegram and remove token/chat_id from config?")" "n"; then
          TELEGRAM_DELIVERY_MODE="local"
          TELEGRAM_BOT_TOKEN=""
          TELEGRAM_ADMIN_ID=""
          TELEGRAM_THREAD_ID=""
          TELEGRAM_THREAD_ID_PANEL=""
          TELEGRAM_THREAD_ID_BEDOLAGA=""
          write_env
          paint "$CLR_OK" "$(tr_text "Telegram отключен. Backup останется локальным." "Telegram disabled. Backup will remain local.")"
        fi
        wait_for_enter
        ;;
      6) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_flow_backup_scope_settings() {
  local scope="${1:-global}"
  local choice=""
  local val=""
  local include_state=""
  local title=""
  local scope_hint=""

  while true; do
    load_existing_env_defaults
    include_state="$(format_backup_scope_label "${BACKUP_INCLUDE:-all}")"
    case "$scope" in
      panel)
        title="$(tr_text "Состав backup панели" "Panel backup scope")"
        scope_hint="$(tr_text "Быстрая кнопка backup панели всегда делает полный backup панели. Эта настройка нужна для общего MODE=backup и кастомного запуска." "The quick panel backup button always runs a full panel backup. This setting is for generic MODE=backup and custom runs.")"
        ;;
      bedolaga)
        title="$(tr_text "Состав backup Bedolaga" "Bedolaga backup scope")"
        scope_hint="$(tr_text "Быстрая кнопка полного Bedolaga делает полный backup. Эта настройка нужна для общего MODE=backup и кастомного запуска." "The quick full Bedolaga button runs a full backup. This setting is for generic MODE=backup and custom runs.")"
        ;;
      *)
        title="$(tr_text "Состав backup" "Backup scope")"
        scope_hint="$(tr_text "Это влияет на общий MODE=backup и кастомный запуск backup." "This affects generic MODE=backup and custom backup runs.")"
        ;;
    esac

    draw_subheader "$title"
    show_back_hint
    paint "$CLR_MUTED" "$scope_hint"
    paint "$CLR_MUTED" "$(tr_text "Текущий состав:" "Current scope:") ${include_state} (${BACKUP_INCLUDE:-all})"
    print_separator
    if [[ "$scope" == "panel" ]]; then
      menu_group "$(tr_text "Готовые варианты" "Presets")" "$CLR_OK"
      menu_option "1" "$(tr_text "Полная панель: DB + Redis + .env + compose + Caddy + subscription" "Full panel: DB + Redis + .env + compose + Caddy + subscription")"
      menu_option "2" "$(tr_text "Только DB + Redis панели" "Panel DB + Redis only")"
      menu_option "3" "$(tr_text "Только конфиги панели" "Panel configs only")"
      menu_group "$(tr_text "Расширенное" "Advanced")" "$CLR_ACCENT"
      menu_option "4" "$(tr_text "Свой список компонентов панели" "Custom panel component list")"
      menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
      menu_option "5" "$(tr_text "Назад" "Back")"
      print_separator
      read -r -p "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")" choice
    elif [[ "$scope" == "bedolaga" ]]; then
      menu_group "$(tr_text "Готовые варианты" "Presets")" "$CLR_OK"
      menu_option "1" "$(tr_text "Полный Bedolaga: DB + Redis + бот + кабинет" "Full Bedolaga: DB + Redis + bot + cabinet")"
      menu_option "2" "$(tr_text "Файлы бота + кабинета без DB/Redis" "Bot + cabinet files without DB/Redis")"
      menu_option "3" "$(tr_text "Только конфиги Bedolaga" "Bedolaga configs only")"
      menu_group "$(tr_text "Расширенное" "Advanced")" "$CLR_ACCENT"
      menu_option "4" "$(tr_text "Свой список компонентов Bedolaga" "Custom Bedolaga component list")"
      menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
      menu_option "5" "$(tr_text "Назад" "Back")"
      print_separator
      read -r -p "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")" choice
    else
      menu_group "$(tr_text "Готовые варианты" "Presets")" "$CLR_OK"
      menu_option "1" "$(tr_text "Только панель Remnawave" "Remnawave panel only")"
      menu_option "2" "$(tr_text "Только Bedolaga" "Bedolaga only")"
      menu_option "3" "$(tr_text "Панель + Bedolaga" "Panel + Bedolaga")"
      menu_group "$(tr_text "Расширенное" "Advanced")" "$CLR_ACCENT"
      menu_option "4" "$(tr_text "Свой список компонентов" "Custom component list")"
      menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
      menu_option "5" "$(tr_text "Назад" "Back")"
      print_separator
      read -r -p "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")" choice
    fi

    if is_back_command "$choice"; then
      break
    fi

    case "$scope:$choice" in
      panel:1) BACKUP_INCLUDE="all" ;;
      panel:2) BACKUP_INCLUDE="db,redis" ;;
      panel:3) BACKUP_INCLUDE="configs" ;;
      panel:4)
        val="$(ask_value "$(tr_text "Компоненты панели через запятую: all,db,redis,configs,env,compose,caddy,subscription" "Panel components: all,db,redis,configs,env,compose,caddy,subscription")" "$BACKUP_INCLUDE")"
        [[ "$val" == "__PBM_BACK__" ]] && continue
        validate_component_list_or_warn "panel" "$val" || { wait_for_enter; continue; }
        BACKUP_INCLUDE="$(normalize_component_list "$val")"
        ;;
      bedolaga:1) BACKUP_INCLUDE="bedolaga" ;;
      bedolaga:2) BACKUP_INCLUDE="bedolaga-bot,bedolaga-cabinet" ;;
      bedolaga:3) BACKUP_INCLUDE="bedolaga-configs" ;;
      bedolaga:4)
        val="$(ask_value "$(tr_text "Компоненты Bedolaga через запятую: bedolaga,bedolaga-fork-db,bedolaga-official-db,bedolaga-db,bedolaga-redis,bedolaga-bot,bedolaga-cabinet,bedolaga-configs" "Bedolaga components: bedolaga,bedolaga-fork-db,bedolaga-official-db,bedolaga-db,bedolaga-redis,bedolaga-bot,bedolaga-cabinet,bedolaga-configs")" "$BACKUP_INCLUDE")"
        [[ "$val" == "__PBM_BACK__" ]] && continue
        validate_component_list_or_warn "bedolaga" "$val" || { wait_for_enter; continue; }
        BACKUP_INCLUDE="$(normalize_component_list "$val")"
        ;;
      global:1) BACKUP_INCLUDE="all" ;;
      global:2) BACKUP_INCLUDE="bedolaga" ;;
      global:3) BACKUP_INCLUDE="all,bedolaga" ;;
      global:4)
        val="$(ask_value "$(tr_text "Компоненты через запятую" "Comma-separated components")" "$BACKUP_INCLUDE")"
        [[ "$val" == "__PBM_BACK__" ]] && continue
        validate_component_list_or_warn "global" "$val" || { wait_for_enter; continue; }
        BACKUP_INCLUDE="$(normalize_component_list "$val")"
        ;;
      *:5) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter; continue ;;
    esac

    write_env
    paint "$CLR_OK" "$(tr_text "Состав backup сохранен." "Backup scope saved.")"
    wait_for_enter
  done
}

menu_section_setup() {
  local choice=""
  local setup_scope="${1:-global}"
  local old_setup_scope="${BACKUP_SETUP_SCOPE:-global}"
  local tg_state=""
  local enc_state=""
  local include_state=""
  local include_state_raw=""
  local section_title=""
  local section_hint=""
  BACKUP_SETUP_SCOPE="$setup_scope"
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
    include_state_raw="${BACKUP_INCLUDE:-all}"
    include_state="$(format_backup_scope_label "$include_state_raw")"
    if [[ "$setup_scope" == "panel" ]]; then
      section_title="$(tr_text "Раздел: Настройки backup панели" "Section: Panel backup settings")"
      section_hint="$(tr_text "Только настройки резервного копирования панели Remnawave." "Panel backup settings only.")"
    elif [[ "$setup_scope" == "bedolaga" ]]; then
      section_title="$(tr_text "Раздел: Настройки backup Bedolaga" "Section: Bedolaga backup settings")"
      section_hint="$(tr_text "Только настройки резервного копирования Bedolaga (бот + кабинет)." "Bedolaga backup settings only (bot + cabinet).")"
    else
      section_title="$(tr_text "Раздел: Настройка резервного копирования" "Section: Backup setup and configuration")"
      section_hint="$(tr_text "Здесь только настройка резервного копирования и уведомлений." "This section is only for backup and notification settings.")"
    fi
    draw_subheader "$section_title"
    show_back_hint
    paint "$CLR_MUTED" "$section_hint"
    paint "$CLR_TITLE" "$(tr_text "Текущее состояние" "Current state")"
    paint "$CLR_MUTED" "  Telegram: ${tg_state}"
    paint "$CLR_MUTED" "  $(tr_text "Шифрование резервной копии:" "Backup encryption:") ${enc_state}"
    paint "$CLR_MUTED" "  $(tr_text "Состав резервной копии:" "Backup scope:") ${include_state}"
    print_separator
    menu_group "$(tr_text "Основные настройки" "Core settings")" "$CLR_ACCENT"
    menu_option "1" "$(tr_text "Telegram: токен, chat_id, проверка отправки" "Telegram: token, chat_id, delivery check")"
    menu_option "2" "$(tr_text "Состав backup" "Backup scope")"
    menu_option "3" "$(tr_text "Шифрование" "Encryption")"
    menu_group "$(tr_text "Мастер и файлы" "Wizard and files")" "$CLR_OK"
    menu_option "4" "$(tr_text "Быстрая настройка мастером" "Quick setup wizard")"
    menu_option "5" "$(tr_text "Установка/обновление файлов backup" "Install/update backup files")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_flow_telegram_settings "$setup_scope" ;;
      2) menu_flow_backup_scope_settings "$setup_scope" ;;
      3) menu_flow_encryption_settings ;;
      4) menu_flow_quick_setup ;;
      5) menu_flow_install_and_setup ;;
      6) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
  BACKUP_SETUP_SCOPE="$old_setup_scope"
}
