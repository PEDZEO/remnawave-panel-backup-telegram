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

  draw_subheader "$(tr_text "Установка и настройка" "Install and configure")"
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
  if ask_yes_no "$(tr_text "Включить таймер резервного копирования сейчас?" "Enable backup timer now?")" "y"; then
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

  draw_subheader "$(tr_text "Краткий итог изменений" "Quick changes summary")"
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
        draw_subheader "$(tr_text "Быстрая настройка" "Quick setup")" "$(tr_text "Шаг 1/3: Telegram и путь" "Step 1/3: Telegram and path")"
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
          if ! $SUDO systemctl restart panel-backup.timer; then
            paint "$CLR_WARN" "$(tr_text "Не удалось перезапустить timer после изменений." "Failed to restart timer after changes.")"
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

format_backup_scope_label() {
  local raw="${1:-all}"
  case "${raw,,}" in
    all) echo "$(tr_text "всё (db + redis + конфиги)" "all (db + redis + configs)")" ;;
    db) echo "$(tr_text "только PostgreSQL (db)" "PostgreSQL only (db)")" ;;
    redis) echo "$(tr_text "только Redis (redis)" "Redis only (redis)")" ;;
    configs) echo "$(tr_text "только конфиги (configs)" "configs only (configs)")" ;;
    *) echo "${raw}" ;;
  esac
}

menu_section_setup() {
  local choice=""
  local tg_state=""
  local enc_state=""
  local include_state=""
  local include_state_raw=""
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
    draw_subheader "$(tr_text "Раздел: Настройка резервного копирования" "Section: Backup setup and configuration")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Здесь только настройка резервного копирования и уведомлений." "This section is only for backup and notification settings.")"
    paint "$CLR_TITLE" "$(tr_text "Текущее состояние" "Current state")"
    paint "$CLR_MUTED" "  Telegram: ${tg_state}"
    paint "$CLR_MUTED" "  $(tr_text "Шифрование резервной копии:" "Backup encryption:") ${enc_state}"
    paint "$CLR_MUTED" "  $(tr_text "Состав резервной копии:" "Backup scope:") ${include_state}"
    menu_option "1" "$(tr_text "Установка/обновление" "Install/update")"
    menu_option "2" "$(tr_text "Быстрая настройка" "Quick setup")"
    menu_option "3" "$(tr_text "Шифрование" "Encryption")"
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

run_component_flow_action() {
  local action_title="$1"
  local flow_func="$2"

  if "$flow_func"; then
    paint "$CLR_OK" "$(tr_text "Операция завершена:" "Operation completed:") ${action_title}"
    wait_for_enter
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Операция завершилась с ошибкой:" "Operation failed:") ${action_title}"
  wait_for_enter
  return 1
}

menu_section_remnawave_components() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Раздел: Компоненты Remnawave" "Section: Remnawave components")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Установка и обновление панели и страницы подписок." "Install and update panel and subscription page.")"
    menu_option "1" "$(tr_text "Полная установка (панель + подписки)" "Full install (panel + subscription)")"
    menu_option "2" "$(tr_text "Установить панель Remnawave" "Install Remnawave panel")"
    menu_option "3" "$(tr_text "Установить страницу подписок" "Install subscription page")"
    menu_option "4" "$(tr_text "Полное обновление (панель + подписки)" "Full update (panel + subscription)")"
    menu_option "5" "$(tr_text "Обновить панель Remnawave" "Update Remnawave panel")"
    menu_option "6" "$(tr_text "Обновить страницу подписок" "Update subscription page")"
    menu_option "7" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-7]: " "Choice [1-7]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_component_flow_action "$(tr_text "Полная установка (панель + подписки)" "Full install (panel + subscription)")" run_remnawave_full_install_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Установить панель Remnawave" "Install Remnawave panel")" run_panel_install_flow
        ;;
      3)
        run_component_flow_action "$(tr_text "Установить страницу подписок" "Install subscription page")" run_subscription_install_flow
        ;;
      4)
        run_component_flow_action "$(tr_text "Полное обновление (панель + подписки)" "Full update (panel + subscription)")" run_remnawave_full_update_flow
        ;;
      5)
        run_component_flow_action "$(tr_text "Обновить панель Remnawave" "Update Remnawave panel")" run_panel_update_flow
        ;;
      6)
        run_component_flow_action "$(tr_text "Обновить страницу подписок" "Update subscription page")" run_subscription_update_flow
        ;;
      7) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_remnanode_components() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Раздел: Компоненты RemnaNode" "Section: RemnaNode components")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Базовые и сетевые инструменты для RemnaNode." "Basic and network tools for RemnaNode.")"
    menu_option "1" "$(tr_text "Полная настройка (нода + Caddy + BBR + WARP)" "Full setup (node + Caddy + BBR + WARP)")"
    menu_option "2" "$(tr_text "Установить ноду RemnaNode" "Install RemnaNode")"
    menu_option "3" "$(tr_text "Обновить ноду RemnaNode" "Update RemnaNode")"
    menu_option "4" "$(tr_text "Настроить Caddy self-steal" "Configure Caddy self-steal")"
    menu_option "5" "$(tr_text "Включить BBR" "Enable BBR")"
    menu_option "6" "$(tr_text "Настроить WARP Native (wgcf)" "Configure WARP Native (wgcf)")"
    menu_option "7" "$(tr_text "Включить/выключить IPv6" "Toggle IPv6")"
    menu_option "8" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-8]: " "Choice [1-8]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_component_flow_action "$(tr_text "Полная настройка (нода + Caddy + BBR + WARP)" "Full setup (node + Caddy + BBR + WARP)")" run_remnanode_full_setup_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Установить ноду RemnaNode" "Install RemnaNode")" run_node_install_flow
        ;;
      3)
        run_component_flow_action "$(tr_text "Обновить ноду RemnaNode" "Update RemnaNode")" run_node_update_flow
        ;;
      4)
        run_component_flow_action "$(tr_text "Настроить Caddy self-steal" "Configure Caddy self-steal")" run_node_caddy_selfsteal_flow
        ;;
      5)
        run_component_flow_action "$(tr_text "Включить BBR" "Enable BBR")" run_node_bbr_flow
        ;;
      6)
        run_component_flow_action "$(tr_text "Настроить WARP Native (wgcf)" "Configure WARP Native (wgcf)")" run_node_warp_native_flow
        ;;
      7)
        run_component_flow_action "$(tr_text "Включить/выключить IPv6" "Toggle IPv6")" run_node_ipv6_toggle_flow
        ;;
      8) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_operations() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Раздел: Ручное управление" "Section: Manual backup control")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Здесь можно вручную: 1) создать резервную копию, 2) запустить восстановление." "Manually: 1) create backup, 2) restore backup.")"
    menu_option "1" "$(tr_text "Создать резервную копию сейчас" "Create backup now")"
    menu_option "2" "$(tr_text "Запустить восстановление" "Restore backup")"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        draw_subheader "$(tr_text "Создание резервной копии" "Create backup")"
        if run_backup_now; then
          paint "$CLR_OK" "$(tr_text "Резервная копия создана успешно." "Backup completed successfully.")"
          show_operation_result_summary "$(tr_text "Создание резервной копии" "Create backup")" "1"
        else
          paint "$CLR_DANGER" "$(tr_text "Ошибка создания резервной копии. Проверьте лог выше." "Backup failed. Check the log above.")"
          show_operation_result_summary "$(tr_text "Создание резервной копии" "Create backup")" "0"
        fi
        wait_for_enter
        ;;
      2)
        draw_restore_step "1" "4" "$(tr_text "Выбор источника архива" "Select backup source")"
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
        if ! ensure_restore_password_if_needed; then
          continue
        fi
        draw_restore_step "3" "4" "$(tr_text "Параметры запуска" "Execution options")"
        paint "$CLR_MUTED" "$(tr_text "Подсказка: тестовый режим только проверяет шаги, боевой режим реально применяет изменения." "Tip: test mode only validates steps, real mode actually applies changes.")"
        paint "$CLR_MUTED" "$(tr_text "Если отключить перезапуски, сервисы не будут автоматически перезапущены после восстановления." "If restarts are disabled, services will not be restarted automatically after restore.")"
        while true; do
          menu_option "1" "$(tr_text "Тестовый режим (без изменений, безопасно)" "Test mode (no changes, safe)")"
          menu_option "2" "$(tr_text "Боевой режим (вносит изменения, риск)" "Real mode (applies changes, risk)")"
          print_separator
          read -r -p "$(tr_text "Выбор режима [1-2]: " "Select mode [1-2]: ")" choice
          if is_back_command "$choice"; then
            continue 2
          fi
          case "$choice" in
            1) RESTORE_DRY_RUN=1; break ;;
            2) RESTORE_DRY_RUN=0; break ;;
            *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")" ;;
          esac
        done
        while true; do
          menu_option "1" "$(tr_text "Автоперезапуск после restore (быстрее)" "Auto-restart after restore (faster)")"
          menu_option "2" "$(tr_text "Без автоперезапуска (осторожно)" "No auto-restart (safer)")"
          print_separator
          read -r -p "$(tr_text "Перезапуски [1-2]: " "Restarts [1-2]: ")" choice
          if is_back_command "$choice"; then
            continue 2
          fi
          case "$choice" in
            1) RESTORE_NO_RESTART=0; break ;;
            2) RESTORE_NO_RESTART=1; break ;;
            *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")" ;;
          esac
        done
        draw_restore_step "4" "4" "$(tr_text "Подтверждение и запуск" "Confirm and run")"
        show_restore_summary
        show_restore_safety_checklist
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
          show_operation_result_summary "$(tr_text "Восстановление" "Backup restore")" "1"
        else
          paint "$CLR_DANGER" "$(tr_text "Ошибка восстановления. Проверьте лог выше." "Restore failed. Check the log above.")"
          show_operation_result_summary "$(tr_text "Восстановление" "Backup restore")" "0"
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
    draw_subheader "$(tr_text "Раздел: Таймер и периодичность" "Section: Timer and schedule")"
    show_back_hint
    schedule_now="$(get_current_timer_calendar || true)"
    paint "$CLR_MUTED" "$(tr_text "Текущее расписание:" "Current schedule:") $(format_schedule_label "$schedule_now")"
    menu_option "1" "$(tr_text "Включить таймер резервного копирования" "Enable backup timer")"
    menu_option "2" "$(tr_text "Выключить таймер резервного копирования" "Disable backup timer")"
    menu_option "3" "$(tr_text "Настроить периодичность резервного копирования" "Configure backup schedule")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        draw_subheader "$(tr_text "Включение таймера резервного копирования" "Enable backup timer")"
        enable_timer
        wait_for_enter
        ;;
      2)
        draw_subheader "$(tr_text "Отключение таймера резервного копирования" "Disable backup timer")"
        disable_timer
        wait_for_enter
        ;;
      3)
        if configure_schedule_menu; then
          write_env
          write_timer_unit
          $SUDO systemctl daemon-reload
          paint "$CLR_OK" "$(tr_text "Периодичность резервного копирования сохранена." "Backup schedule saved.")"
          if $SUDO systemctl is-enabled --quiet panel-backup.timer 2>/dev/null; then
            if ! $SUDO systemctl restart panel-backup.timer; then
              paint "$CLR_WARN" "$(tr_text "Не удалось перезапустить timer после смены расписания." "Failed to restart timer after schedule update.")"
            fi
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
    draw_subheader "$(tr_text "Раздел: Статус и диагностика" "Section: Status and diagnostics")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Проверка состояния скриптов, таймера и последних архивов." "Check scripts, timer and latest backup details.")"
    menu_option "1" "$(tr_text "Показать полный статус" "Show full status")"
    menu_option "2" "$(tr_text "Анализ использования диска" "Analyze disk usage")"
    menu_option "3" "$(tr_text "Безопасная очистка диска" "Safe disk cleanup")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) show_status; wait_for_enter ;;
      2) show_disk_usage_top; wait_for_enter ;;
      3)
        show_safe_cleanup_preview
        if ask_yes_no "$(tr_text "Запустить безопасную очистку сейчас?" "Run safe cleanup now?")" "n"; then
          run_safe_cleanup
        fi
        wait_for_enter
        ;;
      4) break ;;
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
    draw_header "$(tr_text "Главное меню" "Main menu")"
    show_back_hint
    paint "$CLR_TITLE" "$(tr_text "Разделы" "Sections")"
    menu_option "1" "$(tr_text "Remnawave: панель и подписки" "Remnawave: panel and subscriptions")"
    menu_option "2" "$(tr_text "RemnaNode: нода и сеть" "RemnaNode: node and network")"
    menu_option "3" "$(tr_text "Резервное копирование и восстановление" "Backup and restore")"
    menu_option "4" "$(tr_text "Настройка резервного копирования" "Backup setup and configuration")"
    menu_option "5" "$(tr_text "Таймер и периодичность" "Timer and schedule")"
    menu_option "6" "$(tr_text "Статус и диагностика" "Status and diagnostics")"
    menu_option "0" "$(tr_text "Выход" "Exit")" "$CLR_DANGER"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6/0]: " "Choice [1-6/0]: ")" action
    if is_back_command "$action"; then
      echo "$(tr_text "Выход." "Cancelled.")"
      break
    fi

    case "$action" in
      1) menu_section_remnawave_components ;;
      2) menu_section_remnanode_components ;;
      3) menu_section_operations ;;
      4) menu_section_setup ;;
      5) menu_section_timer ;;
      6) menu_section_status ;;
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
