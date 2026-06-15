#!/usr/bin/env bash
# Interactive menu sections for manager.sh

run_component_flow_action() {
  local action_title="$1"
  local flow_func="$2"
  shift 2
  local flow_rc=0

  if [[ "$#" -eq 0 ]]; then
    set -- \
      "$(tr_text "Будет запущен мастер выбранного действия: он покажет вопросы и предложит текущие значения по умолчанию." "The selected action wizard will run: it shows prompts and offers current values as defaults.")" \
      "$(tr_text ".env, домены, токены и Caddyfile не меняются без отдельного вопроса внутри мастера." ".env, domains, tokens and Caddyfile are not changed without a separate prompt inside the wizard.")" \
      "$(tr_text "Если что-то упадет, останется выбор: повторить действие или вернуться в меню." "If something fails, you can retry the action or return to the menu.")"
  fi

  if [[ "$#" -gt 0 ]]; then
    if ! confirm_action_preview "$action_title" "$@"; then
      paint "$CLR_WARN" "$(tr_text "Операция отменена." "Operation cancelled.")"
      ui_record_action "$action_title" "$(tr_text "отменено" "cancelled")"
      wait_for_enter
      return 0
    fi
  fi

  while true; do
    if "$flow_func"; then
      paint "$CLR_OK" "$(tr_text "Операция завершена:" "Operation completed:") ${action_title}"
      ui_record_action "$action_title" "$(tr_text "успешно" "success")"
      wait_for_enter
      return 0
    else
      flow_rc=$?
    fi

    if [[ "$flow_rc" -eq 2 ]]; then
      paint "$CLR_WARN" "$(tr_text "Операция пропущена:" "Operation skipped:") ${action_title}"
      ui_record_action "$action_title" "$(tr_text "пропущено" "skipped")"
      wait_for_enter
      return 0
    fi

    if show_operation_failure_menu "$action_title" "$flow_rc"; then
      ui_record_action "$action_title" "$(tr_text "ошибка, повтор" "failed, retry")"
      continue
    fi
    ui_record_action "$action_title" "$(tr_text "ошибка" "failed")"
    return 0
  done
}

run_backup_with_scope() {
  local action_title="$1"
  local include_scope="$2"
  local old_include="${BACKUP_INCLUDE-__PBM_UNSET__}"

  export BACKUP_INCLUDE="$include_scope"
  draw_subheader "${action_title}"
  if run_backup_now; then
    paint "$CLR_OK" "$(tr_text "Резервная копия создана успешно." "Backup completed successfully.")"
    ui_record_action "$action_title" "$(tr_text "backup готов" "backup done")"
    show_operation_result_summary "${action_title}" "1"
  else
    paint "$CLR_DANGER" "$(tr_text "Ошибка создания резервной копии. Проверьте лог выше." "Backup failed. Check the log above.")"
    ui_record_action "$action_title" "$(tr_text "backup ошибка" "backup failed")"
    show_operation_result_summary "${action_title}" "0"
  fi

  if [[ "$old_include" == "__PBM_UNSET__" ]]; then
    unset BACKUP_INCLUDE
  else
    export BACKUP_INCLUDE="$old_include"
  fi
  wait_for_enter
}

run_backup_scope_selector() {
  local profile="${1:-global}"
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Выбор состава резервной копии" "Backup scope selection")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Выберите, что включать в резервную копию." "Choose what to include in the backup.")"
    paint "$CLR_MUTED" "$(tr_text "Для Bedolaga можно сохранять бот и кабинет отдельно, если один из путей не найден." "For Bedolaga, bot and cabinet can be backed up separately if one of the paths is missing.")"

    if [[ "$profile" == "bedolaga" ]]; then
      paint "$CLR_MUTED" "$(tr_text "DB official и DB форка разделены: профиль определяется по git origin, при несовпадении backup остановится." "Official and fork DB are separated: profile is detected from git origin, backup stops on mismatch.")"
      menu_option "1" "$(tr_text "Файлы бота + кабинета Bedolaga (без DB/Redis)" "Bedolaga bot + cabinet files (no DB/Redis)")"
      menu_option "2" "$(tr_text "Бот Bedolaga полностью (DB + Redis + файлы)" "Full Bedolaga bot (DB + Redis + files)")"
      menu_option "3" "$(tr_text "Файлы кабинета Bedolaga" "Bedolaga cabinet files")"
      menu_option "4" "$(tr_text "Полный Bedolaga (DB + Redis + бот + кабинет)" "Full Bedolaga (DB + Redis + bot + cabinet)")"
      menu_option "5" "$(tr_text "Только DB форка PEDZEO" "PEDZEO fork DB only")"
      menu_option "6" "$(tr_text "Только DB official Bedolaga" "Official Bedolaga DB only")"
      menu_option "7" "$(tr_text "Ручной выбор компонентов Bedolaga" "Manual Bedolaga component selection")"
      menu_option "8" "$(tr_text "Назад" "Back")"
      print_separator
      read_menu_choice choice "$(tr_text "Выбор [1-8]: " "Choice [1-8]: ")"
      if is_back_command "$choice"; then
        return 1
      fi
      case "$choice" in
        1) run_backup_with_scope "$(tr_text "Резервная копия: файлы бота + кабинета Bedolaga (без DB/Redis)" "Backup: Bedolaga bot + cabinet files (no DB/Redis)")" "bedolaga-bot,bedolaga-cabinet"; return 0 ;;
        2) run_backup_with_scope "$(tr_text "Резервная копия: бот Bedolaga полностью" "Backup: full Bedolaga bot")" "bedolaga-db,bedolaga-redis,bedolaga-bot"; return 0 ;;
        3) run_backup_with_scope "$(tr_text "Резервная копия: файлы кабинета Bedolaga" "Backup: Bedolaga cabinet files")" "bedolaga-cabinet"; return 0 ;;
        4) run_backup_with_scope "$(tr_text "Резервная копия: полный Bedolaga" "Backup: full Bedolaga")" "bedolaga"; return 0 ;;
        5) run_backup_with_scope "$(tr_text "Резервная копия: DB форка PEDZEO" "Backup: PEDZEO fork DB")" "bedolaga-fork-db"; return 0 ;;
        6) run_backup_with_scope "$(tr_text "Резервная копия: DB official Bedolaga" "Backup: official Bedolaga DB")" "bedolaga-official-db"; return 0 ;;
        7)
          paint "$CLR_MUTED" "$(tr_text "Используйте настройки backup Bedolaga, чтобы задать свой состав компонентов." "Use Bedolaga backup settings to define a custom component list.")"
          wait_for_enter
          return 1
          ;;
        8) return 1 ;;
        *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
      esac
    else
      menu_option "1" "$(tr_text "Только панель Remnawave" "Remnawave panel only")"
      menu_option "2" "$(tr_text "Назад" "Back")"
      print_separator
      read_menu_choice choice "$(tr_text "Выбор [1-2]: " "Choice [1-2]: ")"
      if is_back_command "$choice"; then
        return 1
      fi
      case "$choice" in
        1) run_backup_with_scope "$(tr_text "Резервная копия: только панель" "Backup: panel only")" "all"; return 0 ;;
        2) return 1 ;;
        *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
      esac
    fi
  done
}

run_quick_backup_menu() {
  local choice=""

  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Быстрый backup" "Home / Quick backup")"
    draw_subheader "$(tr_text "Быстрый backup" "Quick backup")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Выберите профиль backup без поиска по разделам." "Choose a backup profile without navigating through sections.")"
    menu_group "$(tr_text "Профиль" "Profile")" "$CLR_OK"
    menu_option "1" "$(tr_text "Панель Remnawave" "Remnawave panel")"
    menu_option "2" "Bedolaga"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) if run_backup_scope_selector "global"; then break; fi ;;
      2) if run_backup_scope_selector "bedolaga"; then break; fi ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
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
      paint "$CLR_MUTED" "$(tr_text "Restore DB/Redis Bedolaga защищен от смешивания official и fork. Файлы бота/кабинета можно восстанавливать отдельно без DB." "Bedolaga DB/Redis restore is guarded against official/fork mismatch. Bot/cabinet files can be restored separately without DB.")"
      menu_option "1" "$(tr_text "Файлы бота + кабинета Bedolaga (без DB/Redis)" "Bedolaga bot + cabinet files (no DB/Redis)")"
      menu_option "2" "$(tr_text "Бот Bedolaga полностью (DB + Redis + файлы)" "Full Bedolaga bot (DB + Redis + files)")"
      menu_option "3" "$(tr_text "Файлы кабинета Bedolaga" "Bedolaga cabinet files")"
      menu_option "4" "$(tr_text "Ручной выбор компонентов Bedolaga" "Manual Bedolaga component selection")"
      menu_option "5" "$(tr_text "Назад" "Back")"
      print_separator
      read_menu_choice choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
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
      read_menu_choice choice "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")"
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
    paint "$CLR_MUTED" "$(tr_text "Миграция вынесена в отдельный поток: сначала архив, потом перенос и восстановление на новом VPS." "Migration is separated into its own flow: create archive first, then transfer and restore on the new VPS.")"
    paint "$CLR_MUTED" "$(tr_text "Если скрипт уже запущен на новом VPS, используйте локальное восстановление из заранее перенесённого архива." "If the script is already running on the new VPS, use local restore from a pre-transferred archive.")"
    menu_option "1" "$(tr_text "Создать полный архив Bedolaga для переноса" "Create full Bedolaga archive for transfer")"
    menu_option "2" "$(tr_text "Перенести архив на новый VPS по SSH и восстановить" "Transfer archive to new VPS over SSH and restore")"
    menu_option "3" "$(tr_text "Я уже на новом VPS: восстановить из локального архива" "I am already on the new VPS: restore from local archive")"
    menu_option "4" "$(tr_text "Дополнительные режимы миграции" "Advanced migration modes")"
    menu_option "5" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
    if is_back_command "$choice"; then
      return 1
    fi
    case "$choice" in
      1)
        run_backup_with_scope "$(tr_text "Архив для миграции: полный Bedolaga" "Migration archive: full Bedolaga")" "bedolaga"
        return 0
        ;;
      2)
        if run_bedolaga_remote_migration_flow; then
          return 0
        fi
        ;;
      3)
        if run_bedolaga_local_migration_restore_flow; then
          return 0
        fi
        ;;
      4)
        draw_subheader "$(tr_text "Дополнительные режимы миграции" "Advanced migration modes")"
        show_back_hint
        paint "$CLR_MUTED" "$(tr_text "Здесь оставлены частичные сценарии для ручной миграции или отладки." "Partial scenarios are kept here for manual migration or troubleshooting.")"
        menu_option "1" "$(tr_text "Восстановить только бот + кабинет из локального архива" "Restore bot + cabinet only from local archive")"
        menu_option "2" "$(tr_text "Восстановить только кабинет из локального архива" "Restore cabinet only from local archive")"
        menu_option "3" "$(tr_text "Ручной выбор компонентов Bedolaga" "Manual Bedolaga component selection")"
        menu_option "4" "$(tr_text "Назад" "Back")"
        print_separator
        read_menu_choice choice "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")"
        if is_back_command "$choice"; then
          continue
        fi
        case "$choice" in
          1)
            if run_restore_wizard_flow "bedolaga-bot,bedolaga-cabinet" "1"; then
              return 0
            fi
            ;;
          2)
            if run_restore_wizard_flow "bedolaga-cabinet" "1"; then
              return 0
            fi
            ;;
          3)
            if run_restore_wizard_flow "bedolaga" "0"; then
              return 0
            fi
            ;;
          4) ;;
          *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
        esac
        ;;
      5) return 1 ;;
      *)
        paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
        wait_for_enter
        ;;
    esac
  done
}

menu_section_bedolaga_local_backup_restore() {
  local choice=""
  while true; do
    draw_subheader "$(tr_text "Bedolaga: локальный backup/restore" "Bedolaga: local backup/restore")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Этот раздел для работы на текущем VPS: создать архив и восстановить его здесь же." "This section is for the current VPS: create an archive and restore it on the same server.")"
    menu_group "$(tr_text "Backup" "Backup")" "$CLR_OK"
    menu_option "1" "$(tr_text "Создать полный backup Bedolaga" "Create full Bedolaga backup")"
    menu_group "$(tr_text "Восстановление" "Restore")" "$CLR_WARN"
    menu_option "2" "$(tr_text "Восстановить полный Bedolaga из локального архива" "Restore full Bedolaga from local archive")"
    menu_group "$(tr_text "Дополнительно" "Advanced")" "$CLR_ACCENT"
    menu_option "3" "$(tr_text "Дополнительные локальные режимы" "Advanced local modes")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_backup_with_scope "$(tr_text "Резервная копия: полный Bedolaga" "Backup: full Bedolaga")" "bedolaga"
        ;;
      2)
        run_restore_wizard_flow "bedolaga" "1" || true
        ;;
      3)
        draw_subheader "$(tr_text "Дополнительные локальные режимы" "Advanced local modes")"
        show_back_hint
        menu_group "$(tr_text "Backup" "Backup")" "$CLR_OK"
        menu_option "1" "$(tr_text "Создать backup: бот + кабинет" "Create backup: bot + cabinet")"
        menu_option "2" "$(tr_text "Создать backup: только бот" "Create backup: bot only")"
        menu_option "3" "$(tr_text "Создать backup: только кабинет" "Create backup: cabinet only")"
        menu_option "4" "$(tr_text "Создать backup: только DB форка PEDZEO" "Create backup: PEDZEO fork DB only")"
        menu_option "5" "$(tr_text "Создать backup: только DB official Bedolaga" "Create backup: official Bedolaga DB only")"
        menu_group "$(tr_text "Восстановление" "Restore")" "$CLR_WARN"
        menu_option "6" "$(tr_text "Восстановление: выбрать состав" "Restore: choose scope")"
        menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
        menu_option "7" "$(tr_text "Назад" "Back")"
        print_separator
        read_menu_choice choice "$(tr_text "Выбор [1-7]: " "Choice [1-7]: ")"
        if is_back_command "$choice"; then
          continue
        fi
        case "$choice" in
          1) run_backup_with_scope "$(tr_text "Резервная копия: файлы бота + кабинета Bedolaga (без DB/Redis)" "Backup: Bedolaga bot + cabinet files (no DB/Redis)")" "bedolaga-bot,bedolaga-cabinet" ;;
          2) run_backup_with_scope "$(tr_text "Резервная копия: бот Bedolaga полностью" "Backup: full Bedolaga bot")" "bedolaga-db,bedolaga-redis,bedolaga-bot" ;;
          3) run_backup_with_scope "$(tr_text "Резервная копия: файлы кабинета Bedolaga" "Backup: Bedolaga cabinet files")" "bedolaga-cabinet" ;;
          4) run_backup_with_scope "$(tr_text "Резервная копия: DB форка PEDZEO" "Backup: PEDZEO fork DB")" "bedolaga-fork-db" ;;
          5) run_backup_with_scope "$(tr_text "Резервная копия: DB official Bedolaga" "Backup: official Bedolaga DB")" "bedolaga-official-db" ;;
          6) run_restore_scope_selector "bedolaga" || true ;;
          7) ;;
          *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
        esac
        ;;
      4) break ;;
      *)
        paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
        wait_for_enter
        ;;
    esac
  done
}

bedolaga_resolve_migration_repo_url() {
  local component="$1"
  local fallback_url="$2"
  local repo_dir=""
  local repo_url=""

  case "$component" in
    bot)
      if declare -F bedolaga_detect_bot_repo_dir >/dev/null 2>&1; then
        repo_dir="$(bedolaga_detect_bot_repo_dir || true)"
      elif declare -F detect_bedolaga_bot_dir >/dev/null 2>&1; then
        repo_dir="$(detect_bedolaga_bot_dir || true)"
      fi
      ;;
    cabinet)
      if declare -F bedolaga_detect_cabinet_repo_dir >/dev/null 2>&1; then
        repo_dir="$(bedolaga_detect_cabinet_repo_dir || true)"
      elif declare -F detect_bedolaga_cabinet_dir >/dev/null 2>&1; then
        repo_dir="$(detect_bedolaga_cabinet_dir || true)"
      fi
      ;;
  esac

  if [[ -n "$repo_dir" && -d "${repo_dir}/.git" ]] && command -v git >/dev/null 2>&1; then
    repo_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  fi

  printf '%s' "${repo_url:-$fallback_url}"
}

archive_backup_info_value() {
  local archive_path="$1"
  local key="$2"
  local archive_password="${3:-}"
  local info_content=""

  [[ -n "$archive_path" && -f "$archive_path" ]] || return 0

  if [[ "$archive_path" == *.gpg ]]; then
    [[ -n "$archive_password" ]] || return 0
    info_content="$(gpg --batch --yes --pinentry-mode loopback --passphrase "$archive_password" --decrypt "$archive_path" 2>/dev/null | tar -xzOf - ./backup-info.txt 2>/dev/null || true)"
    if [[ -z "$info_content" ]]; then
      info_content="$(gpg --batch --yes --pinentry-mode loopback --passphrase "$archive_password" --decrypt "$archive_path" 2>/dev/null | tar -xzOf - backup-info.txt 2>/dev/null || true)"
    fi
  else
    info_content="$(tar -xzOf "$archive_path" ./backup-info.txt 2>/dev/null || true)"
    if [[ -z "$info_content" ]]; then
      info_content="$(tar -xzOf "$archive_path" backup-info.txt 2>/dev/null || true)"
    fi
  fi

  if [[ -n "$info_content" ]]; then
    printf '%s\n' "$info_content" | awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }'
  fi
}

bedolaga_prepare_local_repos_for_restore() {
  local bot_repo_url="$1"
  local cabinet_repo_url="$2"
  local bot_dir="$3"
  local cabinet_dir="$4"

  bot_dir="${bot_dir:-/root/remnawave-bedolaga-telegram-bot}"
  cabinet_dir="${cabinet_dir:-/root/bedolaga-cabinet}"

  paint "$CLR_ACCENT" "$(tr_text "Подготавливаю репозитории Bedolaga перед восстановлением..." "Preparing Bedolaga repositories before restore...")"
  paint "$CLR_MUTED" "  bot dir: ${bot_dir}"
  paint "$CLR_MUTED" "  cabinet dir: ${cabinet_dir}"
  if ! ensure_git_available; then
    paint "$CLR_WARN" "$(tr_text "Git недоступен, продолжаю без автоклонирования репозиториев." "Git is unavailable, continuing without automatic repository cloning.")"
    return 1
  fi

  if ! bedolaga_clone_or_update_repo "$bot_repo_url" "$bot_dir"; then
    paint "$CLR_WARN" "$(tr_text "Не удалось подготовить репозиторий бота. Продолжаю восстановление по архиву." "Failed to prepare bot repository. Continuing restore from archive.")"
  fi
  if ! bedolaga_clone_or_update_repo "$cabinet_repo_url" "$cabinet_dir"; then
    paint "$CLR_WARN" "$(tr_text "Не удалось подготовить репозиторий кабинета. Продолжаю восстановление по архиву." "Failed to prepare cabinet repository. Continuing restore from archive.")"
  fi
}

run_bedolaga_local_migration_restore_flow() {
  local bot_repo_url=""
  local cabinet_repo_url=""
  local restore_scope_choice=""
  local restore_only="bedolaga-bot,bedolaga-cabinet"
  local target_bot_dir=""
  local target_cabinet_dir=""

  bot_repo_url="$(bedolaga_resolve_migration_repo_url "bot" "${BEDOLAGA_BOT_REPO_DEFAULT}")"
  cabinet_repo_url="$(bedolaga_resolve_migration_repo_url "cabinet" "${BEDOLAGA_CABINET_REPO_DEFAULT}")"
  target_bot_dir="$(archive_backup_info_value "${BACKUP_FILE:-}" "bedolaga_bot_dir" "${BACKUP_PASSWORD:-}")"
  target_cabinet_dir="$(archive_backup_info_value "${BACKUP_FILE:-}" "bedolaga_cabinet_dir" "${BACKUP_PASSWORD:-}")"

  draw_subheader "$(tr_text "Подготовка нового VPS к восстановлению" "Prepare new VPS for restore")"
  paint "$CLR_MUTED" "$(tr_text "Перед восстановлением можно автоматически подготовить исходники Bedolaga через Git." "Before restore, Bedolaga repositories can be prepared automatically via Git.")"
  paint "$CLR_MUTED" "  bot: ${bot_repo_url}"
  paint "$CLR_MUTED" "  cabinet: ${cabinet_repo_url}"
  if [[ -n "$target_bot_dir" ]]; then
    paint "$CLR_MUTED" "  bot target: ${target_bot_dir}"
  fi
  if [[ -n "$target_cabinet_dir" ]]; then
    paint "$CLR_MUTED" "  cabinet target: ${target_cabinet_dir}"
  fi

  draw_subheader "$(tr_text "Выбор состава восстановления на новом VPS" "Select restore scope on the new VPS")"
  menu_option "1" "$(tr_text "Бот Bedolaga полностью (DB + Redis + файлы)" "Full Bedolaga bot (DB + Redis + files)")"
  menu_option "2" "$(tr_text "Файлы кабинета Bedolaga" "Bedolaga cabinet files")"
  menu_option "3" "$(tr_text "Файлы бота + кабинета (без DB/Redis, рекомендовано для старта)" "Bot + cabinet files (without DB/Redis, recommended to start)")"
  menu_option "4" "$(tr_text "Полный Bedolaga (DB + Redis + бот + кабинет)" "Full Bedolaga (DB + Redis + bot + cabinet)")"
  menu_option "5" "$(tr_text "Полный перенос: Remnawave + Bedolaga (весь backup)" "Full migration: Remnawave + Bedolaga (entire backup)")"
  print_separator
  read_menu_choice restore_scope_choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
  if is_back_command "$restore_scope_choice"; then
    return 1
  fi
  case "$restore_scope_choice" in
    1) restore_only="bedolaga-db,bedolaga-redis,bedolaga-bot" ;;
    2) restore_only="bedolaga-cabinet" ;;
    3) restore_only="bedolaga-bot,bedolaga-cabinet" ;;
    4) restore_only="bedolaga" ;;
    5) restore_only="all,bedolaga" ;;
    *)
      paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
      wait_for_enter
      return 1
      ;;
  esac

  if ask_yes_no "$(tr_text "Подготовить репозитории Bedolaga перед восстановлением?" "Prepare Bedolaga repositories before restore?")" "y"; then
    bedolaga_prepare_local_repos_for_restore "$bot_repo_url" "$cabinet_repo_url" "$target_bot_dir" "$target_cabinet_dir" || true
  fi

  run_restore_wizard_flow "$restore_only" "1"
}

run_bedolaga_remote_migration_flow() {
  local archive_path=""
  local latest_archive=""
  local ssh_host=""
  local ssh_user="root"
  local ssh_port="22"
  local ssh_password=""
  local remote_backup_dir="/var/backups/panel"
  local remote_archive=""
  local restore_scope_choice=""
  local restore_only="bedolaga-bot,bedolaga-cabinet"
  local create_fresh_backup=0
  local fresh_backup_scope=""
  local restore_no_restart=1
  local restore_password="${BACKUP_PASSWORD:-}"
  local is_encrypted_archive=0
  local auto_prepare_remote=1
  local include_caddy=0
  local detected_caddy_dir=""
  local detected_caddy_container=""
  local remote_caddy_dir="/root/caddy"
  local confirm_rc=0
  local ssh_cmd=()
  local scp_cmd=()
  local bootstrap_cmd=""
  local remote_cmd=""
  local preseed_cmd=""
  local postcheck_cmd=""
  local only_args=""
  local item=""
  local caddy_source=""
  local caddy_parent=""
  local caddy_up_cmd=""
  local old_include="${BACKUP_INCLUDE-__PBM_UNSET__}"
  local bot_repo_url=""
  local cabinet_repo_url=""
  local archive_bedolaga_profile=""
  local archive_bot_repo_origin=""
  local archive_cabinet_repo_origin=""
  local archive_db_container=""
  local archive_redis_container=""
  local remote_repo_prepare_cmd=""
  local remote_env_prefix=""
  local remote_network_prepare_cmd="docker network inspect remnawave-network >/dev/null 2>&1 || docker network create remnawave-network >/dev/null 2>&1 || true; docker network inspect bedolaga-network >/dev/null 2>&1 || docker network create bedolaga-network >/dev/null 2>&1 || true"
  local postcheck_db_container="remnawave_bot_db"
  local postcheck_redis_container="remnawave_bot_redis"
  local local_restore_bin="${PBM_LOCAL_RESTORE_BIN:-/usr/local/bin/panel-restore.sh}"
  local local_backup_bin="${PBM_LOCAL_BACKUP_BIN:-/usr/local/bin/panel-backup.sh}"
  local target_remnawave_dir=""
  local target_bot_dir=""
  local target_cabinet_dir=""

  latest_archive="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  archive_path="${BACKUP_FILE:-$latest_archive}"
  bot_repo_url="$(bedolaga_resolve_migration_repo_url "bot" "${BEDOLAGA_BOT_REPO_DEFAULT}")"
  cabinet_repo_url="$(bedolaga_resolve_migration_repo_url "cabinet" "${BEDOLAGA_CABINET_REPO_DEFAULT}")"

  draw_subheader "$(tr_text "Миграция Bedolaga на новый VPS (SSH)" "Bedolaga migration to a new VPS (SSH)")"
  paint "$CLR_MUTED" "$(tr_text "Сценарий: копирование архива на удалённый сервер и запуск panel-restore.sh." "Flow: copy archive to remote server and run panel-restore.sh.")"
  paint "$CLR_MUTED" "$(tr_text "Можно включить автоподготовку пустого VPS: Docker + panel-restore.sh + подготовка контейнеров." "You can enable auto-prepare for an empty VPS: Docker + panel-restore.sh + container bootstrap.")"
  paint "$CLR_MUTED" "$(tr_text "Для пустого VPS будут использованы репозитории:" "Repositories used for empty VPS bootstrap:")"
  paint "$CLR_MUTED" "  bot: ${bot_repo_url}"
  paint "$CLR_MUTED" "  cabinet: ${cabinet_repo_url}"

  archive_path="$(ask_value "$(tr_text "Путь к локальному архиву для переноса (Enter = последний)" "Local backup archive path for migration (Enter = latest)")" "$archive_path")"
  [[ "$archive_path" == "__PBM_BACK__" ]] && return 1

  draw_subheader "$(tr_text "Выбор состава восстановления на новом VPS" "Select restore scope on the new VPS")"
  menu_option "1" "$(tr_text "Бот Bedolaga полностью (DB + Redis + файлы)" "Full Bedolaga bot (DB + Redis + files)")"
  menu_option "2" "$(tr_text "Файлы кабинета Bedolaga" "Bedolaga cabinet files")"
  menu_option "3" "$(tr_text "Файлы бота + кабинета (без DB/Redis, рекомендовано для старта)" "Bot + cabinet files (without DB/Redis, recommended to start)")"
  menu_option "4" "$(tr_text "Полный Bedolaga (DB + Redis + бот + кабинет)" "Full Bedolaga (DB + Redis + bot + cabinet)")"
  menu_option "5" "$(tr_text "Полный перенос: Remnawave + Bedolaga (весь backup)" "Full migration: Remnawave + Bedolaga (entire backup)")"
  print_separator
  read_menu_choice restore_scope_choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
  if is_back_command "$restore_scope_choice"; then
    return 1
  fi
  case "$restore_scope_choice" in
    1) restore_only="bedolaga-db,bedolaga-redis,bedolaga-bot" ;;
    2) restore_only="bedolaga-cabinet" ;;
    3) restore_only="bedolaga-bot,bedolaga-cabinet" ;;
    4) restore_only="bedolaga" ;;
    5) restore_only="all,bedolaga" ;;
    *)
      paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
      wait_for_enter
      return 1
      ;;
  esac

  confirm_rc=0
  ask_yes_no "$(tr_text "Создать свежий backup перед отправкой на новый VPS?" "Create a fresh backup before sending to the new VPS?")" "y" || confirm_rc=$?
  case "$confirm_rc" in
    0) create_fresh_backup=1 ;;
    1) create_fresh_backup=0 ;;
    2) return 1 ;;
  esac
  if (( create_fresh_backup == 1 )); then
    case "$restore_only" in
      all,bedolaga|bedolaga,all) fresh_backup_scope="all,bedolaga" ;;
      bedolaga) fresh_backup_scope="bedolaga" ;;
      bedolaga-cabinet) fresh_backup_scope="bedolaga-cabinet" ;;
      bedolaga-db,bedolaga-redis,bedolaga-bot) fresh_backup_scope="bedolaga-db,bedolaga-redis,bedolaga-bot" ;;
      *) fresh_backup_scope="bedolaga-bot,bedolaga-cabinet" ;;
    esac

    paint "$CLR_ACCENT" "$(tr_text "Создаю свежий backup перед миграцией..." "Creating a fresh backup before migration...")"
    export BACKUP_INCLUDE="$fresh_backup_scope"
    if ! run_backup_now; then
      if [[ "$old_include" == "__PBM_UNSET__" ]]; then
        unset BACKUP_INCLUDE
      else
        export BACKUP_INCLUDE="$old_include"
      fi
      paint "$CLR_DANGER" "$(tr_text "Не удалось создать свежий backup." "Failed to create a fresh backup.")"
      wait_for_enter
      return 1
    fi
    if [[ "$old_include" == "__PBM_UNSET__" ]]; then
      unset BACKUP_INCLUDE
    else
      export BACKUP_INCLUDE="$old_include"
    fi

    latest_archive="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
    archive_path="$latest_archive"
    [[ -n "$archive_path" && -f "$archive_path" ]] || {
      paint "$CLR_DANGER" "$(tr_text "Свежий backup не найден после создания." "Fresh backup not found after creation.")"
      wait_for_enter
      return 1
    }
    paint "$CLR_OK" "$(tr_text "Свежий backup готов:" "Fresh backup is ready:") ${archive_path}"
  fi

  if [[ -z "$archive_path" ]]; then
    archive_path="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  fi
  [[ -n "$archive_path" && -f "$archive_path" ]] || {
    paint "$CLR_DANGER" "$(tr_text "Локальный архив не найден." "Local archive not found.")"
    wait_for_enter
    return 1
  }

  confirm_rc=0
  ask_yes_no "$(tr_text "Включить автоподготовку нового VPS (рекомендуется)?" "Enable auto-prepare for the new VPS (recommended)?")" "y" || confirm_rc=$?
  case "$confirm_rc" in
    0) auto_prepare_remote=1 ;;
    1) auto_prepare_remote=0 ;;
    2) return 1 ;;
  esac

  confirm_rc=0
  ask_yes_no "$(tr_text "Отключить автоперезапуск сервисов на новом VPS (--no-restart)?" "Disable service auto-restart on the new VPS (--no-restart)?")" "n" || confirm_rc=$?
  case "$confirm_rc" in
    0) restore_no_restart=1 ;;
    1) restore_no_restart=0 ;;
    2) return 1 ;;
  esac

  ssh_host="$(ask_value "$(tr_text "IP/домен нового VPS" "New VPS IP/domain")" "$ssh_host")"
  [[ "$ssh_host" == "__PBM_BACK__" ]] && return 1
  [[ -n "$ssh_host" ]] || {
    paint "$CLR_DANGER" "$(tr_text "Хост не задан." "Host is not set.")"
    wait_for_enter
    return 1
  }
  if ! validate_ssh_token_or_warn "SSH_HOST" "$ssh_host"; then
    wait_for_enter
    return 1
  fi

  ssh_user="$(ask_value "$(tr_text "SSH пользователь" "SSH user")" "$ssh_user")"
  [[ "$ssh_user" == "__PBM_BACK__" ]] && return 1
  [[ -n "$ssh_user" ]] || ssh_user="root"
  if ! validate_ssh_token_or_warn "SSH_USER" "$ssh_user"; then
    wait_for_enter
    return 1
  fi

  ssh_port="$(ask_value "$(tr_text "SSH порт" "SSH port")" "$ssh_port")"
  [[ "$ssh_port" == "__PBM_BACK__" ]] && return 1
  if ! validate_tcp_port_or_warn "SSH_PORT" "$ssh_port"; then
    wait_for_enter
    return 1
  fi

  ssh_password="$(ask_secret_value "$(tr_text "SSH пароль (опционально, Enter = использовать ключи)" "SSH password (optional, Enter = use SSH keys)")" "")"
  [[ "$ssh_password" == "__PBM_BACK__" ]] && return 1

  remote_backup_dir="$(ask_value "$(tr_text "Папка архива на новом VPS" "Remote archive directory on new VPS")" "$remote_backup_dir")"
  [[ "$remote_backup_dir" == "__PBM_BACK__" ]] && return 1
  [[ -n "$remote_backup_dir" ]] || remote_backup_dir="/var/backups/panel"
  if ! validate_project_path_or_warn "REMOTE_BACKUP_DIR" "$remote_backup_dir"; then
    wait_for_enter
    return 1
  fi
  remote_archive="${remote_backup_dir}/$(basename "$archive_path")"

  detected_caddy_dir=""
  detected_caddy_container=""
  for c in remnawave-caddy remnawave_caddy caddy; do
    caddy_source="$(docker inspect "$c" --format '{{range .Mounts}}{{if eq .Destination "/etc/caddy/Caddyfile"}}{{println .Source}}{{end}}{{end}}' 2>/dev/null | head -n1 || true)"
    [[ -n "$caddy_source" ]] || continue
    caddy_source="$(echo "$caddy_source" | xargs 2>/dev/null || echo "$caddy_source")"
    [[ -f "$caddy_source" ]] || continue
    caddy_parent="$(dirname "$caddy_source")"
    if [[ -f "${caddy_parent}/docker-compose.yml" || -f "${caddy_parent}/docker-compose.caddy.yml" || -f "${caddy_parent}/compose.yaml" || -f "${caddy_parent}/compose.yml" ]]; then
      detected_caddy_dir="$caddy_parent"
      detected_caddy_container="$c"
      break
    fi
  done
  if [[ -z "$detected_caddy_dir" ]] && [[ -f /root/caddy/Caddyfile ]] && [[ -f /root/caddy/docker-compose.yml || -f /root/caddy/docker-compose.caddy.yml || -f /root/caddy/compose.yaml || -f /root/caddy/compose.yml ]]; then
    detected_caddy_dir="/root/caddy"
    detected_caddy_container="remnawave-caddy"
  fi
  if [[ -n "$detected_caddy_dir" ]]; then
    confirm_rc=0
    ask_yes_no "$(tr_text "Найден Docker Caddy. Перенести Caddy на новый VPS?" "Docker Caddy detected. Migrate Caddy to the new VPS?")" "y" || confirm_rc=$?
    case "$confirm_rc" in
      0) include_caddy=1 ;;
      1) include_caddy=0 ;;
      2) return 1 ;;
    esac
    if (( include_caddy == 1 )); then
      remote_caddy_dir="$(ask_value "$(tr_text "Путь Caddy на новом VPS" "Caddy path on the new VPS")" "$remote_caddy_dir")"
      [[ "$remote_caddy_dir" == "__PBM_BACK__" ]] && return 1
      [[ -n "$remote_caddy_dir" ]] || remote_caddy_dir="/root/caddy"
      if ! validate_project_path_or_warn "REMOTE_CADDY_DIR" "$remote_caddy_dir"; then
        wait_for_enter
        return 1
      fi
    fi
  fi

  if [[ "$archive_path" == *.gpg ]]; then
    is_encrypted_archive=1
    restore_password="$(ask_secret_value "$(tr_text "Пароль шифрования архива (BACKUP_PASSWORD) для нового VPS" "Archive encryption password (BACKUP_PASSWORD) for new VPS")" "$restore_password")"
    [[ "$restore_password" == "__PBM_BACK__" ]] && return 1
    [[ -n "$restore_password" ]] || {
      paint "$CLR_DANGER" "$(tr_text "Для .gpg архива нужен пароль шифрования." "Encryption password is required for .gpg archive.")"
      wait_for_enter
      return 1
    }
  fi

  target_remnawave_dir="$(archive_backup_info_value "$archive_path" "remnawave_dir" "$restore_password")"
  target_bot_dir="$(archive_backup_info_value "$archive_path" "bedolaga_bot_dir" "$restore_password")"
  target_cabinet_dir="$(archive_backup_info_value "$archive_path" "bedolaga_cabinet_dir" "$restore_password")"
  archive_bedolaga_profile="$(archive_backup_info_value "$archive_path" "bedolaga_stack_profile" "$restore_password")"
  archive_bot_repo_origin="$(archive_backup_info_value "$archive_path" "bedolaga_bot_repo_origin" "$restore_password")"
  archive_cabinet_repo_origin="$(archive_backup_info_value "$archive_path" "bedolaga_cabinet_repo_origin" "$restore_password")"
  archive_db_container="$(archive_backup_info_value "$archive_path" "bedolaga_db_container" "$restore_password")"
  archive_redis_container="$(archive_backup_info_value "$archive_path" "bedolaga_redis_container" "$restore_password")"
  if declare -F bedolaga_repo_url_to_https >/dev/null 2>&1; then
    archive_bot_repo_origin="$(bedolaga_repo_url_to_https "$archive_bot_repo_origin")"
    archive_cabinet_repo_origin="$(bedolaga_repo_url_to_https "$archive_cabinet_repo_origin")"
  fi
  if declare -F bedolaga_normalize_git_repo_url >/dev/null 2>&1; then
    archive_bot_repo_origin="$(bedolaga_normalize_git_repo_url "$archive_bot_repo_origin")"
    archive_cabinet_repo_origin="$(bedolaga_normalize_git_repo_url "$archive_cabinet_repo_origin")"
  fi
  if bedolaga_validate_git_repo_url "$archive_bot_repo_origin"; then
    bot_repo_url="$archive_bot_repo_origin"
  fi
  if bedolaga_validate_git_repo_url "$archive_cabinet_repo_origin"; then
    cabinet_repo_url="$archive_cabinet_repo_origin"
  fi
  postcheck_db_container="${archive_db_container:-remnawave_bot_db}"
  postcheck_redis_container="${archive_redis_container:-remnawave_bot_redis}"
  target_bot_dir="${target_bot_dir:-/root/remnawave-bedolaga-telegram-bot}"
  target_cabinet_dir="${target_cabinet_dir:-/root/bedolaga-cabinet}"
  if [[ -n "$target_remnawave_dir" ]] && ! validate_project_path_or_warn "REMOTE_REMNAWAVE_DIR" "$target_remnawave_dir"; then
    wait_for_enter
    return 1
  fi
  if ! validate_project_path_or_warn "REMOTE_BEDOLAGA_BOT_DIR" "$target_bot_dir"; then
    wait_for_enter
    return 1
  fi
  if ! validate_project_path_or_warn "REMOTE_BEDOLAGA_CABINET_DIR" "$target_cabinet_dir"; then
    wait_for_enter
    return 1
  fi
  if [[ "$target_bot_dir" == "$target_cabinet_dir" || ( -n "$target_remnawave_dir" && ( "$target_bot_dir" == "$target_remnawave_dir" || "$target_cabinet_dir" == "$target_remnawave_dir" ) ) ]]; then
    paint "$CLR_WARN" "$(tr_text "Каталоги восстановления на новом VPS должны быть разными." "Restore directories on the new VPS must be different.")"
    wait_for_enter
    return 1
  fi
  [[ -n "$target_remnawave_dir" ]] && remote_env_prefix="${remote_env_prefix} REMNAWAVE_DIR=$(printf '%q' "$target_remnawave_dir")"
  [[ -n "$target_bot_dir" ]] && remote_env_prefix="${remote_env_prefix} BEDOLAGA_BOT_DIR=$(printf '%q' "$target_bot_dir")"
  [[ -n "$target_cabinet_dir" ]] && remote_env_prefix="${remote_env_prefix} BEDOLAGA_CABINET_DIR=$(printf '%q' "$target_cabinet_dir")"
  remote_env_prefix="${remote_env_prefix# }"

  command -v ssh >/dev/null 2>&1 || {
    paint "$CLR_DANGER" "$(tr_text "Не найдена команда ssh." "ssh command not found.")"
    wait_for_enter
    return 1
  }
  command -v scp >/dev/null 2>&1 || {
    paint "$CLR_DANGER" "$(tr_text "Не найдена команда scp." "scp command not found.")"
    wait_for_enter
    return 1
  }
  if [[ -n "$ssh_password" ]] && ! command -v sshpass >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "Для входа по паролю нужен sshpass. Пробую установить автоматически..." "sshpass is required for password-based login. Trying to install it automatically...")"
    if ! install_package "sshpass" >/dev/null 2>&1 || ! command -v sshpass >/dev/null 2>&1; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось установить sshpass автоматически. Установите его вручную или используйте SSH-ключи." "Failed to install sshpass automatically. Install it manually or use SSH keys.")"
      wait_for_enter
      return 1
    fi
    paint "$CLR_OK" "$(tr_text "sshpass установлен автоматически." "sshpass was installed automatically.")"
  fi

  if [[ -n "$ssh_password" ]]; then
    ssh_cmd=(sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=accept-new -p "$ssh_port" "${ssh_user}@${ssh_host}")
    scp_cmd=(sshpass -p "$ssh_password" scp -o StrictHostKeyChecking=accept-new -P "$ssh_port")
  else
    ssh_cmd=(ssh -o StrictHostKeyChecking=accept-new -p "$ssh_port" "${ssh_user}@${ssh_host}")
    scp_cmd=(scp -o StrictHostKeyChecking=accept-new -P "$ssh_port")
  fi

  paint "$CLR_TITLE" "$(tr_text "Итог удалённой миграции" "Remote migration summary")"
  paint "$CLR_MUTED" "  $(tr_text "Локальный архив:" "Local archive:") ${archive_path}"
  paint "$CLR_MUTED" "  $(tr_text "Новый VPS:" "New VPS:") ${ssh_user}@${ssh_host}:${ssh_port}"
  paint "$CLR_MUTED" "  $(tr_text "Файл на новом VPS:" "Archive on new VPS:") ${remote_archive}"
  paint "$CLR_MUTED" "  $(tr_text "Состав восстановления:" "Restore scope:") ${restore_only}"
  if [[ -n "$archive_bedolaga_profile" ]]; then
    paint "$CLR_MUTED" "  $(tr_text "Профиль Bedolaga в архиве:" "Bedolaga archive profile:") ${archive_bedolaga_profile}"
  fi
  paint "$CLR_MUTED" "  $(tr_text "Репозиторий бота:" "Bot repository:") ${bot_repo_url}"
  paint "$CLR_MUTED" "  $(tr_text "Репозиторий кабинета:" "Cabinet repository:") ${cabinet_repo_url}"
  paint "$CLR_MUTED" "  $(tr_text "Автоподготовка VPS:" "VPS auto-prepare:") $([[ "$auto_prepare_remote" == "1" ]] && tr_text "включена" "enabled" || tr_text "выключена" "disabled")"
  if (( include_caddy == 1 )); then
    paint "$CLR_MUTED" "  $(tr_text "Caddy перенос:" "Caddy migration:") ${detected_caddy_dir} -> ${remote_caddy_dir}"
  else
    paint "$CLR_MUTED" "  $(tr_text "Caddy перенос:" "Caddy migration:") $(tr_text "пропущен" "skipped")"
  fi
  paint "$CLR_MUTED" "  $(tr_text "Режим:" "Mode:") $(tr_text "рабочее восстановление" "real restore")"
  paint "$CLR_MUTED" "  $(tr_text "Перезапуски:" "Restarts:") $([[ "$restore_no_restart" == "1" ]] && tr_text "отключены (--no-restart)" "disabled (--no-restart)" || tr_text "включены" "enabled")"
  if [[ -n "$ssh_password" ]]; then
    paint "$CLR_MUTED" "  $(tr_text "SSH аутентификация:" "SSH authentication:") $(tr_text "пароль" "password")"
  else
    paint "$CLR_MUTED" "  $(tr_text "SSH аутентификация:" "SSH authentication:") $(tr_text "ключи" "keys")"
  fi

  confirm_rc=0
  ask_yes_no "$(tr_text "Выполнить копирование и удалённое восстановление?" "Run copy and remote restore?")" "n" || confirm_rc=$?
  case "$confirm_rc" in
    0) ;;
    1|2) return 1 ;;
  esac

  if ! "${ssh_cmd[@]}" "mkdir -p $(printf '%q' "$remote_backup_dir")"; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось создать папку на новом VPS." "Failed to create directory on the new VPS.")"
    wait_for_enter
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Копирую архив на новый VPS..." "Copying archive to the new VPS...")"
  if ! "${scp_cmd[@]}" "$archive_path" "${ssh_user}@${ssh_host}:$(printf '%q' "$remote_archive")"; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось скопировать архив на новый VPS." "Failed to copy archive to the new VPS.")"
    wait_for_enter
    return 1
  fi

  if (( include_caddy == 1 )); then
    paint "$CLR_ACCENT" "$(tr_text "Копирую Caddy-конфиг и compose на новый VPS..." "Copying Caddy config and compose to the new VPS...")"
    if [[ ! -d "$detected_caddy_dir" ]]; then
      paint "$CLR_DANGER" "$(tr_text "Исходная папка Caddy недоступна." "Source Caddy directory is not accessible.")"
      wait_for_enter
      return 1
    fi
    if ! "${ssh_cmd[@]}" "mkdir -p $(printf '%q' "$remote_caddy_dir")"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось создать папку Caddy на новом VPS." "Failed to create Caddy directory on the new VPS.")"
      wait_for_enter
      return 1
    fi
    if ! tar -C "$detected_caddy_dir" -czf - . | "${ssh_cmd[@]}" "tar -xzf - -C $(printf '%q' "$remote_caddy_dir")"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось перенести файлы Caddy на новый VPS." "Failed to transfer Caddy files to the new VPS.")"
      wait_for_enter
      return 1
    fi
  fi

  if (( auto_prepare_remote == 1 )); then
    paint "$CLR_ACCENT" "$(tr_text "Подготавливаю новый VPS (Docker/Compose)..." "Preparing new VPS (Docker/Compose)...")"
    bootstrap_cmd='set -e
if ! command -v curl >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y curl >/dev/null 2>&1; fi
  if command -v dnf >/dev/null 2>&1; then dnf install -y curl >/dev/null 2>&1; fi
  if command -v yum >/dev/null 2>&1; then yum install -y curl >/dev/null 2>&1; fi
  if command -v apk >/dev/null 2>&1; then apk add --no-cache curl >/dev/null 2>&1; fi
fi
if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y git >/dev/null 2>&1; fi
  if command -v dnf >/dev/null 2>&1; then dnf install -y git >/dev/null 2>&1; fi
  if command -v yum >/dev/null 2>&1; then yum install -y git >/dev/null 2>&1; fi
  if command -v apk >/dev/null 2>&1; then apk add --no-cache git >/dev/null 2>&1; fi
fi
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker >/dev/null 2>&1 || true
if ! docker compose version >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true; fi
  if command -v dnf >/dev/null 2>&1; then dnf install -y docker-compose-plugin >/dev/null 2>&1 || true; fi
  if command -v yum >/dev/null 2>&1; then yum install -y docker-compose-plugin >/dev/null 2>&1 || true; fi
fi'
    if ! "${ssh_cmd[@]}" "$bootstrap_cmd"; then
      paint "$CLR_DANGER" "$(tr_text "Автоподготовка VPS завершилась ошибкой." "VPS auto-prepare failed.")"
      wait_for_enter
      return 1
    fi

    if ! sync_runtime_scripts; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось обновить локальные runtime-скрипты перед отправкой на новый VPS." "Failed to refresh local runtime scripts before uploading them to the new VPS.")"
      wait_for_enter
      return 1
    fi

    if [[ ! -x "$local_restore_bin" ]]; then
      paint "$CLR_DANGER" "$(tr_text "Локально не найден panel-restore.sh для копирования на новый VPS." "Local panel-restore.sh not found for upload to new VPS.") ${local_restore_bin}"
      wait_for_enter
      return 1
    fi
    paint "$CLR_ACCENT" "$(tr_text "Копирую runtime restore-скрипты на новый VPS..." "Uploading runtime restore scripts to the new VPS...")"
    if ! "${scp_cmd[@]}" "$local_restore_bin" "${ssh_user}@${ssh_host}:/usr/local/bin/panel-restore.sh"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось скопировать panel-restore.sh на новый VPS." "Failed to copy panel-restore.sh to new VPS.")"
      wait_for_enter
      return 1
    fi
    if [[ -x "$local_backup_bin" ]]; then
      "${scp_cmd[@]}" "$local_backup_bin" "${ssh_user}@${ssh_host}:/usr/local/bin/panel-backup.sh" >/dev/null 2>&1 || true
    fi
    if ! "${ssh_cmd[@]}" "chmod 755 /usr/local/bin/panel-restore.sh /usr/local/bin/panel-backup.sh >/dev/null 2>&1 || true"; then
      paint "$CLR_WARN" "$(tr_text "Не удалось применить chmod для runtime-скриптов на новом VPS." "Failed to chmod runtime scripts on new VPS.")"
    fi

    remote_repo_prepare_cmd="set +e
if command -v git >/dev/null 2>&1; then
  if [ ! -d $(printf '%q' "$target_bot_dir")/.git ]; then
    if [ -e $(printf '%q' "$target_bot_dir") ] && [ ! -d $(printf '%q' "$target_bot_dir")/.git ]; then
      echo 'populate bot repo into existing non-git directory $(printf '%q' "$target_bot_dir")'
      tmp_repo_dir=\$(mktemp -d /tmp/bedolaga-bot-repo.XXXXXX 2>/dev/null || mktemp -d)
      if git clone $(printf '%q' "$bot_repo_url") \"\$tmp_repo_dir\"; then
        mkdir -p $(printf '%q' "$target_bot_dir")
        cp -a \"\$tmp_repo_dir\"/. $(printf '%q' "$target_bot_dir")/ || echo 'warn: failed to copy bot repo contents into existing directory'
      else
        echo 'warn: failed to clone bot repo into temp directory'
      fi
      rm -rf \"\$tmp_repo_dir\" >/dev/null 2>&1 || true
    else
      rm -rf $(printf '%q' "$target_bot_dir") >/dev/null 2>&1 || true
      git clone $(printf '%q' "$bot_repo_url") $(printf '%q' "$target_bot_dir") || echo 'warn: failed to clone bot repo'
    fi
  fi
  if [ ! -d $(printf '%q' "$target_cabinet_dir")/.git ]; then
    if [ -e $(printf '%q' "$target_cabinet_dir") ] && [ ! -d $(printf '%q' "$target_cabinet_dir")/.git ]; then
      echo 'populate cabinet repo into existing non-git directory $(printf '%q' "$target_cabinet_dir")'
      tmp_repo_dir=\$(mktemp -d /tmp/bedolaga-cabinet-repo.XXXXXX 2>/dev/null || mktemp -d)
      if git clone $(printf '%q' "$cabinet_repo_url") \"\$tmp_repo_dir\"; then
        mkdir -p $(printf '%q' "$target_cabinet_dir")
        cp -a \"\$tmp_repo_dir\"/. $(printf '%q' "$target_cabinet_dir")/ || echo 'warn: failed to copy cabinet repo contents into existing directory'
      else
        echo 'warn: failed to clone cabinet repo into temp directory'
      fi
      rm -rf \"\$tmp_repo_dir\" >/dev/null 2>&1 || true
    else
      rm -rf $(printf '%q' "$target_cabinet_dir") >/dev/null 2>&1 || true
      git clone $(printf '%q' "$cabinet_repo_url") $(printf '%q' "$target_cabinet_dir") || echo 'warn: failed to clone cabinet repo'
    fi
  fi
else
  echo 'warn: git is unavailable on remote VPS, skipping repo bootstrap'
fi
true"
    if [[ "$restore_only" == *bedolaga* ]]; then
      paint "$CLR_ACCENT" "$(tr_text "Подготавливаю репозитории Bedolaga на новом VPS..." "Preparing Bedolaga repositories on the new VPS...")"
      if ! "${ssh_cmd[@]}" "$remote_repo_prepare_cmd"; then
        paint "$CLR_WARN" "$(tr_text "Не удалось полностью подготовить репозитории Bedolaga на новом VPS. Продолжаю по архиву." "Failed to fully prepare Bedolaga repositories on the new VPS. Continuing with archive-only restore.")"
      fi
    fi
  fi

  if ! "${ssh_cmd[@]}" "test -x /usr/local/bin/panel-restore.sh"; then
    paint "$CLR_DANGER" "$(tr_text "На новом VPS не найден /usr/local/bin/panel-restore.sh." "Could not find /usr/local/bin/panel-restore.sh on the new VPS.")"
    wait_for_enter
    return 1
  fi

  IFS=',' read -r -a __restore_items <<< "$restore_only"
  only_args=""
  for item in "${__restore_items[@]}"; do
    [[ -n "$item" ]] || continue
    only_args="${only_args} --only $(printf '%q' "$item")"
  done

  remote_cmd="/usr/local/bin/panel-restore.sh --from $(printf '%q' "$remote_archive")${only_args}"
  if [[ -n "$remote_env_prefix" ]]; then
    remote_cmd="${remote_env_prefix} ${remote_cmd}"
  fi
  if (( restore_no_restart == 1 )); then
    remote_cmd="${remote_cmd} --no-restart"
  fi
  if (( is_encrypted_archive == 1 )); then
    remote_cmd="BACKUP_PASSWORD=$(printf '%q' "$restore_password") ${remote_cmd}"
  fi

  if (( auto_prepare_remote == 1 )) && [[ "$restore_only" == "bedolaga-db,bedolaga-redis,bedolaga-bot" ]]; then
    paint "$CLR_ACCENT" "$(tr_text "Пустой VPS: предварительно разворачиваю bot и поднимаю контейнеры перед восстановлением bot DB/Redis..." "Empty VPS: pre-seeding bot files and starting containers before bot DB/Redis restore...")"
    preseed_cmd="/usr/local/bin/panel-restore.sh --from $(printf '%q' "$remote_archive") --only bedolaga-bot --no-restart"
    if [[ -n "$remote_env_prefix" ]]; then
      preseed_cmd="${remote_env_prefix} ${preseed_cmd}"
    fi
    if (( is_encrypted_archive == 1 )); then
      preseed_cmd="BACKUP_PASSWORD=$(printf '%q' "$restore_password") ${preseed_cmd}"
    fi
    if ! "${ssh_cmd[@]}" "$preseed_cmd"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось выполнить предварительное восстановление бота на новом VPS." "Failed to run bot pre-restore on the new VPS.")"
      wait_for_enter
      return 1
    fi
    if ! "${ssh_cmd[@]}" "set -e; test -f $(printf '%q' "$target_bot_dir")/.env; mkdir -p $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data $(printf '%q' "$target_bot_dir")/data/backups $(printf '%q' "$target_bot_dir")/data/referral_qr; chown -R 1000:1000 $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data >/dev/null 2>&1 || true; chmod -R 755 $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data >/dev/null 2>&1 || true; ${remote_network_prepare_cmd}; cd $(printf '%q' "$target_bot_dir") && docker compose up -d"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось поднять контейнеры Bedolaga бота на новом VPS." "Failed to start Bedolaga bot containers on the new VPS.")"
      wait_for_enter
      return 1
    fi
  fi

  if (( auto_prepare_remote == 1 )) && [[ "$restore_only" == "bedolaga" ]]; then
    paint "$CLR_ACCENT" "$(tr_text "Пустой VPS: предварительно разворачиваю bot+cabinet и поднимаю контейнеры перед полным restore..." "Empty VPS: pre-seeding bot+cabinet and starting containers before full restore...")"
    preseed_cmd="/usr/local/bin/panel-restore.sh --from $(printf '%q' "$remote_archive") --only bedolaga-bot --only bedolaga-cabinet --no-restart"
    if [[ -n "$remote_env_prefix" ]]; then
      preseed_cmd="${remote_env_prefix} ${preseed_cmd}"
    fi
    if (( is_encrypted_archive == 1 )); then
      preseed_cmd="BACKUP_PASSWORD=$(printf '%q' "$restore_password") ${preseed_cmd}"
    fi
    if ! "${ssh_cmd[@]}" "$preseed_cmd"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось выполнить предварительное восстановление bot+cabinet на новом VPS." "Failed to run bot+cabinet pre-restore on the new VPS.")"
      wait_for_enter
      return 1
    fi
    if ! "${ssh_cmd[@]}" "set -e; test -f $(printf '%q' "$target_bot_dir")/.env; mkdir -p $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data $(printf '%q' "$target_bot_dir")/data/backups $(printf '%q' "$target_bot_dir")/data/referral_qr; chown -R 1000:1000 $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data >/dev/null 2>&1 || true; chmod -R 755 $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data >/dev/null 2>&1 || true; ${remote_network_prepare_cmd}; cd $(printf '%q' "$target_bot_dir") && docker compose up -d; cabdir=$(printf '%q' "$target_cabinet_dir"); if [ -d \"\$cabdir\" ]; then if [ -f \"\$cabdir/.env\" ] && { [ -f \"\$cabdir/docker-compose.yml\" ] || [ -f \"\$cabdir/docker-compose.caddy.yml\" ] || [ -f \"\$cabdir/compose.yaml\" ] || [ -f \"\$cabdir/compose.yml\" ]; }; then cd \"\$cabdir\" && docker compose up -d; fi; fi"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось поднять контейнеры Bedolaga на новом VPS." "Failed to start Bedolaga containers on the new VPS.")"
      wait_for_enter
      return 1
    fi
  fi

  if (( auto_prepare_remote == 1 )) && ([[ "$restore_only" == "all,bedolaga" ]] || [[ "$restore_only" == "bedolaga,all" ]]); then
    paint "$CLR_ACCENT" "$(tr_text "Пустой VPS: предварительно разворачиваю Remnawave+Bedolaga конфиги и поднимаю контейнеры перед полным restore..." "Empty VPS: pre-seeding Remnawave+Bedolaga configs and starting containers before full restore...")"
    preseed_cmd="/usr/local/bin/panel-restore.sh --from $(printf '%q' "$remote_archive") --only env --only compose --only caddy --only subscription --only bedolaga-bot --only bedolaga-cabinet --no-restart"
    if [[ -n "$remote_env_prefix" ]]; then
      preseed_cmd="${remote_env_prefix} ${preseed_cmd}"
    fi
    if (( is_encrypted_archive == 1 )); then
      preseed_cmd="BACKUP_PASSWORD=$(printf '%q' "$restore_password") ${preseed_cmd}"
    fi
    if ! "${ssh_cmd[@]}" "$preseed_cmd"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось выполнить предварительное восстановление Remnawave+Bedolaga на новом VPS." "Failed to run Remnawave+Bedolaga pre-restore on the new VPS.")"
      wait_for_enter
      return 1
    fi
    if ! "${ssh_cmd[@]}" "set -e; ${remote_network_prepare_cmd}; paneldir=$(printf '%q' "$target_remnawave_dir"); if [ -z \"\$paneldir\" ] || { [ ! -d \"\$paneldir\" ] && [ ! -f \"\$paneldir/docker-compose.yml\" ] && [ ! -f \"\$paneldir/compose.yaml\" ] && [ ! -f \"\$paneldir/compose.yml\" ]; }; then paneldir=''; for d in /opt/remnawave /srv/remnawave /root/remnawave /home/remnawave; do if [ -f \"\$d/.env\" ] && [ -f \"\$d/docker-compose.yml\" ]; then paneldir=\"\$d\"; break; fi; done; if [ -z \"\$paneldir\" ]; then paneldir=$(find /root /opt /srv /home -maxdepth 6 -type d -name remnawave 2>/dev/null | while read -r d; do [ -f \"\$d/.env\" ] && [ -f \"\$d/docker-compose.yml\" ] || continue; echo \"\$d\"; break; done); fi; fi; if [ -n \"\$paneldir\" ]; then cd \"\$paneldir\" && docker compose up -d; fi; test -f $(printf '%q' "$target_bot_dir")/.env; mkdir -p $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data $(printf '%q' "$target_bot_dir")/data/backups $(printf '%q' "$target_bot_dir")/data/referral_qr; chown -R 1000:1000 $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data >/dev/null 2>&1 || true; chmod -R 755 $(printf '%q' "$target_bot_dir")/logs $(printf '%q' "$target_bot_dir")/data >/dev/null 2>&1 || true; cd $(printf '%q' "$target_bot_dir") && docker compose up -d; cabdir=$(printf '%q' "$target_cabinet_dir"); if [ -d \"\$cabdir\" ]; then if [ -f \"\$cabdir/.env\" ] && { [ -f \"\$cabdir/docker-compose.yml\" ] || [ -f \"\$cabdir/docker-compose.caddy.yml\" ] || [ -f \"\$cabdir/compose.yaml\" ] || [ -f \"\$cabdir/compose.yml\" ]; }; then cd \"\$cabdir\" && docker compose up -d; fi; fi"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось поднять контейнеры Remnawave+Bedolaga на новом VPS." "Failed to start Remnawave+Bedolaga containers on the new VPS.")"
      wait_for_enter
      return 1
    fi
  fi

  paint "$CLR_ACCENT" "$(tr_text "Запускаю удалённое восстановление..." "Running remote restore...")"
  if ! "${ssh_cmd[@]}" "$remote_cmd"; then
    paint "$CLR_DANGER" "$(tr_text "Удалённое восстановление завершилось ошибкой." "Remote restore failed.")"
    wait_for_enter
    return 1
  fi

  if (( include_caddy == 1 )); then
    paint "$CLR_ACCENT" "$(tr_text "Поднимаю Caddy на новом VPS..." "Starting Caddy on the new VPS...")"
    caddy_up_cmd="set -e; ${remote_network_prepare_cmd}; cd $(printf '%q' "$remote_caddy_dir"); cfile=''; if [ -f docker-compose.yml ]; then cfile='docker-compose.yml'; elif [ -f docker-compose.caddy.yml ]; then cfile='docker-compose.caddy.yml'; elif [ -f compose.yaml ]; then cfile='compose.yaml'; elif [ -f compose.yml ]; then cfile='compose.yml'; fi; if [ -n \"\$cfile\" ]; then docker compose -f \"\$cfile\" up -d; else echo 'compose file not found in caddy dir'; exit 1; fi"
    if ! "${ssh_cmd[@]}" "$caddy_up_cmd"; then
      paint "$CLR_WARN" "$(tr_text "Не удалось запустить Caddy на новом VPS." "Failed to start Caddy on the new VPS.")"
    fi
  fi

  paint "$CLR_ACCENT" "$(tr_text "Проверяю состояние сервисов и последние логи на новом VPS..." "Checking service state and recent logs on the new VPS...")"
  postcheck_cmd='
set +e
db_container='"$(printf '%q' "$postcheck_db_container")"'
redis_container='"$(printf '%q' "$postcheck_redis_container")"'
echo "============================================================"
echo "  Service check: Bedolaga stack"
echo "============================================================"
for c in "$db_container" "$redis_container" remnawave_bot cabinet_frontend remnawave-caddy remnawave_caddy caddy; do
  st="$(docker inspect -f "{{.State.Status}}" "$c" 2>/dev/null || echo "not-found")"
  printf "  %-20s %s\n" "$c:" "$st"
done
echo "------------------------------------------------------------"
echo "docker ps (filtered)"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | awk -v db="$db_container" -v redis="$redis_container" '"'"'NR == 1 || index($0, db) || index($0, redis) || index($0, "remnawave_bot") || index($0, "cabinet_frontend") || index($0, "caddy")'"'"' || true
echo "------------------------------------------------------------"
echo "logs: remnawave_bot (tail 40)"
docker logs --tail 40 remnawave_bot 2>&1 || true
echo "------------------------------------------------------------"
echo "logs: cabinet_frontend (tail 40)"
docker logs --tail 40 cabinet_frontend 2>&1 || true
echo "------------------------------------------------------------"
echo "logs: ${db_container} (tail 30)"
docker logs --tail 30 "$db_container" 2>&1 || true
echo "------------------------------------------------------------"
echo "logs: ${redis_container} (tail 30)"
docker logs --tail 30 "$redis_container" 2>&1 || true
echo "------------------------------------------------------------"
for cc in remnawave-caddy remnawave_caddy caddy; do
  if docker inspect "$cc" >/dev/null 2>&1; then
    echo "logs: ${cc} (tail 30)"
    docker logs --tail 30 "$cc" 2>&1 || true
    break
  fi
done
'
  if ! "${ssh_cmd[@]}" "$postcheck_cmd"; then
    paint "$CLR_WARN" "$(tr_text "Проверка сервисов вернула ошибку. Проверьте SSH/логи вручную." "Service check returned an error. Verify SSH/logs manually.")"
  fi

  paint "$CLR_OK" "$(tr_text "Удалённая миграция завершена." "Remote migration completed.")"
  wait_for_enter
  return 0
}

run_restore_wizard_flow() {
  local preset_restore_only="${1:-all,bedolaga}"
  local lock_restore_only="${2:-0}"
  local choice=""
  local preset_label=""

  draw_restore_step "1" "4" "$(tr_text "Выбор источника архива" "Select backup source")"
  MODE="restore"
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
      bedolaga-db,bedolaga-redis,bedolaga-bot|bedolaga-bot,bedolaga-db,bedolaga-redis) preset_label="$(tr_text "бот Bedolaga полностью (db + redis + файлы)" "full Bedolaga bot (db + redis + files)")" ;;
      bedolaga-cabinet) preset_label="$(tr_text "файлы кабинета Bedolaga" "Bedolaga cabinet files")" ;;
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

  draw_restore_step "3" "4" "$(tr_text "Перезапуски после восстановления" "Restarts after restore")"
  paint "$CLR_MUTED" "$(tr_text "Меню восстановления запускает рабочее восстановление. Перед стартом будет отдельное подтверждение." "The restore menu runs a real restore. A separate confirmation is required before start.")"
  paint "$CLR_MUTED" "$(tr_text "Если отключить перезапуски, сервисы не будут автоматически перезапущены после восстановления." "If restarts are disabled, services will not be restarted automatically after restore.")"

  while true; do
    menu_option "1" "$(tr_text "Автоперезапуск после восстановления (быстрее)" "Auto-restart after restore (faster)")"
    menu_option "2" "$(tr_text "Без автоперезапуска (осторожно)" "No auto-restart (safer)")"
    print_separator
    read_menu_choice choice "$(tr_text "Перезапуски [1-2]: " "Restarts [1-2]: ")"
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
  if ! confirm_restore_phrase; then
    paint "$CLR_WARN" "$(tr_text "Подтверждение не пройдено. Восстановление отменено." "Confirmation failed. Restore cancelled.")"
    wait_for_enter
    return 1
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
    ui_set_breadcrumb "$(tr_text "Главная / Remnawave / Установка" "Home / Remnawave / Install")"
    draw_subheader "$(tr_text "Remnawave: установка и обновление" "Remnawave: install and update")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Операции установки и обновления панели, подписок и Caddy." "Install/update operations for panel, subscription and Caddy.")"
    menu_group "$(tr_text "Установка" "Install")" "$CLR_OK"
    menu_option "1" "$(tr_text "Быстрая установка панели (панель + Caddy)" "Quick panel install (panel + Caddy)")"
    menu_option "2" "$(tr_text "Установить панель Remnawave" "Install Remnawave panel")"
    menu_option "3" "$(tr_text "Установить страницу подписок" "Install subscription page")"
    menu_group "$(tr_text "Обновление" "Update")" "$CLR_WARN"
    menu_option "4" "$(tr_text "Быстрое обновление панели (панель + Caddy)" "Quick panel update (panel + Caddy)")"
    menu_option "5" "$(tr_text "Обновить панель Remnawave" "Update Remnawave panel")"
    menu_option "6" "$(tr_text "Обновить страницу подписок" "Update subscription page")"
    menu_group "Caddy" "$CLR_ACCENT"
    menu_option "7" "$(tr_text "Установить Caddy для панели" "Install panel Caddy")"
    menu_option "8" "$(tr_text "Обновить Caddy для панели" "Update panel Caddy")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "9" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-9]: " "Choice [1-9]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_component_flow_action "$(tr_text "Быстрая установка панели (панель + Caddy)" "Quick panel install (panel + Caddy)")" run_remnawave_full_install_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Установить панель Remnawave" "Install Remnawave panel")" run_panel_install_flow
        ;;
      3)
        run_component_flow_action "$(tr_text "Установить страницу подписок" "Install subscription page")" run_subscription_install_flow
        ;;
      4)
        run_component_flow_action "$(tr_text "Быстрое обновление панели (панель + Caddy)" "Quick panel update (panel + Caddy)")" run_remnawave_full_update_flow
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
  local timer_state=""
  local timer_enabled=""
  local schedule_now=""
  local tg_state=""
  local enc_state=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Remnawave / Backup" "Home / Remnawave / Backup")"
    load_existing_env_defaults
    timer_state="$(systemctl_active_state panel-backup-panel.timer)"
    timer_enabled="$(systemctl_enabled_state panel-backup-panel.timer)"
    schedule_now="$(timer_schedule_for_scope "panel")"
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

    draw_subheader "$(tr_text "Remnawave: backup панели" "Remnawave: panel backup")"
    show_back_hint
    paint "$CLR_TITLE" "$(tr_text "Коротко по состоянию" "Quick state")"
    paint "$CLR_MUTED" "  $(tr_text "Автобэкап:" "Auto-backup:") ${timer_state} / ${timer_enabled}"
    paint "$CLR_MUTED" "  $(tr_text "Расписание:" "Schedule:") $(format_schedule_label "$schedule_now")"
    paint "$CLR_MUTED" "  Telegram: ${tg_state}"
    paint "$CLR_MUTED" "  $(tr_text "Шифрование:" "Encryption:") ${enc_state}"
    print_separator
    menu_group "$(tr_text "Backup" "Backup")" "$CLR_OK"
    menu_option "1" "$(tr_text "Создать backup панели сейчас" "Create panel backup now")"
    menu_group "$(tr_text "Настройки" "Settings")" "$CLR_ACCENT"
    menu_option "2" "$(tr_text "Автобэкап: включить, время, выключить" "Auto-backup: enable, time, disable")"
    menu_option "3" "$(tr_text "Telegram: токен, chat_id, проверка отправки" "Telegram: token, chat_id, delivery check")"
    menu_option "4" "$(tr_text "Шифрование архива" "Archive encryption")"
    menu_group "$(tr_text "Восстановление и проверка" "Restore and checks")" "$CLR_WARN"
    menu_option "5" "$(tr_text "Восстановить панель из backup" "Restore panel from backup")"
    menu_option "6" "$(tr_text "Doctor: проверить backup панели" "Doctor: check panel backup")"
    menu_group "$(tr_text "Дополнительно" "Advanced")" "$CLR_ACCENT"
    menu_option "7" "$(tr_text "Доп. настройки backup" "More backup settings")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "8" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-8]: " "Choice [1-8]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_backup_with_scope "$(tr_text "Резервная копия: только панель" "Backup: panel only")" "all"
        ;;
      2) menu_section_timer_scope "panel" ;;
      3) menu_flow_telegram_settings "panel" ;;
      4) menu_flow_encryption_settings ;;
      5) run_restore_scope_selector "panel" || true ;;
      6) run_doctor_checks || true; wait_for_enter ;;
      7) menu_section_setup "panel" ;;
      8) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_remnawave_components() {
  local choice=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Remnawave" "Home / Remnawave")"
    draw_subheader "$(tr_text "Раздел: Компоненты Remnawave" "Section: Remnawave components")"
    show_back_hint
    menu_group "$(tr_text "Разделы" "Sections")" "$CLR_ACCENT"
    menu_option "1" "$(tr_text "Установка и обновление" "Install and update")"
    menu_option "2" "$(tr_text "Backup и восстановление" "Backup and restore")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")"
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

menu_section_bedolaga_install_update_official() {
  local choice=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Bedolaga / Установка / Official" "Home / Bedolaga / Install / Official")"
    draw_subheader "$(tr_text "Bedolaga: официальный стек" "Bedolaga: official stack")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Установка и раздельное обновление официального стека Bedolaga." "Install and separate update for the official Bedolaga stack.")"
    menu_group "$(tr_text "Установка" "Install")" "$CLR_OK"
    menu_option "1" "$(tr_text "Установить Bedolaga (бот + кабинет + Caddy)" "Install Bedolaga (bot + cabinet + Caddy)")"
    menu_group "$(tr_text "Обновление" "Update")" "$CLR_WARN"
    menu_option "2" "$(tr_text "Обновить весь стек (бот + кабинет)" "Update full stack (bot + cabinet)")"
    menu_hint "$(tr_text "Оба репозитория: git pull, пересборка бота и кабинета. .env и Caddyfile не трогаются." "Both repositories: git pull, bot and cabinet rebuild. .env and Caddyfile are untouched.")"
    menu_option "3" "$(tr_text "Обновить только бот" "Update bot only")"
    menu_hint "$(tr_text "Только репозиторий и контейнеры бота: bot + DB + Redis." "Only bot repository and containers: bot + DB + Redis.")"
    menu_option "4" "$(tr_text "Обновить только кабинет" "Update cabinet only")"
    menu_hint "$(tr_text "Только репозиторий и контейнер кабинета, без пересборки бота." "Only cabinet repository and container, without rebuilding the bot.")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "5" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_component_flow_action "$(tr_text "Установить Bedolaga (бот + кабинет + Caddy)" "Install Bedolaga (bot + cabinet + Caddy)")" run_bedolaga_stack_install_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Обновить весь стек Bedolaga" "Update full Bedolaga stack")" run_bedolaga_stack_update_flow
        ;;
      3)
        run_component_flow_action "$(tr_text "Обновить только бот Bedolaga" "Update Bedolaga bot only")" run_bedolaga_bot_update_flow
        ;;
      4)
        run_component_flow_action "$(tr_text "Обновить только кабинет Bedolaga" "Update Bedolaga cabinet only")" run_bedolaga_cabinet_update_flow
        ;;
      5) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_bedolaga_install_update_fork() {
  local choice=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Bedolaga / Установка / Fork PEDZEO" "Home / Bedolaga / Install / PEDZEO fork")"
    draw_subheader "$(tr_text "Bedolaga: fork PEDZEO" "Bedolaga: PEDZEO fork")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Автоустановка и раздельное безопасное обновление форка PEDZEO." "Auto-install and separate safe update for PEDZEO fork.")"
    menu_group "$(tr_text "Установка" "Install")" "$CLR_OK"
    menu_option "1" "$(tr_text "Автоустановка форка PEDZEO (бот + кабинет + Caddy)" "Auto-install PEDZEO fork (bot + cabinet + Caddy)")"
    menu_group "$(tr_text "Обновление" "Update")" "$CLR_WARN"
    menu_option "2" "$(tr_text "Обновить весь форк PEDZEO (safe)" "Update full PEDZEO fork (safe)")"
    menu_hint "$(tr_text "Бот + кабинет: переключение на PEDZEO origin, git update, пересборка обоих." "Bot + cabinet: switch to PEDZEO origin, git update, rebuild both.")"
    menu_option "3" "$(tr_text "Обновить только бот форка" "Update fork bot only")"
    menu_hint "$(tr_text "Только bot-репозиторий PEDZEO и контейнеры бота." "Only PEDZEO bot repository and bot containers.")"
    menu_option "4" "$(tr_text "Обновить только кабинет форка" "Update fork cabinet only")"
    menu_hint "$(tr_text "Только cabinet-репозиторий PEDZEO и контейнер кабинета." "Only PEDZEO cabinet repository and cabinet container.")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "5" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        run_component_flow_action "$(tr_text "Автоустановка форка PEDZEO (бот + кабинет + Caddy)" "Auto-install PEDZEO fork (bot + cabinet + Caddy)")" run_bedolaga_stack_install_fork_flow
        ;;
      2)
        run_component_flow_action "$(tr_text "Обновить весь форк PEDZEO (safe)" "Update full PEDZEO fork (safe)")" run_bedolaga_stack_update_fork_flow
        ;;
      3)
        run_component_flow_action "$(tr_text "Обновить только бот форка PEDZEO (safe)" "Update PEDZEO fork bot only (safe)")" run_bedolaga_bot_update_fork_flow
        ;;
      4)
        run_component_flow_action "$(tr_text "Обновить только кабинет форка PEDZEO (safe)" "Update PEDZEO fork cabinet only (safe)")" run_bedolaga_cabinet_update_fork_flow
        ;;
      5) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_bedolaga_install_update() {
  local choice=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Bedolaga / Установка" "Home / Bedolaga / Install")"
    draw_subheader "$(tr_text "Bedolaga: установка и обновление" "Bedolaga: install and update")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Выберите ветку: официальный стек Bedolaga или fork PEDZEO." "Choose line: official Bedolaga stack or PEDZEO fork.")"
    menu_group "$(tr_text "Ветка установки" "Install line")" "$CLR_ACCENT"
    menu_option "1" "$(tr_text "Официальный Bedolaga" "Official Bedolaga")"
    menu_option "2" "$(tr_text "Fork PEDZEO" "PEDZEO fork")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_section_bedolaga_install_update_official ;;
      2) menu_section_bedolaga_install_update_fork ;;
      3) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_bedolaga_backup_restore() {
  local choice=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Bedolaga / Backup" "Home / Bedolaga / Backup")"
    draw_subheader "$(tr_text "Bedolaga: backup и восстановление" "Bedolaga: backup and restore")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Локальные backup/restore и отдельный поток миграции на новый VPS." "Local backup/restore and a separate migration flow to a new VPS.")"
    menu_group "$(tr_text "Backup и восстановление" "Backup and restore")" "$CLR_OK"
    menu_option "1" "$(tr_text "Локальный backup/restore" "Local backup/restore")"
    menu_group "$(tr_text "Миграция" "Migration")" "$CLR_WARN"
    menu_option "2" "$(tr_text "Миграция на новый VPS" "Migration to a new VPS")"
    menu_group "$(tr_text "Настройки" "Settings")" "$CLR_ACCENT"
    menu_option "3" "$(tr_text "Настройки backup Bedolaga" "Bedolaga backup settings")"
    menu_option "4" "$(tr_text "Таймер и периодичность Bedolaga" "Bedolaga timer and schedule")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "5" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) menu_section_bedolaga_local_backup_restore ;;
      2) run_bedolaga_migration_wizard || true ;;
      3) menu_section_setup "bedolaga" ;;
      4) menu_section_timer_scope "bedolaga" ;;
      5) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_bedolaga_components() {
  local choice=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Bedolaga" "Home / Bedolaga")"
    draw_subheader "$(tr_text "Раздел: Бот и кабинет Bedolaga" "Section: Bedolaga bot and cabinet")"
    show_back_hint
    menu_group "$(tr_text "Разделы" "Sections")" "$CLR_ACCENT"
    menu_option "1" "$(tr_text "Установка и обновление" "Install and update")"
    menu_option "2" "$(tr_text "Backup и восстановление" "Backup and restore")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "3" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-3]: " "Choice [1-3]: ")"
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
    ui_set_breadcrumb "$(tr_text "Главная / RemnaNode" "Home / RemnaNode")"
    draw_subheader "$(tr_text "Раздел: Компоненты RemnaNode" "Section: RemnaNode components")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Базовые и сетевые инструменты для RemnaNode." "Basic and network tools for RemnaNode.")"
    menu_group "$(tr_text "Быстрый старт" "Quick start")" "$CLR_OK"
    menu_option "1" "$(tr_text "Полная настройка (нода + Caddy + BBR + WARP)" "Full setup (node + Caddy + BBR + WARP)")"
    menu_group "$(tr_text "Нода" "Node")" "$CLR_ACCENT"
    menu_option "2" "$(tr_text "Установить ноду RemnaNode" "Install RemnaNode")"
    menu_option "3" "$(tr_text "Обновить ноду RemnaNode" "Update RemnaNode")"
    menu_group "$(tr_text "Сеть" "Network")" "$CLR_WARN"
    menu_option "4" "$(tr_text "Настроить Caddy self-steal" "Configure Caddy self-steal")"
    menu_option "5" "$(tr_text "Включить BBR" "Enable BBR")"
    menu_option "6" "$(tr_text "Настроить WARP Native (wgcf)" "Configure WARP Native (wgcf)")"
    menu_option "7" "$(tr_text "Включить/выключить IPv6" "Toggle IPv6")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "8" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-8]: " "Choice [1-8]: ")"
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

timer_unit_for_scope() {
  [[ "${1:-panel}" == "bedolaga" ]] && echo "panel-backup-bedolaga.timer" || echo "panel-backup-panel.timer"
}

timer_service_for_scope() {
  [[ "${1:-panel}" == "bedolaga" ]] && echo "panel-backup-bedolaga.service" || echo "panel-backup-panel.service"
}

timer_title_for_scope() {
  [[ "${1:-panel}" == "bedolaga" ]] && tr_text "Bedolaga: автобэкап по расписанию" "Bedolaga: scheduled auto-backup" || tr_text "Панель: автобэкап по расписанию" "Panel: scheduled auto-backup"
}

timer_label_for_scope() {
  [[ "${1:-panel}" == "bedolaga" ]] && tr_text "Автобэкап Bedolaga" "Bedolaga auto-backup" || tr_text "Автобэкап панели" "Panel auto-backup"
}

timer_schedule_for_scope() {
  local scope="${1:-panel}"
  local unit=""
  local current=""

  unit="$(timer_unit_for_scope "$scope")"
  current="$(get_timer_calendar_for_unit "$unit" || true)"
  if [[ -z "$current" ]]; then
    if [[ "$scope" == "bedolaga" ]]; then
      current="${BACKUP_ON_CALENDAR_BEDOLAGA:-${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}}"
    else
      current="${BACKUP_ON_CALENDAR_PANEL:-${BACKUP_ON_CALENDAR:-*-*-* 03:40:00 UTC}}"
    fi
  fi
  printf '%s' "$current"
}

timer_next_run_label() {
  local unit="$1"
  local raw=""

  raw="$($SUDO systemctl show "$unit" -p NextElapseUSecRealtime --value 2>/dev/null || true)"
  if [[ -z "$raw" || "$raw" == "n/a" ]]; then
    printf '%s' "n/a"
  else
    printf '%s' "$raw"
  fi
}

ensure_backup_runtime_installed() {
  local scope="${1:-panel}"
  local service_unit=""
  local need_install=0

  service_unit="$(timer_service_for_scope "$scope")"
  [[ -x /usr/local/bin/panel-backup.sh ]] || need_install=1
  if ! $SUDO systemctl cat "$service_unit" >/dev/null 2>&1; then
    need_install=1
  fi

  if (( need_install == 0 )); then
    return 0
  fi

  paint "$CLR_MUTED" "$(tr_text "Файлы backup не установлены или устарели, обновляю перед включением таймера..." "Backup files are missing or outdated, updating before enabling timer...")"
  install_files
}

save_timer_schedule_for_scope() {
  local scope="${1:-panel}"
  local schedule="$2"
  local timer_unit=""

  if [[ "$scope" == "bedolaga" ]]; then
    BACKUP_ON_CALENDAR_BEDOLAGA="$schedule"
  else
    BACKUP_ON_CALENDAR_PANEL="$schedule"
  fi
  BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR_PANEL:-${BACKUP_ON_CALENDAR_BEDOLAGA:-$schedule}}"
  timer_unit="$(timer_unit_for_scope "$scope")"
  write_env
  write_timer_unit
  $SUDO systemctl daemon-reload
  if $SUDO systemctl is-enabled --quiet "$timer_unit" 2>/dev/null; then
    $SUDO systemctl restart "$timer_unit" >/dev/null 2>&1 || true
  fi
}

enable_timer_for_scope() {
  local scope="${1:-panel}"
  local timer_unit=""

  timer_unit="$(timer_unit_for_scope "$scope")"
  if ! ensure_backup_runtime_installed "$scope"; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось установить файлы backup." "Failed to install backup files.")"
    return 1
  fi
  write_env
  write_timer_unit
  $SUDO systemctl daemon-reload

  if [[ "$scope" == "bedolaga" ]]; then
    if ! has_bedolaga_project; then
      paint "$CLR_WARN" "$(tr_text "Bedolaga не найден. Сначала укажите пути бота и кабинета в настройках." "Bedolaga was not found. Set bot and cabinet paths in settings first.")"
      return 1
    fi
  else
    if ! has_panel_project; then
      paint "$CLR_WARN" "$(tr_text "Панель Remnawave не найдена. Сначала укажите путь панели в настройках." "Remnawave panel was not found. Set panel path in settings first.")"
      return 1
    fi
  fi

  if $SUDO systemctl enable --now "$timer_unit"; then
    paint "$CLR_OK" "$(tr_text "Автобэкап включен." "Auto-backup enabled.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось включить таймер systemd." "Failed to enable the systemd timer.")"
  return 1
}

SELECTED_SCHEDULE_VALUE=""
choose_timer_schedule_value() {
  local current_schedule="$1"
  local schedule_choice=""
  local custom=""

  SELECTED_SCHEDULE_VALUE=""
  while true; do
    paint "$CLR_MUTED" "$(tr_text "Выберите понятный пресет или свой systemd OnCalendar." "Choose a clear preset or custom systemd OnCalendar.")"
    menu_option "1" "$(tr_text "Каждый день в 03:40 UTC" "Every day at 03:40 UTC")"
    menu_option "2" "$(tr_text "Каждые 12 часов" "Every 12 hours")"
    menu_option "3" "$(tr_text "Каждые 6 часов" "Every 6 hours")"
    menu_option "4" "$(tr_text "Каждый час" "Every hour")"
    menu_option "5" "$(tr_text "Свое время OnCalendar" "Custom OnCalendar")"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice schedule_choice "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")"
    if is_back_command "$schedule_choice"; then
      return 1
    fi
    case "$schedule_choice" in
      1) custom="*-*-* 03:40:00 UTC" ;;
      2) custom="*-*-* 00,12:00:00 UTC" ;;
      3) custom="*-*-* 00,06,12,18:00:00 UTC" ;;
      4) custom="hourly" ;;
      5)
        custom="$(ask_value "$(tr_text "Введите OnCalendar" "Enter OnCalendar")" "$current_schedule")"
        [[ "$custom" == "__PBM_BACK__" ]] && continue
        ;;
      6) return 1 ;;
      *)
        paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
        wait_for_enter
        continue
        ;;
    esac
    [[ -n "$custom" ]] || continue
    if ! validate_oncalendar_or_warn "$custom"; then
      wait_for_enter
      continue
    fi
    SELECTED_SCHEDULE_VALUE="$custom"
    return 0
  done
}

menu_section_timer_scope() {
  local scope="${1:-panel}"
  local choice=""
  local current_schedule=""
  local timer_unit=""
  local timer_title=""
  local timer_label=""
  local timer_state=""
  local timer_enabled=""
  local next_run=""

  timer_unit="$(timer_unit_for_scope "$scope")"
  timer_title="$(timer_title_for_scope "$scope")"
  timer_label="$(timer_label_for_scope "$scope")"

  while true; do
    if [[ "$scope" == "bedolaga" ]]; then
      ui_set_breadcrumb "$(tr_text "Главная / Bedolaga / Backup / Таймер" "Home / Bedolaga / Backup / Timer")"
    else
      ui_set_breadcrumb "$(tr_text "Главная / Remnawave / Backup / Таймер" "Home / Remnawave / Backup / Timer")"
    fi
    load_existing_env_defaults
    current_schedule="$(timer_schedule_for_scope "$scope")"
    timer_state="$(systemctl_active_state "$timer_unit")"
    timer_enabled="$(systemctl_enabled_state "$timer_unit")"
    next_run="$(timer_next_run_label "$timer_unit")"

    draw_subheader "$timer_title"
    show_back_hint
    paint "$CLR_TITLE" "$(tr_text "Текущее состояние" "Current state")"
    paint "$CLR_MUTED" "  ${timer_label}: ${timer_state} / ${timer_enabled}"
    paint "$CLR_MUTED" "  $(tr_text "Расписание:" "Schedule:") $(format_schedule_label "$current_schedule")"
    paint "$CLR_MUTED" "  $(tr_text "Следующий запуск:" "Next run:") ${next_run}"
    print_separator
    menu_group "$(tr_text "Автобэкап" "Auto-backup")" "$CLR_OK"
    menu_option "1" "$(tr_text "Включить автобэкап по этому расписанию" "Enable auto-backup with this schedule")"
    menu_option "2" "$(tr_text "Изменить время/периодичность" "Change time/frequency")"
    menu_option "3" "$(tr_text "Выключить автобэкап" "Disable auto-backup")"
    menu_group "$(tr_text "Ручной запуск" "Manual run")" "$CLR_ACCENT"
    menu_option "4" "$(tr_text "Запустить backup сейчас" "Run backup now")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "5" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-5]: " "Choice [1-5]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1)
        enable_timer_for_scope "$scope" || true
        wait_for_enter
        ;;
      2)
        draw_subheader "$timer_title"
        paint "$CLR_MUTED" "$(tr_text "Сейчас:" "Now:") $(format_schedule_label "$current_schedule")"
        if choose_timer_schedule_value "$current_schedule"; then
          save_timer_schedule_for_scope "$scope" "$SELECTED_SCHEDULE_VALUE"
          paint "$CLR_OK" "$(tr_text "Расписание сохранено." "Schedule saved.")"
          if ask_yes_no "$(tr_text "Включить автобэкап с этим расписанием сейчас?" "Enable auto-backup with this schedule now?")" "y"; then
            enable_timer_for_scope "$scope" || true
          fi
          wait_for_enter
        fi
        ;;
      3)
        $SUDO systemctl disable --now "$timer_unit" >/dev/null 2>&1 || true
        paint "$CLR_OK" "$(tr_text "Автобэкап выключен." "Auto-backup disabled.")"
        wait_for_enter
        ;;
      4)
        if [[ "$scope" == "bedolaga" ]]; then
          run_backup_with_scope "$(tr_text "Резервная копия: полный Bedolaga" "Backup: full Bedolaga")" "bedolaga"
        else
          run_backup_with_scope "$(tr_text "Резервная копия: только панель" "Backup: panel only")" "all"
        fi
        ;;
      5) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}

menu_section_status() {
  local choice=""
  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Статус" "Home / Status")"
    draw_subheader "$(tr_text "Раздел: Статус и диагностика" "Section: Status and diagnostics")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Проверка состояния скриптов, таймера и последних архивов." "Check scripts, timer and latest backup details.")"
    menu_group "$(tr_text "Диагностика" "Diagnostics")" "$CLR_WARN"
    menu_option "1" "$(tr_text "Показать полный статус" "Show full status")"
    menu_option "2" "$(tr_text "Doctor: быстрая проверка настроек" "Doctor: quick configuration check")"
    menu_group "$(tr_text "Сервер" "Server")" "$CLR_OK"
    menu_option "3" "$(tr_text "Проверка IP, сайтов и скорости" "IP, website and speed checks")"
    menu_group "$(tr_text "Диск" "Disk")" "$CLR_ACCENT"
    menu_option "4" "$(tr_text "Анализ использования диска" "Analyze disk usage")"
    menu_option "5" "$(tr_text "Безопасная очистка диска" "Safe disk cleanup")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) show_status; wait_for_enter ;;
      2) run_doctor_checks || true; wait_for_enter ;;
      3) run_server_checks || true; wait_for_enter ;;
      4) show_disk_usage_top; wait_for_enter ;;
      5)
        show_safe_cleanup_preview
        if ask_yes_no "$(tr_text "Запустить безопасную очистку сейчас?" "Run safe cleanup now?")" "n"; then
          run_safe_cleanup
        fi
        wait_for_enter
        ;;
      6) break ;;
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
    ui_clear_breadcrumb
    draw_header "$(tr_text "Panel Backup Manager" "Panel Backup Manager")"
    menu_group "$(tr_text "Основные разделы" "Main sections")" "$CLR_ACCENT"
    menu_card_option "1" "Bedolaga" "$(tr_text "Бот, кабинет, backup, восстановление и миграция на новый VPS." "Bot, cabinet, backup, restore and migration to a new VPS.")" "$CLR_OK"
    menu_card_option "2" "Remnawave" "$(tr_text "Панель, страница подписок, Caddy, backup и restore панели." "Panel, subscription page, Caddy, backup and panel restore.")" "$CLR_ACCENT"
    menu_card_option "3" "RemnaNode" "$(tr_text "Нода, Caddy self-steal, BBR, WARP и IPv6." "Node, Caddy self-steal, BBR, WARP and IPv6.")" "$CLR_WARN"
    menu_card_option "4" "$(tr_text "Статус и сервер" "Status and server")" "$(tr_text "Полный статус, doctor, проверка IP/сайтов/скорости, диск и очистка." "Full status, doctor, IP/site/speed checks, disk and cleanup.")" "$CLR_MUTED"
    menu_card_option "5" "Reshala toolbox" "$(tr_text "Отдельная страница внешнего набора функций Reshala." "Separate page for the external Reshala feature set.")" "$CLR_TITLE"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "0" "$(tr_text "Выход" "Exit")" "$CLR_DANGER"
    if [[ -n "$(ui_last_action_label)" ]]; then
      print_separator
      paint "$CLR_MUTED" "  $(tr_text "Последнее действие" "Last action"): $(ui_last_action_label)"
    fi
    menu_quick_hint "$(tr_text "Быстро: s = статус, d = doctor, c = сервер/сеть, n = backup сейчас." "Quick: s = status, d = doctor, c = server/network, n = backup now.")"
    read_menu_choice action "$(tr_text "Выбор [1-5, s/d/c/n, 0 выход]: " "Choice [1-5, s/d/c/n, 0 exit]: ")"
    if is_back_command "$action"; then
      echo "$(tr_text "Выход." "Cancelled.")"
      break
    fi

    case "$action" in
      1) ui_set_breadcrumb "$(tr_text "Главная / Bedolaga" "Home / Bedolaga")"; menu_section_bedolaga_components ;;
      2) ui_set_breadcrumb "$(tr_text "Главная / Remnawave" "Home / Remnawave")"; menu_section_remnawave_components ;;
      3) ui_set_breadcrumb "$(tr_text "Главная / RemnaNode" "Home / RemnaNode")"; menu_section_remnanode_components ;;
      4) ui_set_breadcrumb "$(tr_text "Главная / Статус" "Home / Status")"; menu_section_status ;;
      5) ui_set_breadcrumb "$(tr_text "Главная / Reshala" "Home / Reshala")"; menu_section_reshala_integration ;;
      s|S|status|Status)
        ui_set_breadcrumb "$(tr_text "Главная / Быстрый статус" "Home / Quick status")"
        show_status
        wait_for_enter
        ;;
      d|D|doctor|Doctor)
        ui_set_breadcrumb "$(tr_text "Главная / Doctor" "Home / Doctor")"
        run_doctor_checks || true
        wait_for_enter
        ;;
      c|C|check|Check|server|Server)
        ui_set_breadcrumb "$(tr_text "Главная / Проверка сервера" "Home / Server check")"
        run_server_checks || true
        wait_for_enter
        ;;
      n|N|now|Now|backup|Backup)
        run_quick_backup_menu
        ;;
      0)
        echo "$(tr_text "Выход." "Cancelled.")"
        break
        ;;
      *)
        paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"
        wait_for_enter
        ;;
    esac
  done
}
