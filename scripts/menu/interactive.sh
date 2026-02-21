#!/usr/bin/env bash
# Interactive menu sections for manager.sh

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

run_backup_with_scope() {
  local action_title="$1"
  local include_scope="$2"
  local old_include="${BACKUP_INCLUDE-__PBM_UNSET__}"

  export BACKUP_INCLUDE="$include_scope"
  draw_subheader "${action_title}"
  if run_backup_now; then
    paint "$CLR_OK" "$(tr_text "Резервная копия создана успешно." "Backup completed successfully.")"
    show_operation_result_summary "${action_title}" "1"
  else
    paint "$CLR_DANGER" "$(tr_text "Ошибка создания резервной копии. Проверьте лог выше." "Backup failed. Check the log above.")"
    show_operation_result_summary "${action_title}" "0"
  fi

  if [[ "$old_include" == "__PBM_UNSET__" ]]; then
    unset BACKUP_INCLUDE
  else
    export BACKUP_INCLUDE="$old_include"
  fi
  wait_for_enter
}

run_restore_scope_selector() {
  local profile="${1:-global}"
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Выбор состава восстановления" "Restore scope selection")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Выберите, что восстанавливать из архива." "Choose what to restore from archive.")"
    paint "$CLR_MUTED" "$(tr_text "Даже из общего архива можно восстановить только нужную часть." "Even from a full backup archive you can restore only the required part.")"

    if [[ "$profile" == "bedolaga" ]]; then
      menu_option "1" "$(tr_text "Бот + кабинет Bedolaga" "Bedolaga bot + cabinet")"
      menu_option "2" "$(tr_text "Только бот Bedolaga" "Bedolaga bot only")"
      menu_option "3" "$(tr_text "Только кабинет Bedolaga" "Bedolaga cabinet only")"
      menu_option "4" "$(tr_text "Ручной выбор компонентов Bedolaga" "Manual Bedolaga component selection")"
      menu_option "5" "$(tr_text "Назад" "Back")"
      print_separator
      read -r -p "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")" choice
      if is_back_command "$choice"; then
        return 1
      fi
      case "$choice" in
        1) if run_restore_wizard_flow "bedolaga-bot,bedolaga-cabinet" "1"; then return 0; fi ;;
        2) if run_restore_wizard_flow "bedolaga-db,bedolaga-redis,bedolaga-bot" "1"; then return 0; fi ;;
        3) if run_restore_wizard_flow "bedolaga-cabinet" "1"; then return 0; fi ;;
        4) if run_restore_wizard_flow "bedolaga" "0"; then return 0; fi ;;
        5) return 1 ;;
        *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
      esac
    else
      menu_option "1" "$(tr_text "Только панель Remnawave" "Remnawave panel only")"
      menu_option "2" "$(tr_text "Ручной выбор компонентов панели" "Manual panel component selection")"
      menu_option "3" "$(tr_text "Назад" "Back")"
      print_separator
      read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
      if is_back_command "$choice"; then
        return 1
      fi
      case "$choice" in
        1) if run_restore_wizard_flow "all" "1"; then return 0; fi ;;
        2) if run_restore_wizard_flow "all" "0"; then return 0; fi ;;
        3) return 1 ;;
        *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
      esac
    fi
  done
}

run_bedolaga_migration_wizard() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Миграция Bedolaga на новый VPS" "Bedolaga migration to a new VPS")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Готовые сценарии переноса из архива резервной копии." "Ready-made migration scenarios from a backup archive.")"
    paint "$CLR_MUTED" "$(tr_text "Файловый перенос не требует контейнеров БД/Redis на новом сервере." "File-only migration does not require DB/Redis containers on the new server.")"
    paint "$CLR_MUTED" "$(tr_text "Полный перенос требует archive со всеми компонентами и контейнеры remnawave_bot_db/remnawave_bot_redis." "Full migration requires an archive with all components and remnawave_bot_db/remnawave_bot_redis containers.")"
    menu_option "1" "$(tr_text "Перенести только бот + кабинет (рекомендуется для старта)" "Migrate bot + cabinet only (recommended to start)")"
    menu_option "2" "$(tr_text "Полный перенос Bedolaga (DB + Redis + бот + кабинет)" "Full Bedolaga migration (DB + Redis + bot + cabinet)")"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      return 1
    fi
    case "$choice" in
      1)
        if run_restore_wizard_flow "bedolaga-bot,bedolaga-cabinet" "1"; then
          return 0
        fi
        ;;
      2)
        if run_restore_wizard_flow "bedolaga" "1"; then
          return 0
        fi
        ;;
      3) return 1 ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

run_restore_wizard_flow() {
  local preset_restore_only="${1:-all,bedolaga}"
  local lock_restore_only="${2:-0}"
  local choice=""
  local preset_label=""

  draw_restore_step "1" "4" "$(tr_text "Выбор источника архива" "Select backup source")"
  MODE="restore"
  RESTORE_DRY_RUN=0
  RESTORE_NO_RESTART=0
  RESTORE_ONLY="$preset_restore_only"
  if ! select_restore_source; then
    return 1
  fi

  draw_restore_step "2" "4" "$(tr_text "Выбор компонентов" "Select components")"
  if [[ "$lock_restore_only" == "1" ]]; then
    case "$preset_restore_only" in
      all) preset_label="$(tr_text "панель (all)" "panel (all)")" ;;
      bedolaga) preset_label="$(tr_text "полный Bedolaga (db + redis + бот + кабинет)" "full Bedolaga (db + redis + bot + cabinet)")" ;;
      all,bedolaga|bedolaga,all) preset_label="$(tr_text "полный (панель + бот + кабинет)" "full (panel + bot + cabinet)")" ;;
      bedolaga-bot,bedolaga-cabinet|bedolaga-cabinet,bedolaga-bot) preset_label="$(tr_text "миграция: бот + кабинет (без DB/Redis)" "migration: bot + cabinet (without DB/Redis)")" ;;
      bedolaga-db,bedolaga-redis,bedolaga-bot|bedolaga-bot,bedolaga-db,bedolaga-redis) preset_label="$(tr_text "только бот Bedolaga (db + redis + bot)" "Bedolaga bot only (db + redis + bot)")" ;;
      bedolaga-cabinet) preset_label="$(tr_text "только кабинет Bedolaga" "Bedolaga cabinet only")" ;;
      *) preset_label="$preset_restore_only" ;;
    esac
    paint "$CLR_MUTED" "$(tr_text "Состав восстановления зафиксирован:" "Restore scope is locked:") ${preset_label}"
  else
    if ! select_restore_components; then
      return 1
    fi
  fi

  if ! ensure_restore_password_if_needed; then
    return 1
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
      return 1
    fi
    case "$choice" in
      1) RESTORE_DRY_RUN=1; break ;;
      2) RESTORE_DRY_RUN=0; break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")" ;;
    esac
  done

  while true; do
    menu_option "1" "$(tr_text "Автоперезапуск после восстановления (быстрее)" "Auto-restart after restore (faster)")"
    menu_option "2" "$(tr_text "Без автоперезапуска (осторожно)" "No auto-restart (safer)")"
    print_separator
    read -r -p "$(tr_text "Перезапуски [1-2]: " "Restarts [1-2]: ")" choice
    if is_back_command "$choice"; then
      return 1
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
    paint "$CLR_WARN" "$(tr_text "Восстановление отменено." "Restore cancelled.")"
    wait_for_enter
    return 1
  fi
  if [[ "$RESTORE_DRY_RUN" != "1" ]]; then
    if ! confirm_restore_phrase; then
      paint "$CLR_WARN" "$(tr_text "Подтверждение не пройдено. Восстановление отменено." "Confirmation failed. Restore cancelled.")"
      wait_for_enter
      return 1
    fi
  fi
  if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
    install_files
    write_env
    $SUDO systemctl daemon-reload
  fi
  if run_restore; then
    paint "$CLR_OK" "$(tr_text "Восстановление завершено." "Restore completed.")"
    show_operation_result_summary "$(tr_text "Восстановление" "Restore")" "1"
  else
    paint "$CLR_DANGER" "$(tr_text "Ошибка восстановления. Проверьте лог выше." "Restore failed. Check the log above.")"
    show_operation_result_summary "$(tr_text "Восстановление" "Restore")" "0"
  fi
  wait_for_enter
}

menu_section_remnawave_install_update() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Remnawave: установка и обновление" "Remnawave: install and update")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Операции установки и обновления панели, подписок и Caddy." "Install/update operations for panel, subscription and Caddy.")"
    menu_option "1" "$(tr_text "Полная установка (панель + подписки + Caddy)" "Full install (panel + subscription + Caddy)")"
    menu_option "2" "$(tr_text "Установить панель Remnawave" "Install Remnawave panel")"
    menu_option "3" "$(tr_text "Установить страницу подписок" "Install subscription page")"
    menu_option "4" "$(tr_text "Полное обновление (панель + подписки + Caddy)" "Full update (panel + subscription + Caddy)")"
    menu_option "5" "$(tr_text "Обновить панель Remnawave" "Update Remnawave panel")"
    menu_option "6" "$(tr_text "Обновить страницу подписок" "Update subscription page")"
    menu_option "7" "$(tr_text "Установить Caddy для панели" "Install panel Caddy")"
    menu_option "8" "$(tr_text "Обновить Caddy для панели" "Update panel Caddy")"
    menu_option "9" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-9]: " "Choice [1-9]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_component_flow_action "$(tr_text "Полная установка (панель + подписки + Caddy)" "Full install (panel + subscription + Caddy)")" run_remnawave_full_install_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Установить панель Remnawave" "Install Remnawave panel")" run_panel_install_flow
        ;;
      3)
        run_component_flow_action "$(tr_text "Установить страницу подписок" "Install subscription page")" run_subscription_install_flow
        ;;
      4)
        run_component_flow_action "$(tr_text "Полное обновление (панель + подписки + Caddy)" "Full update (panel + subscription + Caddy)")" run_remnawave_full_update_flow
        ;;
      5)
        run_component_flow_action "$(tr_text "Обновить панель Remnawave" "Update Remnawave panel")" run_panel_update_flow
        ;;
      6)
        run_component_flow_action "$(tr_text "Обновить страницу подписок" "Update subscription page")" run_subscription_update_flow
        ;;
      7)
        run_component_flow_action "$(tr_text "Установить Caddy для панели" "Install panel Caddy")" run_panel_caddy_install_flow
        ;;
      8)
        run_component_flow_action "$(tr_text "Обновить Caddy для панели" "Update panel Caddy")" run_panel_caddy_update_flow
        ;;
      9) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_remnawave_backup_restore() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Remnawave: backup и восстановление" "Remnawave: backup and restore")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Операции резервной копии, восстановления и настроек backup панели." "Panel backup, restore and backup settings.")"
    menu_option "1" "$(tr_text "Создать резервную копию панели" "Create panel backup")"
    menu_option "2" "$(tr_text "Восстановление: выбрать состав" "Restore: choose scope")"
    menu_option "3" "$(tr_text "Настройки backup панели" "Panel backup settings")"
    menu_option "4" "$(tr_text "Таймер и периодичность панели" "Panel timer and schedule")"
    menu_option "5" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_backup_with_scope "$(tr_text "Резервная копия: только панель" "Backup: panel only")" "all"
        ;;
      2) run_restore_scope_selector "panel" || true ;;
      3) menu_section_setup "panel" ;;
      4) menu_section_timer_scope "panel" ;;
      5) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_remnawave_components() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Раздел: Компоненты Remnawave" "Section: Remnawave components")"
    show_back_hint
    menu_option "1" "$(tr_text "Установка и обновление" "Install and update")"
    menu_option "2" "$(tr_text "Backup и восстановление" "Backup and restore")"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_section_remnawave_install_update ;;
      2) menu_section_remnawave_backup_restore ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_bedolaga_install_update() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Bedolaga: установка и обновление" "Bedolaga: install and update")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Операции установки и обновления стека Bedolaga (бот + кабинет)." "Install/update operations for Bedolaga stack (bot + cabinet).")"
    menu_option "1" "$(tr_text "Установить Bedolaga (бот + кабинет + Caddy)" "Install Bedolaga (bot + cabinet + Caddy)")"
    menu_option "2" "$(tr_text "Обновить Bedolaga (бот + кабинет)" "Update Bedolaga (bot + cabinet)")"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_component_flow_action "$(tr_text "Установить Bedolaga (бот + кабинет + Caddy)" "Install Bedolaga (bot + cabinet + Caddy)")" run_bedolaga_stack_install_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Обновить Bedolaga (бот + кабинет)" "Update Bedolaga (bot + cabinet)")" run_bedolaga_stack_update_flow
        ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_bedolaga_backup_restore() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Bedolaga: backup и восстановление" "Bedolaga: backup and restore")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Операции резервной копии, восстановления и настроек backup Bedolaga." "Bedolaga backup, restore and backup settings.")"
    menu_option "1" "$(tr_text "Создать резервную копию Bedolaga" "Create Bedolaga backup")"
    menu_option "2" "$(tr_text "Восстановление: выбрать состав" "Restore: choose scope")"
    menu_option "3" "$(tr_text "Миграция на новый VPS" "Migration to a new VPS")"
    menu_option "4" "$(tr_text "Настройки backup Bedolaga" "Bedolaga backup settings")"
    menu_option "5" "$(tr_text "Таймер и периодичность Bedolaga" "Bedolaga timer and schedule")"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_backup_with_scope "$(tr_text "Резервная копия: только Bedolaga" "Backup: Bedolaga only")" "bedolaga"
        ;;
      2) run_restore_scope_selector "bedolaga" || true ;;
      3) run_bedolaga_migration_wizard || true ;;
      4) menu_section_setup "bedolaga" ;;
      5) menu_section_timer_scope "bedolaga" ;;
      6) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_bedolaga_components() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Раздел: Бот и кабинет Bedolaga" "Section: Bedolaga bot and cabinet")"
    show_back_hint
    menu_option "1" "$(tr_text "Установка и обновление" "Install and update")"
    menu_option "2" "$(tr_text "Backup и восстановление" "Backup and restore")"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_section_bedolaga_install_update ;;
      2) menu_section_bedolaga_backup_restore ;;
      3) break ;;
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

menu_section_timer_scope() {
  local scope="${1:-panel}"
  local choice=""
  local current_schedule=""
  local timer_unit=""
  local timer_title=""
  local timer_label=""
  local schedule_choice=""
  local custom=""

  if [[ "$scope" == "bedolaga" ]]; then
    timer_unit="panel-backup-bedolaga.timer"
    timer_title="$(tr_text "Bedolaga: таймер и периодичность" "Bedolaga: timer and schedule")"
    timer_label="$(tr_text "Таймер Bedolaga" "Bedolaga timer")"
  else
    timer_unit="panel-backup-panel.timer"
    timer_title="$(tr_text "Панель: таймер и периодичность" "Panel: timer and schedule")"
    timer_label="$(tr_text "Таймер панели" "Panel timer")"
  fi

  while true; do
    draw_subheader "$timer_title"
    show_back_hint
    current_schedule="$(get_timer_calendar_for_unit "$timer_unit" || true)"
    if [[ -z "$current_schedule" ]]; then
      if [[ "$scope" == "bedolaga" ]]; then
        current_schedule="${BACKUP_ON_CALENDAR_BEDOLAGA:-${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}}"
      else
        current_schedule="${BACKUP_ON_CALENDAR_PANEL:-${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}}"
      fi
    fi
    paint "$CLR_MUTED" "${timer_label}: $($SUDO systemctl is-active "$timer_unit" 2>/dev/null || echo inactive)"
    paint "$CLR_MUTED" "$(tr_text "Текущее расписание:" "Current schedule:") $(format_schedule_label "$current_schedule")"
    menu_option "1" "$(tr_text "Включить таймер" "Enable timer")"
    menu_option "2" "$(tr_text "Выключить таймер" "Disable timer")"
    menu_option "3" "$(tr_text "Настроить периодичность" "Configure schedule")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        write_env
        write_timer_unit
        $SUDO systemctl daemon-reload
        if [[ "$scope" == "bedolaga" ]]; then
          if has_bedolaga_project; then
            $SUDO systemctl enable --now panel-backup-bedolaga.timer
          else
            paint "$CLR_WARN" "$(tr_text "Bedolaga не обнаружен. Таймер не включен." "Bedolaga not detected. Timer was not enabled.")"
          fi
        else
          if has_panel_project; then
            $SUDO systemctl enable --now panel-backup-panel.timer
          else
            paint "$CLR_WARN" "$(tr_text "Панель не обнаружена. Таймер не включен." "Panel not detected. Timer was not enabled.")"
          fi
        fi
        wait_for_enter
        ;;
      2)
        $SUDO systemctl disable --now "$timer_unit" >/dev/null 2>&1 || true
        paint "$CLR_OK" "$(tr_text "Таймер отключен." "Timer disabled.")"
        wait_for_enter
        ;;
      3)
        draw_subheader "$timer_title"
        paint "$CLR_MUTED" "$(tr_text "1) Ежедневно 03:40 UTC  2) Каждые 12 часов  3) Каждые 6 часов  4) Каждый час  5) Свой OnCalendar" "1) Daily 03:40 UTC  2) Every 12h  3) Every 6h  4) Hourly  5) Custom OnCalendar")"
        read -r -p "$(tr_text "Выбор [1-5], b назад: " "Choice [1-5], b back: ")" schedule_choice
        if is_back_command "$schedule_choice"; then
          continue
        fi
        custom=""
        case "$schedule_choice" in
          1) custom="*-*-* 03:40:00 UTC" ;;
          2) custom="*-*-* 00,12:00:00 UTC" ;;
          3) custom="*-*-* 00,06,12,18:00:00 UTC" ;;
          4) custom="hourly" ;;
          5)
            custom="$(ask_value "$(tr_text "Введите OnCalendar" "Enter OnCalendar")" "$current_schedule")"
            [[ "$custom" == "__PBM_BACK__" ]] && continue
            ;;
          *)
            paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
            wait_for_enter
            continue
            ;;
        esac
        [[ -n "$custom" ]] || continue
        if [[ "$scope" == "bedolaga" ]]; then
          BACKUP_ON_CALENDAR_BEDOLAGA="$custom"
        else
          BACKUP_ON_CALENDAR_PANEL="$custom"
        fi
        BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR_PANEL:-${BACKUP_ON_CALENDAR_BEDOLAGA:-$custom}}"
        write_env
        write_timer_unit
        $SUDO systemctl daemon-reload
        if $SUDO systemctl is-enabled --quiet "$timer_unit" 2>/dev/null; then
          $SUDO systemctl restart "$timer_unit" >/dev/null 2>&1 || true
        fi
        paint "$CLR_OK" "$(tr_text "Периодичность сохранена." "Schedule saved.")"
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
    paint "$CLR_TITLE" "============================================================"
    paint "$CLR_ACCENT" "  $(tr_text "Раздел 1. Бот и кабинет" "Section 1. Bot and cabinet")"
    paint "$CLR_TITLE" "------------------------------------------------------------"
    menu_option "1" "$(tr_text "Меню Bedolaga: бот + кабинет" "Bedolaga menu: bot + cabinet")"
    paint "$CLR_TITLE" "============================================================"
    paint "$CLR_ACCENT" "  $(tr_text "Раздел 2. Панель и нода" "Section 2. Panel and node")"
    paint "$CLR_TITLE" "------------------------------------------------------------"
    menu_option "2" "$(tr_text "Панель Remnawave и подписки" "Remnawave panel and subscriptions")"
    menu_option "3" "$(tr_text "Нода RemnaNode и сеть" "RemnaNode and network")"
    paint "$CLR_TITLE" "============================================================"
    paint "$CLR_ACCENT" "  $(tr_text "Сервисные инструменты" "Service tools")"
    paint "$CLR_TITLE" "------------------------------------------------------------"
    menu_option "4" "$(tr_text "Статус и диагностика" "Status and diagnostics")"
    paint "$CLR_TITLE" "============================================================"
    menu_option "0" "$(tr_text "Выход" "Exit")" "$CLR_DANGER"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4/0]: " "Choice [1-4/0]: ")" action
    if is_back_command "$action"; then
      echo "$(tr_text "Выход." "Cancelled.")"
      break
    fi

    case "$action" in
      1) menu_section_bedolaga_components ;;
      2) menu_section_remnawave_components ;;
      3) menu_section_remnanode_components ;;
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
