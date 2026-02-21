#!/usr/bin/env bash
# Install pipeline functions for manager.sh
INSTALL_TIMER_ENABLED="1"

is_valid_telegram_token() {
  local token="$1"
  [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]{20,}$ ]]
}

is_valid_telegram_id() {
  local value="$1"
  [[ "$value" =~ ^-?[0-9]+$ ]]
}

prompt_install_settings() {
  local val=""
  local detected_path=""
  local detected_bedolaga_bot=""
  local detected_bedolaga_cabinet=""
  local panel_path_prompt=""
  local encrypt_choice=""
  local confirm_val=""
  local previous_password=""
  local include_choice=""
  load_existing_env_defaults

  draw_header "$(tr_text "Настройка резервного копирования" "Configure backup settings")"
  show_back_hint
  paint "$CLR_MUTED" "$(tr_text "Сейчас вы настраиваете: Telegram-уведомления и пути для панели, бота и кабинета." "You are configuring: Telegram notifications and paths for panel, bot and cabinet.")"
  paint "$CLR_MUTED" "$(tr_text "Также можно включить шифрование архива резервной копии." "You can also enable backup archive encryption.")"
  paint "$CLR_MUTED" "$(tr_text "Пустое значение оставляет текущее (если есть)." "Empty input keeps current value (if any).")"
  echo
  detected_path="$(detect_remnawave_dir || true)"
  detected_bedolaga_bot="$(detect_bedolaga_bot_dir || true)"
  detected_bedolaga_cabinet="$(detect_bedolaga_cabinet_dir || true)"
  show_remnawave_autodetect "$detected_path"
  show_bedolaga_autodetect "$detected_bedolaga_bot" "$detected_bedolaga_cabinet"
  if [[ -z "${REMNAWAVE_DIR:-}" && -n "$detected_path" ]]; then
    REMNAWAVE_DIR="$detected_path"
  fi
  if [[ -z "$detected_path" && -n "$detected_bedolaga_bot" && "${REMNAWAVE_DIR:-}" == "$detected_bedolaga_bot" ]]; then
    REMNAWAVE_DIR=""
    paint "$CLR_WARN" "$(tr_text "Сброшен путь панели: ранее был подставлен путь бота." "Panel path was reset: bot path had been filled there before.")"
  fi
  if [[ -z "$detected_path" && -n "$detected_bedolaga_bot" ]]; then
    if [[ -z "${BACKUP_INCLUDE:-}" || "${BACKUP_INCLUDE}" == "all" ]]; then
      BACKUP_INCLUDE="bedolaga"
      paint "$CLR_MUTED" "$(tr_text "Панель не обнаружена, установлен профиль backup: bedolaga (бот + кабинет)." "Panel was not detected, backup profile set to: bedolaga (bot + cabinet).")"
    fi
  fi
  if [[ -z "$detected_path" ]]; then
    panel_path_prompt="$(tr_text "[4/7] Путь к папке панели Remnawave (опционально, можно оставить пусто)" "[4/7] Path to Remnawave panel directory (optional, you can leave it empty)")"
  else
    panel_path_prompt="$(tr_text "[4/7] Путь к папке панели Remnawave (пример: /opt/remnawave)" "[4/7] Path to Remnawave panel directory (example: /opt/remnawave)")"
  fi
  echo

  while true; do
    val="$(ask_value "$(tr_text "[1/7] Токен Telegram-бота (пример: 123456:ABCDEF...)" "[1/7] Telegram bot token (example: 123456:ABCDEF...)")" "$TELEGRAM_BOT_TOKEN")"
    [[ "$val" == "__PBM_BACK__" ]] && return 1
    if [[ -n "$val" ]] && ! is_valid_telegram_token "$val"; then
      paint "$CLR_WARN" "$(tr_text "Похоже на некорректный токен Telegram. Формат: digits:token" "Looks like an invalid Telegram token. Format: digits:token")"
      continue
    fi
    TELEGRAM_BOT_TOKEN="$val"
    break
  done

  while true; do
    val="$(ask_value "$(tr_text "[2/7] ID чата/канала Telegram (пример: 123456789 или -1001234567890)" "[2/7] Telegram chat/channel ID (example: 123456789 or -1001234567890)")" "$TELEGRAM_ADMIN_ID")"
    [[ "$val" == "__PBM_BACK__" ]] && return 1
    if [[ -n "$val" ]] && ! is_valid_telegram_id "$val"; then
      paint "$CLR_WARN" "$(tr_text "ID чата должен быть числом (например 123456789 или -1001234567890)." "Chat ID must be numeric (for example 123456789 or -1001234567890).")"
      continue
    fi
    TELEGRAM_ADMIN_ID="$val"
    break
  done

  while true; do
    val="$(ask_value "$(tr_text "[3/7] ID темы (topic), если нужен (иначе оставьте пусто)" "[3/7] Topic/thread ID if needed (otherwise leave empty)")" "$TELEGRAM_THREAD_ID")"
    [[ "$val" == "__PBM_BACK__" ]] && return 1
    if [[ -n "$val" ]] && ! is_valid_telegram_id "$val"; then
      paint "$CLR_WARN" "$(tr_text "ID темы должен быть числом." "Thread ID must be numeric.")"
      continue
    fi
    TELEGRAM_THREAD_ID="$val"
    break
  done

  while true; do
    val="$(ask_value "$panel_path_prompt" "$REMNAWAVE_DIR")"
    [[ "$val" == "__PBM_BACK__" ]] && return 1
    REMNAWAVE_DIR="$val"
    break
  done

  while true; do
    val="$(ask_value "$(tr_text "[5/8] Язык описания резервной копии в Telegram (ru/en)" "[5/8] Backup description language in Telegram (ru/en)")" "$BACKUP_LANG")"
    [[ "$val" == "__PBM_BACK__" ]] && return 1
    case "${val,,}" in
      en|eu) BACKUP_LANG="en"; break ;;
      ru|"") BACKUP_LANG="ru"; break ;;
      *)
        paint "$CLR_WARN" "$(tr_text "Допустимые значения: ru или en." "Allowed values: ru or en.")"
        ;;
    esac
  done

  draw_header "$(tr_text "Режим шифрования резервной копии" "Backup encryption mode")"
  show_back_hint
  paint "$CLR_MUTED" "$(tr_text "Выберите режим шифрования архива." "Choose archive encryption mode.")"
  menu_option "1" "$(tr_text "Включить шифрование (GPG)" "Enable encryption (GPG)")"
  menu_option "2" "$(tr_text "Выключить шифрование" "Disable encryption")"
  print_separator
  while true; do
    read -r -p "$(tr_text "[6/8] Выбор [1-2]: " "[6/8] Choice [1-2]: ")" encrypt_choice
    if is_back_command "$encrypt_choice"; then
      return 1
    fi
    case "$encrypt_choice" in
      1) BACKUP_ENCRYPT="1"; break ;;
      2) BACKUP_ENCRYPT="0"; break ;;
      *)
        paint "$CLR_WARN" "$(tr_text "Некорректный выбор режима шифрования." "Invalid encryption mode choice.")"
        ;;
    esac
  done

  if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
    while true; do
      previous_password="$BACKUP_PASSWORD"
      val="$(ask_secret_value "$(tr_text "[7/8] Пароль шифрования (GPG symmetric)" "[7/8] Encryption password (GPG symmetric)")" "$BACKUP_PASSWORD")"
      [[ "$val" == "__PBM_BACK__" ]] && return 1
      if [[ -n "$previous_password" && "$val" == "$previous_password" ]]; then
        BACKUP_PASSWORD="$val"
        break
      fi
      if [[ ${#val} -lt 8 ]]; then
        paint "$CLR_WARN" "$(tr_text "Пароль шифрования должен быть не короче 8 символов." "Encryption password must be at least 8 characters long.")"
        continue
      fi
      confirm_val="$(ask_secret_value "$(tr_text "Подтвердите пароль шифрования" "Confirm encryption password")" "")"
      [[ "$confirm_val" == "__PBM_BACK__" ]] && return 1
      if [[ "$confirm_val" != "$val" ]]; then
        paint "$CLR_WARN" "$(tr_text "Пароли не совпадают." "Passwords do not match.")"
        continue
      fi
      BACKUP_PASSWORD="$val"
      break
    done
  else
    BACKUP_PASSWORD=""
  fi

  draw_header "$(tr_text "Состав резервной копии" "Backup scope")"
  show_back_hint
  paint "$CLR_MUTED" "$(tr_text "Выберите, какие данные включать в резервную копию." "Choose what to include in backup.")"
  menu_option "1" "$(tr_text "Полный (панель + Bedolaga)" "Full (panel + Bedolaga)")"
  menu_option "2" "$(tr_text "Только PostgreSQL (db)" "PostgreSQL only (db)")"
  menu_option "3" "$(tr_text "Только Redis (redis)" "Redis only (redis)")"
  menu_option "4" "$(tr_text "Только конфиги (панель + Bedolaga)" "Configs only (panel + Bedolaga)")"
  menu_option "5" "$(tr_text "Свой список (пример: db,env,compose)" "Custom list (example: db,env,compose)")"
  print_separator
  while true; do
    read -r -p "$(tr_text "[8/8] Выбор [1-5]: " "[8/8] Choice [1-5]: ")" include_choice
    if is_back_command "$include_choice"; then
      return 1
    fi
    case "$include_choice" in
      1) BACKUP_INCLUDE="all,bedolaga"; break ;;
      2) BACKUP_INCLUDE="db"; break ;;
      3) BACKUP_INCLUDE="redis"; break ;;
      4) BACKUP_INCLUDE="configs,bedolaga-configs"; break ;;
      5)
        val="$(ask_value "$(tr_text "Введите компоненты через запятую (all,db,redis,configs,env,compose,caddy,subscription,bedolaga,bedolaga-db,bedolaga-redis,bedolaga-bot,bedolaga-cabinet,bedolaga-configs)" "Enter comma-separated components (all,db,redis,configs,env,compose,caddy,subscription,bedolaga,bedolaga-db,bedolaga-redis,bedolaga-bot,bedolaga-cabinet,bedolaga-configs)")" "$BACKUP_INCLUDE")"
        [[ "$val" == "__PBM_BACK__" ]] && continue
        [[ -n "$val" ]] || { paint "$CLR_WARN" "$(tr_text "Список не может быть пустым." "List cannot be empty.")"; continue; }
        BACKUP_INCLUDE="$val"
        break
        ;;
      *)
        paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
        ;;
    esac
  done

  return 0
}

install_files() {
  paint "$CLR_ACCENT" "[1/5] $(tr_text "Загрузка файлов" "Downloading files")"
  fetch "scripts/bin/panel-backup.sh" "$TMP_DIR/panel-backup.sh"
  fetch "scripts/bin/panel-restore.sh" "$TMP_DIR/panel-restore.sh"
  fetch "systemd/panel-backup.service" "$TMP_DIR/panel-backup.service"
  fetch "systemd/panel-backup.timer" "$TMP_DIR/panel-backup.timer"

  paint "$CLR_ACCENT" "[2/5] $(tr_text "Установка скриптов и systemd-юнитов" "Installing scripts and systemd units")"
  $SUDO install -m 755 "$TMP_DIR/panel-backup.sh" /usr/local/bin/panel-backup.sh
  $SUDO install -m 755 "$TMP_DIR/panel-restore.sh" /usr/local/bin/panel-restore.sh
  $SUDO install -m 644 "$TMP_DIR/panel-backup.service" /etc/systemd/system/panel-backup.service
  $SUDO install -m 644 "$TMP_DIR/panel-backup.timer" /etc/systemd/system/panel-backup.timer
}

write_env() {
  local escaped_bot=""
  local escaped_admin=""
  local escaped_thread=""
  local escaped_thread_panel=""
  local escaped_thread_bedolaga=""
  local escaped_dir=""
  local escaped_calendar=""
  local escaped_backup_lang=""
  local escaped_backup_password=""
  local escaped_backup_include=""
  load_existing_env_defaults

  escaped_bot="$(escape_env_value "${TELEGRAM_BOT_TOKEN:-}")"
  escaped_admin="$(escape_env_value "${TELEGRAM_ADMIN_ID:-}")"
  escaped_thread="$(escape_env_value "${TELEGRAM_THREAD_ID:-}")"
  escaped_thread_panel="$(escape_env_value "${TELEGRAM_THREAD_ID_PANEL:-}")"
  escaped_thread_bedolaga="$(escape_env_value "${TELEGRAM_THREAD_ID_BEDOLAGA:-}")"
  escaped_dir="$(escape_env_value "${REMNAWAVE_DIR:-}")"
  escaped_calendar="$(escape_env_value "${BACKUP_ON_CALENDAR:-}")"
  escaped_backup_lang="$(escape_env_value "${BACKUP_LANG:-}")"
  escaped_backup_password="$(escape_env_value "${BACKUP_PASSWORD:-}")"
  escaped_backup_include="$(escape_env_value "${BACKUP_INCLUDE:-all}")"

  paint "$CLR_ACCENT" "[3/5] $(tr_text "Запись /etc/panel-backup.env" "Writing /etc/panel-backup.env")"
  $SUDO install -d -m 755 /etc
  $SUDO bash -c "cat > /etc/panel-backup.env <<ENV
${TELEGRAM_BOT_TOKEN:+TELEGRAM_BOT_TOKEN=\"${escaped_bot}\"}
${TELEGRAM_ADMIN_ID:+TELEGRAM_ADMIN_ID=\"${escaped_admin}\"}
${TELEGRAM_THREAD_ID:+TELEGRAM_THREAD_ID=\"${escaped_thread}\"}
${TELEGRAM_THREAD_ID_PANEL:+TELEGRAM_THREAD_ID_PANEL=\"${escaped_thread_panel}\"}
${TELEGRAM_THREAD_ID_BEDOLAGA:+TELEGRAM_THREAD_ID_BEDOLAGA=\"${escaped_thread_bedolaga}\"}
${REMNAWAVE_DIR:+REMNAWAVE_DIR=\"${escaped_dir}\"}
${BACKUP_ON_CALENDAR:+BACKUP_ON_CALENDAR=\"${escaped_calendar}\"}
${BACKUP_LANG:+BACKUP_LANG=\"${escaped_backup_lang}\"}
BACKUP_ENCRYPT=\"${BACKUP_ENCRYPT:-0}\"
${BACKUP_PASSWORD:+BACKUP_PASSWORD=\"${escaped_backup_password}\"}
BACKUP_INCLUDE=\"${escaped_backup_include}\"
ENV"
  $SUDO chmod 600 /etc/panel-backup.env
  $SUDO chown root:root /etc/panel-backup.env

  paint "$CLR_MUTED" "REMNAWAVE_DIR=${REMNAWAVE_DIR:-not-detected}"
  paint "$CLR_MUTED" "BACKUP_ON_CALENDAR=${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"
  paint "$CLR_MUTED" "BACKUP_LANG=${BACKUP_LANG:-ru}"
  paint "$CLR_MUTED" "BACKUP_ENCRYPT=${BACKUP_ENCRYPT:-0}"
  paint "$CLR_MUTED" "BACKUP_INCLUDE=${BACKUP_INCLUDE:-all}"
}

escape_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\$}"
  value="${value//\`/\\\`}"
  printf '%s' "$value"
}

write_timer_unit() {
  local calendar="${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"

  $SUDO bash -c "cat > /etc/systemd/system/panel-backup.timer <<TIMER
[Unit]
Description=Run panel backup by configured schedule

[Timer]
OnCalendar=${calendar}
Persistent=true
Unit=panel-backup.service

[Install]
WantedBy=timers.target
TIMER"
  $SUDO chmod 644 /etc/systemd/system/panel-backup.timer
  $SUDO chown root:root /etc/systemd/system/panel-backup.timer
}

configure_schedule_menu() {
  local choice=""
  local custom=""
  local current="${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"

  while true; do
    draw_header "$(tr_text "Периодичность резервного копирования" "Backup schedule")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Текущее расписание:" "Current schedule:") $(format_schedule_label "$current")"
    menu_option "1" "$(tr_text "Ежедневно 03:40 UTC (по умолчанию)" "Daily at 03:40 UTC (default)")"
    menu_option "2" "$(tr_text "Каждые 12 часов" "Every 12 hours")"
    menu_option "3" "$(tr_text "Каждые 6 часов" "Every 6 hours")"
    menu_option "4" "$(tr_text "Каждый час" "Every hour")"
    menu_option "5" "$(tr_text "Свой OnCalendar" "Custom OnCalendar")"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      return 1
    fi

    case "$choice" in
      1) BACKUP_ON_CALENDAR="*-*-* 03:40:00 UTC"; return 0 ;;
      2) BACKUP_ON_CALENDAR="*-*-* 00,12:00:00 UTC"; return 0 ;;
      3) BACKUP_ON_CALENDAR="*-*-* 00,06,12,18:00:00 UTC"; return 0 ;;
      4) BACKUP_ON_CALENDAR="hourly"; return 0 ;;
      5)
        custom="$(ask_value "$(tr_text "Введите OnCalendar (пример: *-*-* 02:00:00 UTC)" "Enter OnCalendar (example: *-*-* 02:00:00 UTC)")" "$current")"
        [[ "$custom" == "__PBM_BACK__" ]] && continue
        if [[ -n "$custom" ]]; then
          BACKUP_ON_CALENDAR="$custom"
          return 0
        fi
        ;;
      6) return 1 ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")" ;;
    esac
  done
}

enable_timer() {
  write_timer_unit
  paint "$CLR_ACCENT" "[4/5] $(tr_text "Перезагрузка systemd и включение таймера" "Reloading systemd and enabling timer")"
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now panel-backup.timer

  paint "$CLR_OK" "[5/5] $(tr_text "Готово" "Done")"
  $SUDO systemctl status --no-pager panel-backup.timer | sed -n '1,12p'
}

is_backup_target_available() {
  local candidate=""

  candidate="${REMNAWAVE_DIR:-}"
  if [[ -n "$candidate" && -f "$candidate/.env" && -f "$candidate/docker-compose.yml" ]]; then
    return 0
  fi

  candidate="$(detect_remnawave_dir || true)"
  if [[ -n "$candidate" && -f "$candidate/.env" && -f "$candidate/docker-compose.yml" ]]; then
    REMNAWAVE_DIR="$candidate"
    return 0
  fi

  return 1
}

post_install_health_check() {
  local timer_active="inactive"
  local service_loaded="unknown"

  timer_active="$($SUDO systemctl is-active panel-backup.timer 2>/dev/null || echo "inactive")"
  if $SUDO systemctl cat panel-backup.service >/dev/null 2>&1; then
    service_loaded="ok"
  else
    service_loaded="missing"
  fi

  paint "$CLR_TITLE" "$(tr_text "Проверка после установки" "Post-install check")"
  paint "$CLR_MUTED" "panel-backup.timer: ${timer_active}"
  paint "$CLR_MUTED" "panel-backup.service: ${service_loaded}"
  if [[ "$INSTALL_TIMER_ENABLED" == "1" && "$timer_active" == "active" && "$service_loaded" == "ok" ]]; then
    paint "$CLR_OK" "$(tr_text "Установка и запуск таймера подтверждены." "Install and timer activation confirmed.")"
  elif [[ "$INSTALL_TIMER_ENABLED" == "0" && "$service_loaded" == "ok" ]]; then
    paint "$CLR_OK" "$(tr_text "Панель не обнаружена: таймер оставлен выключенным до настройки панели." "Panel not detected: timer left disabled until panel is configured.")"
  else
    paint "$CLR_WARN" "$(tr_text "Есть проблемы после установки, проверьте systemctl status." "Post-install checks reported issues, verify with systemctl status.")"
  fi
}

run_install_pipeline() {
  preflight_install_environment || return 1
  install_files
  write_env
  if is_backup_target_available; then
    INSTALL_TIMER_ENABLED="1"
    enable_timer
  else
    INSTALL_TIMER_ENABLED="0"
    paint "$CLR_WARN" "$(tr_text "Панель Remnawave не найдена: таймер резервного копирования не включен." "Remnawave panel was not found: backup timer was not enabled.")"
    paint "$CLR_MUTED" "$(tr_text "Установите панель или укажите корректный REMNAWAVE_DIR, затем включите таймер в меню." "Install panel or set a valid REMNAWAVE_DIR, then enable timer from menu.")"
    $SUDO systemctl disable --now panel-backup.timer >/dev/null 2>&1 || true
  fi
  post_install_health_check
  return 0
}

disable_timer() {
  echo "$(tr_text "Отключаю таймер резервного копирования" "Disabling backup timer")"
  $SUDO systemctl disable --now panel-backup.timer
  $SUDO systemctl status --no-pager panel-backup.timer | sed -n '1,12p' || true
}
