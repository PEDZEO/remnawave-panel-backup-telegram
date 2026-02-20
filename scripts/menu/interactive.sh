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

menu_section_remnawave_components() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Раздел: Компоненты Remnawave" "Section: Remnawave components")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Установка и обновление панели, подписок и Caddy для панели." "Install and update panel, subscription and panel Caddy.")"
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
    paint "$CLR_TITLE" "============================================================"
    paint "$CLR_ACCENT" "  $(tr_text "Раздел 1. Бот и кабинет" "Section 1. Bot and cabinet")"
    paint "$CLR_TITLE" "------------------------------------------------------------"
    menu_option "1" "$(tr_text "Установить Bedolaga (бот + кабинет + Caddy)" "Install Bedolaga (bot + cabinet + Caddy)")"
    menu_option "2" "$(tr_text "Обновить Bedolaga (бот + кабинет)" "Update Bedolaga (bot + cabinet)")"
    paint "$CLR_TITLE" "============================================================"
    paint "$CLR_ACCENT" "  $(tr_text "Раздел 2. Панель и ноды" "Section 2. Panel and nodes")"
    paint "$CLR_TITLE" "------------------------------------------------------------"
    menu_option "3" "$(tr_text "Панель Remnawave и подписки" "Remnawave panel and subscriptions")"
    menu_option "4" "$(tr_text "Нода RemnaNode и сеть" "RemnaNode and network")"
    paint "$CLR_TITLE" "============================================================"
    paint "$CLR_ACCENT" "  $(tr_text "Раздел 3. Бэкапы" "Section 3. Backups")"
    paint "$CLR_TITLE" "------------------------------------------------------------"
    menu_option "5" "$(tr_text "Ручной backup/restore" "Manual backup/restore")"
    menu_option "6" "$(tr_text "Мастер настройки backup" "Backup setup wizard")"
    menu_option "7" "$(tr_text "Таймер и периодичность" "Timer and schedule")"
    menu_option "8" "$(tr_text "Статус и диагностика" "Status and diagnostics")"
    paint "$CLR_TITLE" "============================================================"
    menu_option "0" "$(tr_text "Выход" "Exit")" "$CLR_DANGER"
    print_separator
    read -r -p "$(tr_text "Выбор [1-8/0]: " "Choice [1-8/0]: ")" action
    if is_back_command "$action"; then
      echo "$(tr_text "Выход." "Cancelled.")"
      break
    fi

    case "$action" in
      1)
        run_component_flow_action "$(tr_text "Установить Bedolaga (бот + кабинет + Caddy)" "Install Bedolaga (bot + cabinet + Caddy)")" run_bedolaga_stack_install_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Обновить Bedolaga (бот + кабинет)" "Update Bedolaga (bot + cabinet)")" run_bedolaga_stack_update_flow
        ;;
      3) menu_section_remnawave_components ;;
      4) menu_section_remnanode_components ;;
      5) menu_section_operations ;;
      6) menu_section_setup ;;
      7) menu_section_timer ;;
      8) menu_section_status ;;
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
