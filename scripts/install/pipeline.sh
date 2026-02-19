#!/usr/bin/env bash
# Install pipeline functions for manager.sh

prompt_install_settings() {
  local val=""
  local detected_path=""
  load_existing_env_defaults

  draw_header "$(tr_text "Настройка параметров бэкапа" "Configure backup settings")"
  show_back_hint
  paint "$CLR_MUTED" "$(tr_text "Сейчас вы настраиваете: Telegram-уведомления и путь к панели." "You are configuring: Telegram notifications and panel path.")"
  paint "$CLR_MUTED" "$(tr_text "Также можно включить шифрование backup-архива." "You can also enable backup archive encryption.")"
  paint "$CLR_MUTED" "$(tr_text "Пустое значение оставляет текущее (если есть)." "Empty input keeps current value (if any).")"
  echo
  detected_path="$(detect_remnawave_dir || true)"
  show_remnawave_autodetect "$detected_path"
  if [[ -z "${REMNAWAVE_DIR:-}" && -n "$detected_path" ]]; then
    REMNAWAVE_DIR="$detected_path"
  fi
  echo

  val="$(ask_value "$(tr_text "[1/7] Токен Telegram-бота (пример: 123456:ABCDEF...)" "[1/7] Telegram bot token (example: 123456:ABCDEF...)")" "$TELEGRAM_BOT_TOKEN")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_BOT_TOKEN="$val"

  val="$(ask_value "$(tr_text "[2/7] ID чата/канала Telegram (пример: 123456789 или -1001234567890)" "[2/7] Telegram chat/channel ID (example: 123456789 or -1001234567890)")" "$TELEGRAM_ADMIN_ID")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_ADMIN_ID="$val"

  val="$(ask_value "$(tr_text "[3/7] ID темы (topic), если нужен (иначе оставьте пусто)" "[3/7] Topic/thread ID if needed (otherwise leave empty)")" "$TELEGRAM_THREAD_ID")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  TELEGRAM_THREAD_ID="$val"

  val="$(ask_value "$(tr_text "[4/7] Путь к папке панели Remnawave (пример: /opt/remnawave)" "[4/7] Path to Remnawave panel directory (example: /opt/remnawave)")" "$REMNAWAVE_DIR")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  REMNAWAVE_DIR="$val"

  val="$(ask_value "$(tr_text "[5/7] Язык описания backup в Telegram (ru/en)" "[5/7] Backup description language in Telegram (ru/en)")" "$BACKUP_LANG")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  case "${val,,}" in
    en|eu) BACKUP_LANG="en" ;;
    ru|"") BACKUP_LANG="ru" ;;
    *) BACKUP_LANG="$val" ;;
  esac

  val="$(ask_value "$(tr_text "[6/7] Шифровать backup-архив (0/1, no/yes)" "[6/7] Encrypt backup archive (0/1, no/yes)")" "$BACKUP_ENCRYPT")"
  [[ "$val" == "__PBM_BACK__" ]] && return 1
  BACKUP_ENCRYPT="$(normalize_backup_encrypt_raw "$val")"

  if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
    val="$(ask_value "$(tr_text "[7/7] Пароль шифрования (GPG symmetric)" "[7/7] Encryption password (GPG symmetric)")" "$BACKUP_PASSWORD")"
    [[ "$val" == "__PBM_BACK__" ]] && return 1
    BACKUP_PASSWORD="$val"
  else
    BACKUP_PASSWORD=""
  fi

  return 0
}

install_files() {
  paint "$CLR_ACCENT" "[1/5] $(tr_text "Загрузка файлов" "Downloading files")"
  fetch "panel-backup.sh" "$TMP_DIR/panel-backup.sh"
  fetch "panel-restore.sh" "$TMP_DIR/panel-restore.sh"
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
  local escaped_dir=""
  local escaped_calendar=""
  local escaped_backup_lang=""
  local escaped_backup_password=""
  load_existing_env_defaults

  escaped_bot="$(escape_env_value "${TELEGRAM_BOT_TOKEN:-}")"
  escaped_admin="$(escape_env_value "${TELEGRAM_ADMIN_ID:-}")"
  escaped_thread="$(escape_env_value "${TELEGRAM_THREAD_ID:-}")"
  escaped_dir="$(escape_env_value "${REMNAWAVE_DIR:-}")"
  escaped_calendar="$(escape_env_value "${BACKUP_ON_CALENDAR:-}")"
  escaped_backup_lang="$(escape_env_value "${BACKUP_LANG:-}")"
  escaped_backup_password="$(escape_env_value "${BACKUP_PASSWORD:-}")"

  paint "$CLR_ACCENT" "[3/5] $(tr_text "Запись /etc/panel-backup.env" "Writing /etc/panel-backup.env")"
  $SUDO install -d -m 755 /etc
  $SUDO bash -c "cat > /etc/panel-backup.env <<ENV
${TELEGRAM_BOT_TOKEN:+TELEGRAM_BOT_TOKEN=\"${escaped_bot}\"}
${TELEGRAM_ADMIN_ID:+TELEGRAM_ADMIN_ID=\"${escaped_admin}\"}
${TELEGRAM_THREAD_ID:+TELEGRAM_THREAD_ID=\"${escaped_thread}\"}
${REMNAWAVE_DIR:+REMNAWAVE_DIR=\"${escaped_dir}\"}
${BACKUP_ON_CALENDAR:+BACKUP_ON_CALENDAR=\"${escaped_calendar}\"}
${BACKUP_LANG:+BACKUP_LANG=\"${escaped_backup_lang}\"}
BACKUP_ENCRYPT=\"${BACKUP_ENCRYPT:-0}\"
${BACKUP_PASSWORD:+BACKUP_PASSWORD=\"${escaped_backup_password}\"}
ENV"
  $SUDO chmod 600 /etc/panel-backup.env
  $SUDO chown root:root /etc/panel-backup.env

  paint "$CLR_MUTED" "REMNAWAVE_DIR=${REMNAWAVE_DIR:-not-detected}"
  paint "$CLR_MUTED" "BACKUP_ON_CALENDAR=${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}"
  paint "$CLR_MUTED" "BACKUP_LANG=${BACKUP_LANG:-ru}"
  paint "$CLR_MUTED" "BACKUP_ENCRYPT=${BACKUP_ENCRYPT:-0}"
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
    draw_header "$(tr_text "Периодичность backup" "Backup schedule")"
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
  if [[ "$timer_active" == "active" && "$service_loaded" == "ok" ]]; then
    paint "$CLR_OK" "$(tr_text "Установка и запуск таймера подтверждены." "Install and timer activation confirmed.")"
  else
    paint "$CLR_WARN" "$(tr_text "Есть проблемы после установки, проверьте systemctl status." "Post-install checks reported issues, verify with systemctl status.")"
  fi
}

run_install_pipeline() {
  preflight_install_environment || return 1
  install_files
  write_env
  enable_timer
  post_install_health_check
  return 0
}

disable_timer() {
  echo "$(tr_text "Отключаю таймер бэкапа" "Disabling backup timer")"
  $SUDO systemctl disable --now panel-backup.timer
  $SUDO systemctl status --no-pager panel-backup.timer | sed -n '1,12p' || true
}
