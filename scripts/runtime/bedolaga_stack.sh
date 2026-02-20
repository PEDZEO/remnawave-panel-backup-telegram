#!/usr/bin/env bash
# Bedolaga bot + cabinet + caddy installation/update flows.

BEDOLAGA_BOT_REPO_DEFAULT="https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git"
BEDOLAGA_CABINET_REPO_DEFAULT="https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git"
BEDOLAGA_SHARED_NETWORK="bedolaga-network"
CADDY_MODE=""
CADDY_CONTAINER_NAME=""
CADDY_FILE_PATH=""

ensure_git_available() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi
  if install_package "git" >/dev/null 2>&1; then
    command -v git >/dev/null 2>&1
    return $?
  fi
  paint "$CLR_DANGER" "$(tr_text "Не удалось установить git." "Failed to install git.")"
  return 1
}

bedolaga_upsert_env_value() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  local tmp_file=""

  tmp_file="$(mktemp "${TMP_DIR}/bedolaga-env.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { done=0 }
    $0 ~ "^" key "=" {
      print key "=" value
      done=1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' "$file_path" > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

bedolaga_clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"

  if [[ -d "${target_dir}/.git" ]]; then
    paint "$CLR_ACCENT" "$(tr_text "Обновляю репозиторий" "Updating repository"): ${target_dir}"
    if ! git -C "$target_dir" fetch --all --prune; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось получить обновления Git." "Failed to fetch Git updates.")"
      return 1
    fi
    if ! git -C "$target_dir" pull --ff-only; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось обновить репозиторий (pull --ff-only)." "Failed to update repository (pull --ff-only).")"
      return 1
    fi
    return 0
  fi

  if [[ -d "$target_dir" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Папка уже существует, но это не git-репозиторий:" "Directory exists but is not a git repository:") ${target_dir}"
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Клонирую репозиторий" "Cloning repository"): ${repo_url}"
  git clone "$repo_url" "$target_dir"
}

bedolaga_configure_bot_env() {
  local bot_dir="$1"
  local bot_token="$2"
  local admin_ids="$3"
  local hooks_domain="$4"
  local cabinet_domain="$5"
  local remnawave_api_url="$6"
  local remnawave_api_key="$7"
  local bot_username="$8"
  local postgres_db="$9"
  local postgres_user="${10}"
  local postgres_password="${11}"
  local env_file="${bot_dir}/.env"
  local webhook_secret=""
  local web_api_token=""
  local cabinet_jwt_secret=""

  if [[ ! -f "$env_file" ]]; then
    if [[ -f "${bot_dir}/.env.example" ]]; then
      cp "${bot_dir}/.env.example" "$env_file"
    else
      paint "$CLR_DANGER" "$(tr_text "Не найден .env.example в репозитории бота." "Missing .env.example in bot repository.")"
      return 1
    fi
  fi

  webhook_secret="$(generate_hex 32)"
  web_api_token="$(generate_hex 32)"
  cabinet_jwt_secret="$(generate_hex 32)"

  bedolaga_upsert_env_value "$env_file" "BOT_TOKEN" "$bot_token"
  bedolaga_upsert_env_value "$env_file" "ADMIN_IDS" "$admin_ids"
  bedolaga_upsert_env_value "$env_file" "BOT_RUN_MODE" "webhook"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_URL" "https://${hooks_domain}"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_PATH" "/webhook"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_SECRET_TOKEN" "$webhook_secret"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_MAX_QUEUE_SIZE" "1024"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_WORKERS" "4"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_ENQUEUE_TIMEOUT" "0.1"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_WORKER_SHUTDOWN_TIMEOUT" "30.0"
  bedolaga_upsert_env_value "$env_file" "WEB_API_ENABLED" "true"
  bedolaga_upsert_env_value "$env_file" "WEB_API_HOST" "0.0.0.0"
  bedolaga_upsert_env_value "$env_file" "WEB_API_PORT" "8080"
  bedolaga_upsert_env_value "$env_file" "WEB_API_DEFAULT_TOKEN" "$web_api_token"
  bedolaga_upsert_env_value "$env_file" "WEB_API_ALLOWED_ORIGINS" "https://${cabinet_domain}"
  bedolaga_upsert_env_value "$env_file" "MENU_LAYOUT_ENABLED" "true"
  bedolaga_upsert_env_value "$env_file" "MAIN_MENU_MODE" "text"
  bedolaga_upsert_env_value "$env_file" "CONNECT_BUTTON_MODE" "miniapp_subscription"
  bedolaga_upsert_env_value "$env_file" "ENABLE_LOGO_MODE" "true"
  bedolaga_upsert_env_value "$env_file" "DEFAULT_LANGUAGE" "ru"
  bedolaga_upsert_env_value "$env_file" "AVAILABLE_LANGUAGES" "ru,en"
  bedolaga_upsert_env_value "$env_file" "LANGUAGE_SELECTION_ENABLED" "true"
  bedolaga_upsert_env_value "$env_file" "BACKUP_AUTO_ENABLED" "true"
  bedolaga_upsert_env_value "$env_file" "BACKUP_INTERVAL_HOURS" "24"
  bedolaga_upsert_env_value "$env_file" "BACKUP_TIME" "03:00"
  bedolaga_upsert_env_value "$env_file" "BACKUP_MAX_KEEP" "7"
  bedolaga_upsert_env_value "$env_file" "BACKUP_COMPRESSION" "true"
  bedolaga_upsert_env_value "$env_file" "BACKUP_INCLUDE_LOGS" "false"
  bedolaga_upsert_env_value "$env_file" "BACKUP_LOCATION" "/app/data/backups"
  bedolaga_upsert_env_value "$env_file" "CABINET_ENABLED" "true"
  bedolaga_upsert_env_value "$env_file" "CABINET_URL" "https://${cabinet_domain}"
  bedolaga_upsert_env_value "$env_file" "CABINET_JWT_SECRET" "$cabinet_jwt_secret"
  bedolaga_upsert_env_value "$env_file" "CABINET_ALLOWED_ORIGINS" "https://${cabinet_domain}"
  bedolaga_upsert_env_value "$env_file" "REMNAWAVE_API_URL" "$remnawave_api_url"
  bedolaga_upsert_env_value "$env_file" "REMNAWAVE_API_KEY" "$remnawave_api_key"
  bedolaga_upsert_env_value "$env_file" "POSTGRES_DB" "$postgres_db"
  bedolaga_upsert_env_value "$env_file" "POSTGRES_USER" "$postgres_user"
  bedolaga_upsert_env_value "$env_file" "POSTGRES_PASSWORD" "$postgres_password"
  if [[ -n "$bot_username" ]]; then
    bedolaga_upsert_env_value "$env_file" "BOT_USERNAME" "$bot_username"
  fi

  return 0
}

bedolaga_prepare_bot_dirs() {
  local bot_dir="$1"
  mkdir -p "${bot_dir}/logs" "${bot_dir}/data" "${bot_dir}/data/backups" "${bot_dir}/data/referral_qr"
  chmod -R 755 "${bot_dir}/logs" "${bot_dir}/data"
}

bedolaga_upsert_if_not_empty() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  [[ -n "$value" ]] || return 0
  bedolaga_upsert_env_value "$file_path" "$key" "$value"
}

bedolaga_read_env_value() {
  local file_path="$1"
  local key="$2"
  [[ -f "$file_path" ]] || return 0
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file_path"
}

bedolaga_upsert_env_default() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  if grep -q "^${key}=" "$file_path" 2>/dev/null; then
    return 0
  fi
  bedolaga_upsert_env_value "$file_path" "$key" "$value"
}

bedolaga_ensure_env_file_from_example() {
  local repo_dir="$1"
  local env_file="${repo_dir}/.env"

  if [[ -f "$env_file" ]]; then
    return 0
  fi
  if [[ -f "${repo_dir}/.env.example" ]]; then
    cp "${repo_dir}/.env.example" "$env_file"
    return 0
  fi
  return 1
}

bedolaga_sync_bot_env_defaults() {
  local bot_dir="$1"
  local hooks_domain="$2"
  local cabinet_domain="$3"
  local bot_username="${4:-}"
  local env_file="${bot_dir}/.env"
  local webhook_secret=""
  local web_api_token=""
  local cabinet_jwt_secret=""

  if ! bedolaga_ensure_env_file_from_example "$bot_dir"; then
    paint "$CLR_DANGER" "$(tr_text "Не найден .env.example в репозитории бота." "Missing .env.example in bot repository.")"
    return 1
  fi

  webhook_secret="$(bedolaga_read_env_value "$env_file" "WEBHOOK_SECRET_TOKEN")"
  web_api_token="$(bedolaga_read_env_value "$env_file" "WEB_API_DEFAULT_TOKEN")"
  cabinet_jwt_secret="$(bedolaga_read_env_value "$env_file" "CABINET_JWT_SECRET")"
  [[ -n "$webhook_secret" ]] || webhook_secret="$(generate_hex 32)"
  [[ -n "$web_api_token" ]] || web_api_token="$(generate_hex 32)"
  [[ -n "$cabinet_jwt_secret" ]] || cabinet_jwt_secret="$(generate_hex 32)"

  bedolaga_upsert_env_default "$env_file" "BOT_RUN_MODE" "webhook"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_URL" "https://${hooks_domain}"
  bedolaga_upsert_env_default "$env_file" "WEBHOOK_PATH" "/webhook"
  bedolaga_upsert_env_value "$env_file" "WEBHOOK_SECRET_TOKEN" "$webhook_secret"
  bedolaga_upsert_env_default "$env_file" "WEBHOOK_MAX_QUEUE_SIZE" "1024"
  bedolaga_upsert_env_default "$env_file" "WEBHOOK_WORKERS" "4"
  bedolaga_upsert_env_default "$env_file" "WEBHOOK_ENQUEUE_TIMEOUT" "0.1"
  bedolaga_upsert_env_default "$env_file" "WEBHOOK_WORKER_SHUTDOWN_TIMEOUT" "30.0"
  bedolaga_upsert_env_default "$env_file" "WEB_API_ENABLED" "true"
  bedolaga_upsert_env_default "$env_file" "WEB_API_HOST" "0.0.0.0"
  bedolaga_upsert_env_default "$env_file" "WEB_API_PORT" "8080"
  bedolaga_upsert_env_value "$env_file" "WEB_API_DEFAULT_TOKEN" "$web_api_token"
  bedolaga_upsert_env_value "$env_file" "WEB_API_ALLOWED_ORIGINS" "https://${cabinet_domain}"
  bedolaga_upsert_env_default "$env_file" "MENU_LAYOUT_ENABLED" "true"
  bedolaga_upsert_env_default "$env_file" "MAIN_MENU_MODE" "text"
  bedolaga_upsert_env_default "$env_file" "CONNECT_BUTTON_MODE" "miniapp_subscription"
  bedolaga_upsert_env_default "$env_file" "ENABLE_LOGO_MODE" "true"
  bedolaga_upsert_env_default "$env_file" "DEFAULT_LANGUAGE" "ru"
  bedolaga_upsert_env_default "$env_file" "AVAILABLE_LANGUAGES" "ru,en"
  bedolaga_upsert_env_default "$env_file" "LANGUAGE_SELECTION_ENABLED" "true"
  bedolaga_upsert_env_default "$env_file" "BACKUP_AUTO_ENABLED" "true"
  bedolaga_upsert_env_default "$env_file" "BACKUP_INTERVAL_HOURS" "24"
  bedolaga_upsert_env_default "$env_file" "BACKUP_TIME" "03:00"
  bedolaga_upsert_env_default "$env_file" "BACKUP_MAX_KEEP" "7"
  bedolaga_upsert_env_default "$env_file" "BACKUP_COMPRESSION" "true"
  bedolaga_upsert_env_default "$env_file" "BACKUP_INCLUDE_LOGS" "false"
  bedolaga_upsert_env_default "$env_file" "BACKUP_LOCATION" "/app/data/backups"
  bedolaga_upsert_env_default "$env_file" "CABINET_ENABLED" "true"
  bedolaga_upsert_env_value "$env_file" "CABINET_URL" "https://${cabinet_domain}"
  bedolaga_upsert_env_value "$env_file" "CABINET_JWT_SECRET" "$cabinet_jwt_secret"
  bedolaga_upsert_env_value "$env_file" "CABINET_ALLOWED_ORIGINS" "https://${cabinet_domain}"
  if [[ -n "$bot_username" ]]; then
    bedolaga_upsert_env_value "$env_file" "BOT_USERNAME" "$bot_username"
  fi

  return 0
}

bedolaga_sync_cabinet_env() {
  local cabinet_dir="$1"
  local bot_username="$2"
  local cabinet_port="$3"
  local env_file="${cabinet_dir}/.env"

  if ! bedolaga_ensure_env_file_from_example "$cabinet_dir"; then
    paint "$CLR_DANGER" "$(tr_text "Не найден .env.example в репозитории кабинета." "Missing .env.example in cabinet repository.")"
    return 1
  fi

  bedolaga_upsert_env_value "$env_file" "VITE_API_URL" "/api"
  if [[ -n "$bot_username" ]]; then
    bedolaga_upsert_env_value "$env_file" "VITE_TELEGRAM_BOT_USERNAME" "$bot_username"
  fi
  bedolaga_upsert_env_value "$env_file" "CABINET_PORT" "$cabinet_port"
}

bedolaga_apply_notification_defaults() {
  local env_file="$1"
  local admin_notifications_enabled="$2"
  local admin_notifications_chat_id="$3"
  local admin_notifications_topic_id="$4"
  local admin_notifications_ticket_topic_id="$5"
  local admin_reports_enabled="$6"
  local admin_reports_chat_id="$7"
  local admin_reports_topic_id="$8"
  local admin_reports_send_time="$9"
  local channel_sub_id="${10}"
  local channel_is_required_sub="${11}"
  local channel_link="${12}"

  bedolaga_upsert_env_value "$env_file" "ADMIN_NOTIFICATIONS_ENABLED" "$admin_notifications_enabled"
  bedolaga_upsert_if_not_empty "$env_file" "ADMIN_NOTIFICATIONS_CHAT_ID" "$admin_notifications_chat_id"
  bedolaga_upsert_if_not_empty "$env_file" "ADMIN_NOTIFICATIONS_TOPIC_ID" "$admin_notifications_topic_id"
  bedolaga_upsert_if_not_empty "$env_file" "ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID" "$admin_notifications_ticket_topic_id"
  bedolaga_upsert_env_value "$env_file" "ADMIN_REPORTS_ENABLED" "$admin_reports_enabled"
  bedolaga_upsert_if_not_empty "$env_file" "ADMIN_REPORTS_CHAT_ID" "$admin_reports_chat_id"
  bedolaga_upsert_if_not_empty "$env_file" "ADMIN_REPORTS_TOPIC_ID" "$admin_reports_topic_id"
  bedolaga_upsert_if_not_empty "$env_file" "ADMIN_REPORTS_SEND_TIME" "$admin_reports_send_time"
  bedolaga_upsert_if_not_empty "$env_file" "CHANNEL_SUB_ID" "$channel_sub_id"
  bedolaga_upsert_env_value "$env_file" "CHANNEL_IS_REQUIRED_SUB" "$channel_is_required_sub"
  bedolaga_upsert_if_not_empty "$env_file" "CHANNEL_LINK" "$channel_link"
}

bedolaga_apply_backup_send_defaults() {
  local env_file="$1"
  local backup_send_enabled="$2"
  local backup_send_chat_id="$3"
  local backup_send_topic_id="$4"

  bedolaga_upsert_env_value "$env_file" "BACKUP_SEND_ENABLED" "$backup_send_enabled"
  bedolaga_upsert_if_not_empty "$env_file" "BACKUP_SEND_CHAT_ID" "$backup_send_chat_id"
  bedolaga_upsert_if_not_empty "$env_file" "BACKUP_SEND_TOPIC_ID" "$backup_send_topic_id"
}

bedolaga_detect_bot_username() {
  local bot_token="$1"
  local username=""
  username="$(curl -fsSL "https://api.telegram.org/bot${bot_token}/getMe" 2>/dev/null | sed -n 's/.*"username":"\([^"]*\)".*/\1/p' | head -n1 || true)"
  echo "$username"
}

bedolaga_ensure_shared_network() {
  if ! $SUDO docker network inspect "$BEDOLAGA_SHARED_NETWORK" >/dev/null 2>&1; then
    $SUDO docker network create "$BEDOLAGA_SHARED_NETWORK" >/dev/null
  fi
}

bedolaga_connect_container_to_network() {
  local container_name="$1"
  if ! $SUDO docker ps -a --format '{{.Names}}' | grep -qx "$container_name"; then
    return 0
  fi
  if $SUDO docker inspect "$container_name" --format '{{json .NetworkSettings.Networks}}' | grep -q "\"${BEDOLAGA_SHARED_NETWORK}\""; then
    return 0
  fi
  $SUDO docker network connect "$BEDOLAGA_SHARED_NETWORK" "$container_name" >/dev/null 2>&1 || true
}

bedolaga_collect_container_logs_if_needed() {
  local container_name="$1"
  local state=""
  local health=""
  local show_logs="0"

  if ! $SUDO docker ps -a --format '{{.Names}}' | grep -qx "$container_name"; then
    paint "$CLR_DANGER" "$(tr_text "Контейнер не найден:" "Container not found:") ${container_name}"
    return 1
  fi

  state="$($SUDO docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")"
  health="$($SUDO docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_name" 2>/dev/null || echo "none")"
  paint "$CLR_MUTED" "  - ${container_name}: state=${state}, health=${health}"

  if [[ "$state" != "running" ]]; then
    show_logs="1"
  fi
  if [[ "$health" != "none" && "$health" != "healthy" ]]; then
    show_logs="1"
  fi

  if [[ "$show_logs" == "1" ]]; then
    paint "$CLR_WARN" "$(tr_text "Проблема в контейнере, показываю последние логи:" "Container issue detected, showing recent logs:") ${container_name}"
    $SUDO docker logs --tail 120 "$container_name" 2>&1 || true
    return 1
  fi
  return 0
}

bedolaga_post_deploy_health_check() {
  local failed="0"

  paint "$CLR_ACCENT" "$(tr_text "Проверяю состояние контейнеров Bedolaga..." "Checking Bedolaga container health...")"
  bedolaga_collect_container_logs_if_needed "remnawave_bot" || failed="1"
  bedolaga_collect_container_logs_if_needed "remnawave_bot_db" || failed="1"
  bedolaga_collect_container_logs_if_needed "remnawave_bot_redis" || failed="1"
  bedolaga_collect_container_logs_if_needed "cabinet_frontend" || failed="1"

  if [[ "$failed" == "1" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Обнаружены проблемы после запуска Bedolaga. Исправьте ошибки по логам выше." "Issues detected after Bedolaga start. Fix errors using logs above.")"
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Контейнеры Bedolaga запущены корректно." "Bedolaga containers are healthy.")"
  return 0
}

bedolaga_attach_stack_to_shared_network() {
  bedolaga_ensure_shared_network || return 1
  bedolaga_connect_container_to_network "remnawave_bot"
  bedolaga_connect_container_to_network "remnawave_bot_db"
  bedolaga_connect_container_to_network "remnawave_bot_redis"
  bedolaga_connect_container_to_network "cabinet_frontend"
}

bedolaga_detect_caddy_runtime() {
  local container=""
  local inspect_path=""
  local host_file=""
  local candidate=""
  local -a candidates=(
    "/opt/remnawave/caddy/Caddyfile"
    "/root/caddy/Caddyfile"
    "/etc/caddy/Caddyfile"
  )

  CADDY_MODE=""
  CADDY_CONTAINER_NAME=""
  CADDY_FILE_PATH=""

  for container in remnawave-caddy remnawave_caddy caddy; do
    if $SUDO docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
      inspect_path="$($SUDO docker inspect "$container" \
        --format '{{range .Mounts}}{{if eq .Destination "/etc/caddy/Caddyfile"}}{{println .Source}}{{end}}{{end}}' \
        2>/dev/null | head -n1 || true)"
      if [[ -n "$inspect_path" && -f "$inspect_path" ]]; then
        CADDY_MODE="container"
        CADDY_CONTAINER_NAME="$container"
        CADDY_FILE_PATH="$inspect_path"
        return 0
      fi
    fi
  done

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      CADDY_MODE="host"
      CADDY_FILE_PATH="$candidate"
      return 0
    fi
  done

  if command -v caddy >/dev/null 2>&1; then
    host_file="/etc/caddy/Caddyfile"
    if [[ -f "$host_file" ]]; then
      CADDY_MODE="host"
      CADDY_FILE_PATH="$host_file"
      return 0
    fi
  fi

  paint "$CLR_DANGER" "$(tr_text "Не найден Caddyfile. Установите Caddy или контейнер remnawave-caddy и повторите." "Caddyfile not found. Install Caddy or remnawave-caddy container and retry.")"
  return 1
}

bedolaga_ensure_caddy_runtime() {
  if bedolaga_detect_caddy_runtime; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Caddy не найден, требуется установка для публикации webhook и кабинета." "Caddy was not found, installation is required to publish webhook and cabinet.")"
  if ! ask_yes_no "$(tr_text "Установить Caddy и создать базовый Caddyfile сейчас?" "Install Caddy and create base Caddyfile now?")" "y"; then
    return 1
  fi

  if ! ensure_remnanode_caddy_installed; then
    return 1
  fi

  CADDY_MODE="host"
  CADDY_CONTAINER_NAME=""
  CADDY_FILE_PATH="/etc/caddy/Caddyfile"

  if [[ ! -f "$CADDY_FILE_PATH" ]]; then
    $SUDO install -d -m 755 /etc/caddy
    $SUDO bash -c "cat > '$CADDY_FILE_PATH' <<'CADDY'
{
    servers :443 {
        protocols h1 h2 h3
    }
    servers :80 {
        protocols h1
    }
}
CADDY"
  fi

  return 0
}

bedolaga_validate_and_reload_caddy() {
  if [[ "$CADDY_MODE" == "container" ]]; then
    $SUDO docker exec "$CADDY_CONTAINER_NAME" sh -lc 'mkdir -p /var/log/caddy' >/dev/null 2>&1 || true
  else
    $SUDO install -d -m 755 /var/log/caddy >/dev/null 2>&1 || true
    if id -u caddy >/dev/null 2>&1; then
      $SUDO chown caddy:caddy /var/log/caddy >/dev/null 2>&1 || true
    fi
  fi

  if [[ "$CADDY_MODE" == "container" ]]; then
    if ! $SUDO docker exec "$CADDY_CONTAINER_NAME" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
      return 1
    fi
    if $SUDO docker exec "$CADDY_CONTAINER_NAME" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
      return 0
    fi
    $SUDO docker restart "$CADDY_CONTAINER_NAME" >/dev/null 2>&1
    return $?
  fi

  if ! $SUDO caddy validate --config "$CADDY_FILE_PATH" >/dev/null 2>&1; then
    return 1
  fi
  $SUDO systemctl reload caddy >/dev/null 2>&1
}

bedolaga_apply_caddy_block() {
  local hooks_domain="$1"
  local cabinet_domain="$2"
  local api_domain="$3"
  local cabinet_port="$4"
  local force_replace="${5:-0}"
  local marker_begin="# BEGIN BEDOLAGA_AUTOGEN"
  local marker_end="# END BEDOLAGA_AUTOGEN"
  local tmp_file=""
  local backup_file=""
  local caddy_file="$CADDY_FILE_PATH"
  local bot_upstream="127.0.0.1:8080"
  local cabinet_upstream="127.0.0.1:${cabinet_port}"
  local bot_for_api="$bot_upstream"

  if [[ -z "$caddy_file" || ! -f "$caddy_file" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не найден Caddyfile для изменения." "Caddyfile for update was not found.")"
    return 1
  fi

  if [[ "$CADDY_MODE" == "container" ]]; then
    bot_upstream="remnawave_bot:8080"
    cabinet_upstream="cabinet_frontend:80"
    bot_for_api="remnawave_bot:8080"
  fi

  backup_file="${caddy_file}.bak-$(date -u +%Y%m%d-%H%M%S)"
  $SUDO cp "$caddy_file" "$backup_file"

  tmp_file="$(mktemp "${TMP_DIR}/caddy.XXXXXX")"
  if [[ "$force_replace" == "1" ]]; then
    cat > "$tmp_file" <<'CADDY'
{
    servers :443 {
        protocols h1 h2 h3
    }
    servers :80 {
        protocols h1
    }
}
CADDY
  else
    awk -v mb="$marker_begin" -v me="$marker_end" '
      BEGIN { skip=0 }
      index($0, mb) { skip=1; next }
      index($0, me) { skip=0; next }
      skip == 0 { print }
    ' "$caddy_file" > "$tmp_file"
  fi

  cat >> "$tmp_file" <<CADDY

${marker_begin}
https://${hooks_domain} {
    encode gzip zstd
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "no-referrer-when-downgrade"
    }
    reverse_proxy ${bot_upstream} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    log {
        output file /var/log/caddy/hooks.access.log {
            roll_size 50mb
            roll_keep 5
            roll_keep_for 720h
        }
        level INFO
    }
}

https://${cabinet_domain} {
    encode gzip zstd
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    handle /api/* {
        uri strip_prefix /api
        reverse_proxy ${bot_upstream} {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    handle {
        reverse_proxy ${cabinet_upstream}
    }
    log {
        output file /var/log/caddy/cabinet.access.log {
            roll_size 50mb
            roll_keep 5
            roll_keep_for 720h
        }
        level INFO
    }
}

https://${api_domain} {
    encode gzip zstd
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "no-referrer-when-downgrade"
    }
    @ws path /central/ws*
    handle @ws {
        uri strip_prefix /central
        reverse_proxy ${bot_for_api} {
            transport http {
                versions 1.1
                read_timeout 1h
                write_timeout 1h
            }
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Connection "Upgrade"
            header_up Upgrade "websocket"
        }
    }
    handle {
        reverse_proxy ${bot_for_api} {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    log {
        output file /var/log/caddy/api.access.log {
            roll_size 50mb
            roll_keep 5
            roll_keep_for 720h
        }
        level INFO
    }
}
${marker_end}
CADDY

  $SUDO mv "$tmp_file" "$caddy_file"

  if ! bedolaga_validate_and_reload_caddy; then
    paint "$CLR_DANGER" "$(tr_text "Проверка Caddyfile не прошла, откатываю изменения." "Caddyfile validation failed, rolling back changes.")"
    $SUDO cp "$backup_file" "$caddy_file"
    bedolaga_validate_and_reload_caddy >/dev/null 2>&1 || true
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Caddy обновлен: " "Caddy updated: ")${caddy_file}"
  return 0
}

run_bedolaga_stack_install_flow() {
  local bot_dir="/root/remnawave-bedolaga-telegram-bot"
  local cabinet_dir="/root/bedolaga-cabinet"
  local bot_repo="$BEDOLAGA_BOT_REPO_DEFAULT"
  local cabinet_repo="$BEDOLAGA_CABINET_REPO_DEFAULT"
  local hooks_domain=""
  local cabinet_domain=""
  local api_domain=""
  local bot_token=""
  local admin_ids=""
  local remnawave_api_url=""
  local remnawave_api_key=""
  local bot_username=""
  local cabinet_port="3020"
  local postgres_db="remnawave_bot"
  local postgres_user="remnawave_user"
  local postgres_password=""
  local configure_notifications="0"
  local configure_backup_send="0"
  local admin_notifications_enabled="true"
  local admin_notifications_chat_id=""
  local admin_notifications_topic_id=""
  local admin_notifications_ticket_topic_id=""
  local admin_reports_enabled="false"
  local admin_reports_chat_id=""
  local admin_reports_topic_id=""
  local admin_reports_send_time="10:00"
  local channel_sub_id=""
  local channel_is_required_sub="false"
  local channel_link=""
  local backup_send_enabled="true"
  local backup_send_chat_id=""
  local backup_send_topic_id=""
  local replace_caddy_config="0"

  draw_subheader "$(tr_text "Bedolaga: установка (бот + кабинет + Caddy)" "Bedolaga: install (bot + cabinet + Caddy)")"

  if ! ensure_docker_available; then
    return 1
  fi
  if ! ensure_openssl_available; then
    return 1
  fi
  if ! ensure_git_available; then
    return 1
  fi
  if ! bedolaga_ensure_caddy_runtime; then
    return 1
  fi
  paint "$CLR_MUTED" "$(tr_text "Обнаружен Caddy: " "Detected Caddy: ")${CADDY_MODE} (${CADDY_FILE_PATH})"
  if ask_yes_no "$(tr_text "Заменить весь Caddyfile на шаблон Bedolaga? (иначе обновится только автоген-блок)" "Replace full Caddyfile with Bedolaga template? (otherwise only autogen block is updated)")" "n"; then
    replace_caddy_config="1"
  fi

  hooks_domain="$(ask_value "$(tr_text "Домен для bot webhook/API (пример: hooks.example.com)" "Domain for bot webhook/API (example: hooks.example.com)")" "")"
  [[ "$hooks_domain" == "__PBM_BACK__" ]] && return 1
  [[ -n "$hooks_domain" ]] || return 1

  cabinet_domain="$(ask_value "$(tr_text "Домен для кабинета (пример: cabinet.example.com)" "Domain for cabinet (example: cabinet.example.com)")" "")"
  [[ "$cabinet_domain" == "__PBM_BACK__" ]] && return 1
  [[ -n "$cabinet_domain" ]] || return 1

  api_domain="$(ask_value "$(tr_text "Домен для API (пример: api.example.com)" "Domain for API (example: api.example.com)")" "")"
  [[ "$api_domain" == "__PBM_BACK__" ]] && return 1
  [[ -n "$api_domain" ]] || return 1

  bot_token="$(ask_value "$(tr_text "BOT_TOKEN Telegram" "Telegram BOT_TOKEN")" "")"
  [[ "$bot_token" == "__PBM_BACK__" ]] && return 1
  [[ -n "$bot_token" ]] || return 1

  admin_ids="$(ask_value "$(tr_text "ADMIN_IDS (через запятую)" "ADMIN_IDS (comma-separated)")" "")"
  [[ "$admin_ids" == "__PBM_BACK__" ]] && return 1
  [[ -n "$admin_ids" ]] || return 1

  bot_username="$(ask_value "$(tr_text "BOT_USERNAME (без @, опционально)" "BOT_USERNAME (without @, optional)")" "")"
  [[ "$bot_username" == "__PBM_BACK__" ]] && return 1
  if [[ -z "$bot_username" ]]; then
    paint "$CLR_MUTED" "$(tr_text "Пробую определить BOT_USERNAME автоматически..." "Trying to detect BOT_USERNAME automatically...")"
    bot_username="$(bedolaga_detect_bot_username "$bot_token")"
  fi
  if [[ -z "$bot_username" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось определить BOT_USERNAME. Укажите username бота вручную (без @)." "Failed to detect BOT_USERNAME. Provide bot username manually (without @).")"
    return 1
  fi

  remnawave_api_url="$(ask_value "$(tr_text "REMNAWAVE_API_URL (URL панели, например https://panel.example.com)" "REMNAWAVE_API_URL (panel URL, for example https://panel.example.com)")" "")"
  [[ "$remnawave_api_url" == "__PBM_BACK__" ]] && return 1
  [[ -n "$remnawave_api_url" ]] || return 1

  remnawave_api_key="$(ask_secret_value "$(tr_text "REMNAWAVE_API_KEY" "REMNAWAVE_API_KEY")" "")"
  [[ "$remnawave_api_key" == "__PBM_BACK__" ]] && return 1
  [[ -n "$remnawave_api_key" ]] || return 1

  postgres_db="$(ask_value "$(tr_text "POSTGRES_DB (база данных бота)" "POSTGRES_DB (bot database name)")" "$postgres_db")"
  [[ "$postgres_db" == "__PBM_BACK__" ]] && return 1
  [[ -n "$postgres_db" ]] || return 1

  postgres_user="$(ask_value "$(tr_text "POSTGRES_USER (пользователь БД бота)" "POSTGRES_USER (bot database user)")" "$postgres_user")"
  [[ "$postgres_user" == "__PBM_BACK__" ]] && return 1
  [[ -n "$postgres_user" ]] || return 1

  postgres_password="$(ask_secret_value "$(tr_text "POSTGRES_PASSWORD (пароль БД бота)" "POSTGRES_PASSWORD (bot database password)")" "$(generate_hex 24)")"
  [[ "$postgres_password" == "__PBM_BACK__" ]] && return 1
  [[ -n "$postgres_password" ]] || return 1

  if ask_yes_no "$(tr_text "Настроить уведомления админов/отчеты/подписку на канал сейчас?" "Configure admin notifications/reports/channel subscription now?")" "n"; then
    configure_notifications="1"
  fi

  if [[ "$configure_notifications" == "1" ]]; then
    admin_notifications_enabled="$(ask_value "$(tr_text "ADMIN_NOTIFICATIONS_ENABLED (true/false)" "ADMIN_NOTIFICATIONS_ENABLED (true/false)")" "$admin_notifications_enabled")"
    [[ "$admin_notifications_enabled" == "__PBM_BACK__" ]] && return 1

    admin_notifications_chat_id="$(ask_value "$(tr_text "ADMIN_NOTIFICATIONS_CHAT_ID (пример: -1001234567890)" "ADMIN_NOTIFICATIONS_CHAT_ID (example: -1001234567890)")" "$admin_notifications_chat_id")"
    [[ "$admin_notifications_chat_id" == "__PBM_BACK__" ]] && return 1

    admin_notifications_topic_id="$(ask_value "$(tr_text "ADMIN_NOTIFICATIONS_TOPIC_ID (опционально, пример: 2)" "ADMIN_NOTIFICATIONS_TOPIC_ID (optional, example: 2)")" "$admin_notifications_topic_id")"
    [[ "$admin_notifications_topic_id" == "__PBM_BACK__" ]] && return 1

    admin_notifications_ticket_topic_id="$(ask_value "$(tr_text "ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID (опционально, пример: 126)" "ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID (optional, example: 126)")" "$admin_notifications_ticket_topic_id")"
    [[ "$admin_notifications_ticket_topic_id" == "__PBM_BACK__" ]] && return 1

    admin_reports_enabled="$(ask_value "$(tr_text "ADMIN_REPORTS_ENABLED (true/false)" "ADMIN_REPORTS_ENABLED (true/false)")" "$admin_reports_enabled")"
    [[ "$admin_reports_enabled" == "__PBM_BACK__" ]] && return 1

    admin_reports_chat_id="$(ask_value "$(tr_text "ADMIN_REPORTS_CHAT_ID (опционально, пример: -1001234567890)" "ADMIN_REPORTS_CHAT_ID (optional, example: -1001234567890)")" "$admin_reports_chat_id")"
    [[ "$admin_reports_chat_id" == "__PBM_BACK__" ]] && return 1

    admin_reports_topic_id="$(ask_value "$(tr_text "ADMIN_REPORTS_TOPIC_ID (опционально, пример: 339)" "ADMIN_REPORTS_TOPIC_ID (optional, example: 339)")" "$admin_reports_topic_id")"
    [[ "$admin_reports_topic_id" == "__PBM_BACK__" ]] && return 1

    admin_reports_send_time="$(ask_value "$(tr_text "ADMIN_REPORTS_SEND_TIME (HH:MM, пример: 10:00)" "ADMIN_REPORTS_SEND_TIME (HH:MM, example: 10:00)")" "$admin_reports_send_time")"
    [[ "$admin_reports_send_time" == "__PBM_BACK__" ]] && return 1

    channel_sub_id="$(ask_value "$(tr_text "CHANNEL_SUB_ID (опционально, формат: -100...)" "CHANNEL_SUB_ID (optional, format: -100...)")" "$channel_sub_id")"
    [[ "$channel_sub_id" == "__PBM_BACK__" ]] && return 1

    channel_is_required_sub="$(ask_value "$(tr_text "CHANNEL_IS_REQUIRED_SUB (true/false)" "CHANNEL_IS_REQUIRED_SUB (true/false)")" "$channel_is_required_sub")"
    [[ "$channel_is_required_sub" == "__PBM_BACK__" ]] && return 1

    channel_link="$(ask_value "$(tr_text "CHANNEL_LINK (опционально, пример: https://t.me/your_channel)" "CHANNEL_LINK (optional, example: https://t.me/your_channel)")" "$channel_link")"
    [[ "$channel_link" == "__PBM_BACK__" ]] && return 1
  fi

  if ask_yes_no "$(tr_text "Настроить отправку backup в Telegram сейчас?" "Configure backup send to Telegram now?")" "n"; then
    configure_backup_send="1"
  fi

  if [[ "$configure_backup_send" == "1" ]]; then
    backup_send_enabled="$(ask_value "$(tr_text "BACKUP_SEND_ENABLED (true/false)" "BACKUP_SEND_ENABLED (true/false)")" "$backup_send_enabled")"
    [[ "$backup_send_enabled" == "__PBM_BACK__" ]] && return 1

    backup_send_chat_id="$(ask_value "$(tr_text "BACKUP_SEND_CHAT_ID (формат: -100..., пример: -1001234567890)" "BACKUP_SEND_CHAT_ID (format: -100..., example: -1001234567890)")" "$backup_send_chat_id")"
    [[ "$backup_send_chat_id" == "__PBM_BACK__" ]] && return 1

    backup_send_topic_id="$(ask_value "$(tr_text "BACKUP_SEND_TOPIC_ID (опционально, пример: 8)" "BACKUP_SEND_TOPIC_ID (optional, example: 8)")" "$backup_send_topic_id")"
    [[ "$backup_send_topic_id" == "__PBM_BACK__" ]] && return 1
  fi

  cabinet_port="$(ask_value "$(tr_text "Локальный порт cabinet (для Caddy reverse proxy)" "Local cabinet port (for Caddy reverse proxy)")" "3020")"
  [[ "$cabinet_port" == "__PBM_BACK__" ]] && return 1
  if [[ ! "$cabinet_port" =~ ^[0-9]+$ ]]; then
    paint "$CLR_DANGER" "$(tr_text "Порт cabinet должен быть числом." "Cabinet port must be numeric.")"
    return 1
  fi

  if ! bedolaga_clone_or_update_repo "$bot_repo" "$bot_dir"; then
    return 1
  fi
  if ! bedolaga_clone_or_update_repo "$cabinet_repo" "$cabinet_dir"; then
    return 1
  fi

  bedolaga_prepare_bot_dirs "$bot_dir"
  if ! bedolaga_configure_bot_env "$bot_dir" "$bot_token" "$admin_ids" "$hooks_domain" "$cabinet_domain" "$remnawave_api_url" "$remnawave_api_key" "$bot_username" "$postgres_db" "$postgres_user" "$postgres_password"; then
    return 1
  fi
  if [[ "$configure_notifications" == "1" ]]; then
    bedolaga_apply_notification_defaults \
      "${bot_dir}/.env" \
      "$admin_notifications_enabled" \
      "$admin_notifications_chat_id" \
      "$admin_notifications_topic_id" \
      "$admin_notifications_ticket_topic_id" \
      "$admin_reports_enabled" \
      "$admin_reports_chat_id" \
      "$admin_reports_topic_id" \
      "$admin_reports_send_time" \
      "$channel_sub_id" \
      "$channel_is_required_sub" \
      "$channel_link"
  fi
  if [[ "$configure_backup_send" == "1" ]]; then
    bedolaga_apply_backup_send_defaults \
      "${bot_dir}/.env" \
      "$backup_send_enabled" \
      "$backup_send_chat_id" \
      "$backup_send_topic_id"
  fi

  ( cd "$bot_dir" && $SUDO docker compose up -d --build ) || return 1

  if ! bedolaga_sync_cabinet_env "$cabinet_dir" "$bot_username" "$cabinet_port"; then
    return 1
  fi

  ( cd "$cabinet_dir" && $SUDO docker compose up -d --build ) || return 1
  bedolaga_attach_stack_to_shared_network || return 1

  if ! bedolaga_apply_caddy_block "$hooks_domain" "$cabinet_domain" "$api_domain" "$cabinet_port" "$replace_caddy_config"; then
    return 1
  fi
  if ! bedolaga_post_deploy_health_check; then
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Bedolaga stack установлен и запущен." "Bedolaga stack installed and started.")"
  return 0
}

run_bedolaga_stack_update_flow() {
  local bot_dir="/root/remnawave-bedolaga-telegram-bot"
  local cabinet_dir="/root/bedolaga-cabinet"
  local replace_caddy_config="0"
  local hooks_domain=""
  local cabinet_domain=""
  local api_domain=""
  local cabinet_port="3020"
  local bot_env_file="${bot_dir}/.env"
  local bot_username=""
  local bot_token=""

  draw_subheader "$(tr_text "Bedolaga: обновление (бот + кабинет)" "Bedolaga: update (bot + cabinet)")"

  if ! ensure_docker_available; then
    return 1
  fi
  if ! ensure_git_available; then
    return 1
  fi
  if ! bedolaga_ensure_caddy_runtime; then
    return 1
  fi

  if [[ ! -d "${bot_dir}/.git" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не найден установленный репозиторий бота в /root/remnawave-bedolaga-telegram-bot" "Installed bot repository not found in /root/remnawave-bedolaga-telegram-bot")"
    return 1
  fi
  if [[ ! -d "${cabinet_dir}/.git" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не найден установленный репозиторий кабинета в /root/bedolaga-cabinet" "Installed cabinet repository not found in /root/bedolaga-cabinet")"
    return 1
  fi

  hooks_domain="$(ask_value "$(tr_text "Домен webhook/API (как в установке)" "Webhook/API domain (same as install)")" "")"
  [[ "$hooks_domain" == "__PBM_BACK__" ]] && return 1
  [[ -n "$hooks_domain" ]] || return 1

  cabinet_domain="$(ask_value "$(tr_text "Домен кабинета (как в установке)" "Cabinet domain (same as install)")" "")"
  [[ "$cabinet_domain" == "__PBM_BACK__" ]] && return 1
  [[ -n "$cabinet_domain" ]] || return 1

  api_domain="$(ask_value "$(tr_text "Домен API (как в установке)" "API domain (same as install)")" "")"
  [[ "$api_domain" == "__PBM_BACK__" ]] && return 1
  [[ -n "$api_domain" ]] || return 1

  cabinet_port="$(ask_value "$(tr_text "Локальный порт cabinet (для Caddy reverse proxy)" "Local cabinet port (for Caddy reverse proxy)")" "3020")"
  [[ "$cabinet_port" == "__PBM_BACK__" ]] && return 1
  if [[ ! "$cabinet_port" =~ ^[0-9]+$ ]]; then
    paint "$CLR_DANGER" "$(tr_text "Порт cabinet должен быть числом." "Cabinet port must be numeric.")"
    return 1
  fi

  bedolaga_clone_or_update_repo "$BEDOLAGA_BOT_REPO_DEFAULT" "$bot_dir" || return 1
  bedolaga_clone_or_update_repo "$BEDOLAGA_CABINET_REPO_DEFAULT" "$cabinet_dir" || return 1

  bot_username="$(bedolaga_read_env_value "$bot_env_file" "BOT_USERNAME")"
  if [[ -z "$bot_username" ]]; then
    bot_token="$(bedolaga_read_env_value "$bot_env_file" "BOT_TOKEN")"
    if [[ -n "$bot_token" ]]; then
      bot_username="$(bedolaga_detect_bot_username "$bot_token")"
    fi
  fi
  if ! bedolaga_sync_bot_env_defaults "$bot_dir" "$hooks_domain" "$cabinet_domain" "$bot_username"; then
    return 1
  fi
  if ! bedolaga_sync_cabinet_env "$cabinet_dir" "$bot_username" "$cabinet_port"; then
    return 1
  fi

  ( cd "$bot_dir" && $SUDO docker compose up -d --build ) || return 1
  ( cd "$cabinet_dir" && $SUDO docker compose up -d --build ) || return 1
  bedolaga_attach_stack_to_shared_network || return 1

  if ask_yes_no "$(tr_text "Заменить весь Caddyfile на шаблон Bedolaga? (иначе обновится только автоген-блок)" "Replace full Caddyfile with Bedolaga template? (otherwise only autogen block is updated)")" "n"; then
    replace_caddy_config="1"
  fi
  if ! bedolaga_apply_caddy_block "$hooks_domain" "$cabinet_domain" "$api_domain" "$cabinet_port" "$replace_caddy_config"; then
    return 1
  fi
  if ! bedolaga_post_deploy_health_check; then
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Bedolaga stack обновлен." "Bedolaga stack updated.")"
  return 0
}
