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
    menu_option "3" "$(tr_text "Перенести на новый VPS по SSH (автоматически)" "Migrate to a new VPS over SSH (automatic)")"
    menu_option "4" "$(tr_text "Назад" "Back")"
    print_separator
    read -r -p "$(tr_text "Выбор [1-4]: " "Choice [1-4]: ")" choice
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
      3)
        if run_bedolaga_remote_migration_flow; then
          return 0
        fi
        ;;
      4) return 1 ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
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
  local restore_dry_run=1
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

  latest_archive="$(ls -1t /var/backups/panel/pb-*.tar.gz /var/backups/panel/pb-*.tar.gz.gpg /var/backups/panel/panel-backup-*.tar.gz /var/backups/panel/panel-backup-*.tar.gz.gpg 2>/dev/null | head -n1 || true)"
  archive_path="${BACKUP_FILE:-$latest_archive}"

  draw_subheader "$(tr_text "Миграция Bedolaga на новый VPS (SSH)" "Bedolaga migration to a new VPS (SSH)")"
  paint "$CLR_MUTED" "$(tr_text "Сценарий: копирование архива на удалённый сервер и запуск panel-restore.sh." "Flow: copy archive to remote server and run panel-restore.sh.")"
  paint "$CLR_MUTED" "$(tr_text "Можно включить автоподготовку пустого VPS: Docker + panel-restore.sh + подготовка контейнеров." "You can enable auto-prepare for an empty VPS: Docker + panel-restore.sh + container bootstrap.")"

  archive_path="$(ask_value "$(tr_text "Путь к локальному архиву для переноса (Enter = последний)" "Local backup archive path for migration (Enter = latest)")" "$archive_path")"
  [[ "$archive_path" == "__PBM_BACK__" ]] && return 1

  draw_subheader "$(tr_text "Выбор состава восстановления на новом VPS" "Select restore scope on the new VPS")"
  menu_option "1" "$(tr_text "Бот + кабинет (без DB/Redis, рекомендовано для старта)" "Bot + cabinet (without DB/Redis, recommended to start)")"
  menu_option "2" "$(tr_text "Полный Bedolaga (DB + Redis + бот + кабинет)" "Full Bedolaga (DB + Redis + bot + cabinet)")"
  print_separator
  read -r -p "$(tr_text "Выбор [1-2]: " "Choice [1-2]: ")" restore_scope_choice
  if is_back_command "$restore_scope_choice"; then
    return 1
  fi
  case "$restore_scope_choice" in
    1) restore_only="bedolaga-bot,bedolaga-cabinet" ;;
    2) restore_only="bedolaga" ;;
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
      bedolaga) fresh_backup_scope="bedolaga" ;;
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
  ask_yes_no "$(tr_text "Запустить удалённое восстановление в тестовом режиме (--dry-run)?" "Run remote restore in test mode (--dry-run)?")" "y" || confirm_rc=$?
  case "$confirm_rc" in
    0) restore_dry_run=1 ;;
    1) restore_dry_run=0 ;;
    2) return 1 ;;
  esac

  if (( restore_dry_run == 1 )); then
    restore_no_restart=1
  else
    confirm_rc=0
    ask_yes_no "$(tr_text "Отключить автоперезапуск сервисов на новом VPS (--no-restart)?" "Disable service auto-restart on the new VPS (--no-restart)?")" "n" || confirm_rc=$?
    case "$confirm_rc" in
      0) restore_no_restart=1 ;;
      1) restore_no_restart=0 ;;
      2) return 1 ;;
    esac
  fi

  ssh_host="$(ask_value "$(tr_text "IP/домен нового VPS" "New VPS IP/domain")" "$ssh_host")"
  [[ "$ssh_host" == "__PBM_BACK__" ]] && return 1
  [[ -n "$ssh_host" ]] || {
    paint "$CLR_DANGER" "$(tr_text "Хост не задан." "Host is not set.")"
    wait_for_enter
    return 1
  }

  ssh_user="$(ask_value "$(tr_text "SSH пользователь" "SSH user")" "$ssh_user")"
  [[ "$ssh_user" == "__PBM_BACK__" ]] && return 1
  [[ -n "$ssh_user" ]] || ssh_user="root"

  ssh_port="$(ask_value "$(tr_text "SSH порт" "SSH port")" "$ssh_port")"
  [[ "$ssh_port" == "__PBM_BACK__" ]] && return 1
  [[ "$ssh_port" =~ ^[0-9]+$ ]] || {
    paint "$CLR_DANGER" "$(tr_text "SSH порт должен быть числом." "SSH port must be numeric.")"
    wait_for_enter
    return 1
  }

  ssh_password="$(ask_secret_value "$(tr_text "SSH пароль (опционально, Enter = использовать ключи)" "SSH password (optional, Enter = use SSH keys)")" "")"
  [[ "$ssh_password" == "__PBM_BACK__" ]] && return 1

  remote_backup_dir="$(ask_value "$(tr_text "Папка архива на новом VPS" "Remote archive directory on new VPS")" "$remote_backup_dir")"
  [[ "$remote_backup_dir" == "__PBM_BACK__" ]] && return 1
  [[ -n "$remote_backup_dir" ]] || remote_backup_dir="/var/backups/panel"
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
    paint "$CLR_DANGER" "$(tr_text "Для входа по паролю нужен sshpass." "sshpass is required for password-based login.")"
    wait_for_enter
    return 1
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
  paint "$CLR_MUTED" "  $(tr_text "Автоподготовка VPS:" "VPS auto-prepare:") $([[ "$auto_prepare_remote" == "1" ]] && tr_text "включена" "enabled" || tr_text "выключена" "disabled")"
  if (( include_caddy == 1 )); then
    paint "$CLR_MUTED" "  $(tr_text "Caddy перенос:" "Caddy migration:") ${detected_caddy_dir} -> ${remote_caddy_dir}"
  else
    paint "$CLR_MUTED" "  $(tr_text "Caddy перенос:" "Caddy migration:") $(tr_text "пропущен" "skipped")"
  fi
  paint "$CLR_MUTED" "  $(tr_text "Режим:" "Mode:") $([[ "$restore_dry_run" == "1" ]] && tr_text "тестовый (--dry-run)" "test (--dry-run)" || tr_text "боевой" "real")"
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

    if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
      paint "$CLR_DANGER" "$(tr_text "Локально не найден /usr/local/bin/panel-restore.sh для копирования на новый VPS." "Local /usr/local/bin/panel-restore.sh not found for upload to new VPS.")"
      wait_for_enter
      return 1
    fi
    paint "$CLR_ACCENT" "$(tr_text "Копирую runtime restore-скрипты на новый VPS..." "Uploading runtime restore scripts to the new VPS...")"
    if ! "${scp_cmd[@]}" /usr/local/bin/panel-restore.sh "${ssh_user}@${ssh_host}:/usr/local/bin/panel-restore.sh"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось скопировать panel-restore.sh на новый VPS." "Failed to copy panel-restore.sh to new VPS.")"
      wait_for_enter
      return 1
    fi
    if [[ -x /usr/local/bin/panel-backup.sh ]]; then
      "${scp_cmd[@]}" /usr/local/bin/panel-backup.sh "${ssh_user}@${ssh_host}:/usr/local/bin/panel-backup.sh" >/dev/null 2>&1 || true
    fi
    if ! "${ssh_cmd[@]}" "chmod 755 /usr/local/bin/panel-restore.sh /usr/local/bin/panel-backup.sh >/dev/null 2>&1 || true"; then
      paint "$CLR_WARN" "$(tr_text "Не удалось применить chmod для runtime-скриптов на новом VPS." "Failed to chmod runtime scripts on new VPS.")"
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
  if (( restore_dry_run == 1 )); then
    remote_cmd="${remote_cmd} --dry-run"
  fi
  if (( restore_no_restart == 1 )); then
    remote_cmd="${remote_cmd} --no-restart"
  fi
  if (( is_encrypted_archive == 1 )); then
    remote_cmd="BACKUP_PASSWORD=$(printf '%q' "$restore_password") ${remote_cmd}"
  fi

  if (( restore_dry_run == 0 && auto_prepare_remote == 1 )) && [[ "$restore_only" == "bedolaga" ]]; then
    paint "$CLR_ACCENT" "$(tr_text "Пустой VPS: предварительно разворачиваю bot+cabinet и поднимаю контейнеры перед полным restore..." "Empty VPS: pre-seeding bot+cabinet and starting containers before full restore...")"
    preseed_cmd="/usr/local/bin/panel-restore.sh --from $(printf '%q' "$remote_archive") --only bedolaga-bot --only bedolaga-cabinet --no-restart"
    if (( is_encrypted_archive == 1 )); then
      preseed_cmd="BACKUP_PASSWORD=$(printf '%q' "$restore_password") ${preseed_cmd}"
    fi
    if ! "${ssh_cmd[@]}" "$preseed_cmd"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось выполнить предварительное восстановление bot+cabinet на новом VPS." "Failed to run bot+cabinet pre-restore on the new VPS.")"
      wait_for_enter
      return 1
    fi
    if ! "${ssh_cmd[@]}" "set -e; cd /root/remnawave-bedolaga-telegram-bot && docker compose up -d; if [ -d /root/cabinet-frontend ]; then cd /root/cabinet-frontend && docker compose up -d; fi"; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось поднять контейнеры Bedolaga на новом VPS." "Failed to start Bedolaga containers on the new VPS.")"
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

  if (( include_caddy == 1 && restore_dry_run == 0 )); then
    paint "$CLR_ACCENT" "$(tr_text "Поднимаю Caddy на новом VPS..." "Starting Caddy on the new VPS...")"
    caddy_up_cmd="set -e; cd $(printf '%q' "$remote_caddy_dir"); cfile=''; if [ -f docker-compose.yml ]; then cfile='docker-compose.yml'; elif [ -f docker-compose.caddy.yml ]; then cfile='docker-compose.caddy.yml'; elif [ -f compose.yaml ]; then cfile='compose.yaml'; elif [ -f compose.yml ]; then cfile='compose.yml'; fi; if [ -n \"\$cfile\" ]; then docker compose -f \"\$cfile\" up -d; else echo 'compose file not found in caddy dir'; exit 1; fi"
    if ! "${ssh_cmd[@]}" "$caddy_up_cmd"; then
      paint "$CLR_WARN" "$(tr_text "Не удалось запустить Caddy на новом VPS." "Failed to start Caddy on the new VPS.")"
    fi
  fi

  if (( restore_dry_run == 0 )); then
    paint "$CLR_ACCENT" "$(tr_text "Проверяю состояние сервисов и последние логи на новом VPS..." "Checking service state and recent logs on the new VPS...")"
    postcheck_cmd='
set +e
echo "============================================================"
echo "  Post-check: Bedolaga stack"
echo "============================================================"
for c in remnawave_bot_db remnawave_bot_redis remnawave_bot cabinet_frontend remnawave-caddy remnawave_caddy caddy; do
  st="$(docker inspect -f "{{.State.Status}}" "$c" 2>/dev/null || echo "not-found")"
  printf "  %-20s %s\n" "$c:" "$st"
done
echo "------------------------------------------------------------"
echo "docker ps (filtered)"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "NAMES|remnawave_bot|cabinet_frontend" || true
echo "------------------------------------------------------------"
echo "logs: remnawave_bot (tail 40)"
docker logs --tail 40 remnawave_bot 2>&1 || true
echo "------------------------------------------------------------"
echo "logs: cabinet_frontend (tail 40)"
docker logs --tail 40 cabinet_frontend 2>&1 || true
echo "------------------------------------------------------------"
echo "logs: remnawave_bot_db (tail 30)"
docker logs --tail 30 remnawave_bot_db 2>&1 || true
echo "------------------------------------------------------------"
echo "logs: remnawave_bot_redis (tail 30)"
docker logs --tail 30 remnawave_bot_redis 2>&1 || true
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
      paint "$CLR_WARN" "$(tr_text "Постпроверка вернула ошибку. Проверьте SSH/логи вручную." "Post-check returned an error. Verify SSH/logs manually.")"
    fi
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
