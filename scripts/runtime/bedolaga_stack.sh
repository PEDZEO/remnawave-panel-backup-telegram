#!/usr/bin/env bash
# Bedolaga bot + cabinet + caddy installation/update flows.

BEDOLAGA_BOT_REPO_DEFAULT="https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git"
BEDOLAGA_CABINET_REPO_DEFAULT="https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git"
BEDOLAGA_BOT_REPO_FORK_DEFAULT="https://github.com/PEDZEO/remnawave-bedolaga-telegram-bot.git"
BEDOLAGA_CABINET_REPO_FORK_DEFAULT="https://github.com/PEDZEO/cabinet-frontend.git"
BEDOLAGA_SHARED_NETWORK="bedolaga-network"
BEDOLAGA_BOT_REPO_LAST_CUSTOM="${BEDOLAGA_BOT_REPO_LAST_CUSTOM:-$BEDOLAGA_BOT_REPO_FORK_DEFAULT}"
BEDOLAGA_CABINET_REPO_LAST_CUSTOM="${BEDOLAGA_CABINET_REPO_LAST_CUSTOM:-$BEDOLAGA_CABINET_REPO_FORK_DEFAULT}"

bedolaga_detect_repo_origin_url() {
  local repo_dir="$1"
  local url=""

  [[ -d "$repo_dir/.git" ]] || return 1
  url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1
  echo "$url"
  return 0
}

bedolaga_repo_url_to_https() {
  local url="$1"
  if [[ "$url" =~ ^git@github\.com:(.+)\.git$ ]]; then
    echo "https://github.com/${BASH_REMATCH[1]}.git"
    return 0
  fi
  echo "$url"
}

bedolaga_autodetect_fork_repo_urls() {
  local user_dir=""
  local detected=""

  for user_dir in /root /home/*; do
    [[ -d "$user_dir" ]] || continue

    detected="$(bedolaga_detect_repo_origin_url "${user_dir}/GitHub/remnawave-bedolaga-telegram-bot" || true)"
    detected="$(bedolaga_repo_url_to_https "$detected")"
    if bedolaga_validate_git_repo_url "$detected"; then
      BEDOLAGA_BOT_REPO_LAST_CUSTOM="$detected"
      break
    fi
  done

  for user_dir in /root /home/*; do
    [[ -d "$user_dir" ]] || continue

    detected="$(bedolaga_detect_repo_origin_url "${user_dir}/GitHub/cabinet-frontend" || true)"
    detected="$(bedolaga_repo_url_to_https "$detected")"
    if bedolaga_validate_git_repo_url "$detected"; then
      BEDOLAGA_CABINET_REPO_LAST_CUSTOM="$detected"
      break
    fi
  done
}

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

bedolaga_comment_out_env_key() {
  local file_path="$1"
  local key="$2"
  local tmp_file=""

  [[ -f "$file_path" ]] || return 0

  tmp_file="$(mktemp "${TMP_DIR}/bedolaga-env.XXXXXX")"
  awk -v key="$key" '
    $0 ~ "^" key "=" {
      print "# " $0
      next
    }
    { print }
  ' "$file_path" > "$tmp_file"
  mv "$tmp_file" "$file_path"
}

bedolaga_trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "$value"
}

bedolaga_validate_not_empty() {
  [[ -n "$1" ]]
}

bedolaga_validate_domain() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

bedolaga_validate_https_url() {
  local value="$1"
  [[ "$value" =~ ^https://[^[:space:]]+$ ]]
}

bedolaga_validate_git_repo_url() {
  local value="$1"
  [[ "$value" =~ ^https://[^[:space:]]+\.git$ ]] && return 0
  [[ "$value" =~ ^git@[^[:space:]]+:[^[:space:]]+\.git$ ]] && return 0
  return 1
}

bedolaga_normalize_git_repo_url() {
  local value
  value="$(bedolaga_trim_value "$1")"

  if [[ -z "$value" ]]; then
    echo ""
    return 0
  fi
  if [[ "$value" =~ ^https://[^[:space:]]+\.git$ ]] || [[ "$value" =~ ^git@[^[:space:]]+:[^[:space:]]+\.git$ ]]; then
    echo "$value"
    return 0
  fi
  if [[ "$value" =~ ^https://github\.com/[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    echo "${value}.git"
    return 0
  fi
  if [[ "$value" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    echo "https://github.com/${value}.git"
    return 0
  fi
  echo "$value"
}

bedolaga_validate_bot_token() {
  local value="$1"
  [[ "$value" =~ ^[0-9]{6,}:[A-Za-z0-9_-]{20,}$ ]]
}

bedolaga_validate_admin_ids() {
  local value="$1"
  [[ "$value" =~ ^-?[0-9]+(,-?[0-9]+)*$ ]]
}

bedolaga_validate_bool() {
  local value="${1,,}"
  [[ "$value" == "true" || "$value" == "false" ]]
}

bedolaga_validate_int() {
  [[ "$1" =~ ^-?[0-9]+$ ]]
}

bedolaga_validate_optional_int() {
  [[ -z "$1" ]] || bedolaga_validate_int "$1"
}

bedolaga_validate_optional_chat_id() {
  [[ -z "$1" ]] || [[ "$1" =~ ^-?[0-9]+$ ]]
}

bedolaga_validate_optional_channel_link() {
  local value="$1"
  [[ -z "$value" ]] || [[ "$value" =~ ^https?://[^[:space:]]+$ ]]
}

bedolaga_validate_hhmm() {
  [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

bedolaga_prompt_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local validator_func="$3"
  local error_message="$4"
  local value=""
  while true; do
    value="$(ask_value "$prompt" "$default_value")"
    [[ "$value" == "__PBM_BACK__" ]] && echo "__PBM_BACK__" && return 0
    if "$validator_func" "$value"; then
      echo "$value"
      return 0
    fi
    paint "$CLR_WARN" "$error_message"
  done
}

bedolaga_prompt_secret_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local validator_func="$3"
  local error_message="$4"
  local value=""
  while true; do
    value="$(ask_secret_value "$prompt" "$default_value")"
    [[ "$value" == "__PBM_BACK__" ]] && echo "__PBM_BACK__" && return 0
    if "$validator_func" "$value"; then
      echo "$value"
      return 0
    fi
    paint "$CLR_WARN" "$error_message"
  done
}

bedolaga_is_integer_like() {
  local value="$1"
  [[ "$value" =~ ^-?[0-9]+$ ]] && return 0
  [[ "$value" =~ ^\"-?[0-9]+\"$ ]] && return 0
  [[ "$value" =~ ^\'-?[0-9]+\'$ ]] && return 0
  return 1
}

bedolaga_comment_invalid_optional_int() {
  local file_path="$1"
  local key="$2"
  local raw_value=""
  local value=""

  raw_value="$(bedolaga_read_env_value "$file_path" "$key")"
  value="$(bedolaga_trim_value "$raw_value")"

  if [[ -z "$value" || "$value" =~ ^# || "$value" =~ ^\<.*\>$ ]]; then
    bedolaga_comment_out_env_key "$file_path" "$key"
    return 0
  fi
  if ! bedolaga_is_integer_like "$value"; then
    bedolaga_comment_out_env_key "$file_path" "$key"
    return 0
  fi
}

bedolaga_sanitize_bot_optional_int_env() {
  local env_file="$1"

  bedolaga_comment_invalid_optional_int "$env_file" "ADMIN_REPORTS_TOPIC_ID"
  bedolaga_comment_invalid_optional_int "$env_file" "MULENPAY_SHOP_ID"
  bedolaga_comment_invalid_optional_int "$env_file" "FREEKASSA_SHOP_ID"
  bedolaga_comment_invalid_optional_int "$env_file" "FREEKASSA_PAYMENT_SYSTEM_ID"
  bedolaga_comment_invalid_optional_int "$env_file" "KASSA_AI_SHOP_ID"
  bedolaga_comment_invalid_optional_int "$env_file" "LOG_ROTATION_TOPIC_ID"
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
  local webhook_secret_in="${12:-}"
  local web_api_token_in="${13:-}"
  local cabinet_jwt_secret_in="${14:-}"
  local env_file="${bot_dir}/.env"
  local webhook_secret=""
  local web_api_token=""
  local cabinet_jwt_secret=""
  local tmp_file=""

  webhook_secret="${webhook_secret_in:-$(generate_hex 32)}"
  web_api_token="${web_api_token_in:-$(generate_hex 32)}"
  cabinet_jwt_secret="${cabinet_jwt_secret_in:-$(generate_hex 32)}"

  tmp_file="$(mktemp "${TMP_DIR}/bedolaga-bot-env.XXXXXX")"
  cat > "$tmp_file" <<EOF
BOT_TOKEN=${bot_token}
ADMIN_IDS=${admin_ids}
BOT_RUN_MODE=webhook
WEBHOOK_URL=https://${hooks_domain}
WEBHOOK_PATH=/webhook
WEBHOOK_SECRET_TOKEN=${webhook_secret}
WEBHOOK_MAX_QUEUE_SIZE=1024
WEBHOOK_WORKERS=4
WEBHOOK_ENQUEUE_TIMEOUT=0.1
WEBHOOK_WORKER_SHUTDOWN_TIMEOUT=30.0
WEB_API_ENABLED=true
WEB_API_HOST=0.0.0.0
WEB_API_PORT=8080
WEB_API_DEFAULT_TOKEN=${web_api_token}
WEB_API_ALLOWED_ORIGINS=https://${cabinet_domain}
MAIN_MENU_MODE=text
CONNECT_BUTTON_MODE=miniapp_subscription
ENABLE_LOGO_MODE=true
DEFAULT_LANGUAGE=ru
AVAILABLE_LANGUAGES=ru,en
LANGUAGE_SELECTION_ENABLED=true
BACKUP_AUTO_ENABLED=true
BACKUP_INTERVAL_HOURS=24
BACKUP_TIME=03:00
BACKUP_MAX_KEEP=7
BACKUP_COMPRESSION=true
BACKUP_INCLUDE_LOGS=false
BACKUP_LOCATION=/app/data/backups
CABINET_ENABLED=true
CABINET_URL=https://${cabinet_domain}
CABINET_JWT_SECRET=${cabinet_jwt_secret}
CABINET_ALLOWED_ORIGINS=https://${cabinet_domain}
REMNAWAVE_API_URL=${remnawave_api_url}
REMNAWAVE_API_KEY=${remnawave_api_key}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=${postgres_db}
POSTGRES_USER=${postgres_user}
POSTGRES_PASSWORD=${postgres_password}
EOF
  if [[ -n "$bot_username" ]]; then
    printf "BOT_USERNAME=%s\n" "$bot_username" >> "$tmp_file"
  fi
  mv "$tmp_file" "$env_file"
  chmod 600 "$env_file"

  return 0
}

bedolaga_prepare_bot_dirs() {
  local bot_dir="$1"
  mkdir -p "${bot_dir}/logs" "${bot_dir}/data" "${bot_dir}/data/backups" "${bot_dir}/data/referral_qr"
  # Bot container user must be able to write runtime files/logs on host-mounted volumes.
  chmod -R 777 "${bot_dir}/logs" "${bot_dir}/data"
}

bedolaga_write_bot_compose_override() {
  local bot_dir="$1"
  local override_file="${bot_dir}/docker-compose.override.yml"
  cat > "$override_file" <<EOF
services:
  bot:
    networks:
      - default
      - bedolaga-shared

networks:
  bedolaga-shared:
    external: true
    name: ${BEDOLAGA_SHARED_NETWORK}
EOF
}

bedolaga_write_cabinet_compose_override() {
  local cabinet_dir="$1"
  local override_file="${cabinet_dir}/docker-compose.override.yml"
  cat > "$override_file" <<EOF
services:
  cabinet-frontend:
    networks:
      - default
      - bedolaga-shared

networks:
  bedolaga-shared:
    external: true
    name: ${BEDOLAGA_SHARED_NETWORK}
EOF
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

bedolaga_sync_bot_env_defaults() {
  local bot_dir="$1"
  local hooks_domain="$2"
  local cabinet_domain="$3"
  local bot_username="${4:-}"
  local env_file="${bot_dir}/.env"
  local bot_token=""
  local admin_ids=""
  local remnawave_api_url=""
  local remnawave_api_key=""
  local postgres_db=""
  local postgres_user=""
  local postgres_password=""
  local webhook_secret=""
  local web_api_token=""
  local cabinet_jwt_secret=""

  if [[ ! -f "$env_file" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не найден .env бота для обновления." "Bot .env was not found for update.")"
    return 1
  fi

  bot_token="$(bedolaga_read_env_value "$env_file" "BOT_TOKEN")"
  admin_ids="$(bedolaga_read_env_value "$env_file" "ADMIN_IDS")"
  remnawave_api_url="$(bedolaga_read_env_value "$env_file" "REMNAWAVE_API_URL")"
  remnawave_api_key="$(bedolaga_read_env_value "$env_file" "REMNAWAVE_API_KEY")"
  postgres_db="$(bedolaga_read_env_value "$env_file" "POSTGRES_DB")"
  postgres_user="$(bedolaga_read_env_value "$env_file" "POSTGRES_USER")"
  postgres_password="$(bedolaga_read_env_value "$env_file" "POSTGRES_PASSWORD")"
  if [[ -z "$bot_token" || -z "$admin_ids" || -z "$remnawave_api_url" || -z "$remnawave_api_key" || -z "$postgres_db" || -z "$postgres_user" || -z "$postgres_password" ]]; then
    paint "$CLR_DANGER" "$(tr_text "В .env бота отсутствуют обязательные поля (BOT_TOKEN, ADMIN_IDS, REMNAWAVE_API_*, POSTGRES_*)." "Bot .env misses required fields (BOT_TOKEN, ADMIN_IDS, REMNAWAVE_API_*, POSTGRES_*).")"
    return 1
  fi

  webhook_secret="$(bedolaga_read_env_value "$env_file" "WEBHOOK_SECRET_TOKEN")"
  web_api_token="$(bedolaga_read_env_value "$env_file" "WEB_API_DEFAULT_TOKEN")"
  cabinet_jwt_secret="$(bedolaga_read_env_value "$env_file" "CABINET_JWT_SECRET")"
  bedolaga_configure_bot_env \
    "$bot_dir" \
    "$bot_token" \
    "$admin_ids" \
    "$hooks_domain" \
    "$cabinet_domain" \
    "$remnawave_api_url" \
    "$remnawave_api_key" \
    "$bot_username" \
    "$postgres_db" \
    "$postgres_user" \
    "$postgres_password" \
    "$webhook_secret" \
    "$web_api_token" \
    "$cabinet_jwt_secret"
}

bedolaga_sync_cabinet_env() {
  local cabinet_dir="$1"
  local bot_username="$2"
  local cabinet_port="$3"
  local env_file="${cabinet_dir}/.env"
  local tmp_file=""

  tmp_file="$(mktemp "${TMP_DIR}/bedolaga-cabinet-env.XXXXXX")"
  cat > "$tmp_file" <<EOF
VITE_API_URL=/api
CABINET_PORT=${cabinet_port}
EOF
  if [[ -n "$bot_username" ]]; then
    printf "VITE_TELEGRAM_BOT_USERNAME=%s\n" "$bot_username" >> "$tmp_file"
  fi
  mv "$tmp_file" "$env_file"
  chmod 600 "$env_file"
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
  local cabinet_port="${2:-}"
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
  if [[ "$health" == "starting" ]]; then
    paint "$CLR_MUTED" "$(tr_text "Контейнер еще прогревается, продолжаю проверку..." "Container is still starting, continuing checks...")"
    show_logs="0"
  elif [[ "$health" == "unhealthy" && "$container_name" == "cabinet_frontend" && -n "$cabinet_port" ]]; then
    if curl -fsS "http://127.0.0.1:${cabinet_port}/" >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "healthcheck cabinet помечен unhealthy, но HTTP отвечает 200 — продолжаю." "cabinet healthcheck is unhealthy, but HTTP 200 is reachable — continuing.")"
      show_logs="0"
    else
      show_logs="1"
    fi
  elif [[ "$health" != "none" && "$health" != "healthy" ]]; then
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
  local cabinet_port="${1:-3020}"
  local failed="0"

  paint "$CLR_ACCENT" "$(tr_text "Проверяю состояние контейнеров Bedolaga..." "Checking Bedolaga container health...")"
  bedolaga_collect_container_logs_if_needed "remnawave_bot" "$cabinet_port" || failed="1"
  bedolaga_collect_container_logs_if_needed "remnawave_bot_db" "$cabinet_port" || failed="1"
  bedolaga_collect_container_logs_if_needed "remnawave_bot_redis" "$cabinet_port" || failed="1"
  bedolaga_collect_container_logs_if_needed "cabinet_frontend" "$cabinet_port" || failed="1"
  bedolaga_collect_container_logs_if_needed "remnawave-caddy" "$cabinet_port" || failed="1"

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
  bedolaga_connect_container_to_network "remnawave-caddy"
}

bedolaga_verify_caddy_upstream_dns() {
  local target=""
  local resolver_cmd=""

  if ! $SUDO docker ps --format '{{.Names}}' | grep -qx "remnawave-caddy"; then
    return 1
  fi

  for target in remnawave_bot cabinet_frontend; do
    resolver_cmd="getent hosts ${target} >/dev/null 2>&1 || nslookup ${target} 127.0.0.11 >/dev/null 2>&1"
    if ! $SUDO docker exec remnawave-caddy sh -lc "$resolver_cmd" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

bedolaga_repair_shared_network_if_needed() {
  bedolaga_attach_stack_to_shared_network || return 1
  if bedolaga_verify_caddy_upstream_dns; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Обнаружена проблема связи Caddy -> Bedolaga, выполняю автопочинку сети..." "Detected Caddy -> Bedolaga connectivity issue, running network auto-repair...")"
  bedolaga_attach_stack_to_shared_network || return 1
  $SUDO docker restart remnawave-caddy >/dev/null 2>&1 || true
  sleep 2

  if ! bedolaga_verify_caddy_upstream_dns; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось восстановить DNS-маршрутизацию между Caddy и контейнерами Bedolaga." "Failed to restore DNS routing between Caddy and Bedolaga containers.")"
    return 1
  fi
  paint "$CLR_OK" "$(tr_text "Сеть Bedolaga восстановлена: Caddy видит remnawave_bot и cabinet_frontend." "Bedolaga network repaired: Caddy resolves remnawave_bot and cabinet_frontend.")"
  return 0
}

bedolaga_probe_cabinet_ws_route() {
  local cabinet_domain="$1"
  local header_dump=""
  local status_line=""
  local status_code=""
  local server_header=""

  header_dump="$(curl -sS -o /dev/null -D - --http1.1 \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    "https://${cabinet_domain}/cabinet/ws" 2>/dev/null || true)"

  status_line="$(printf '%s\n' "$header_dump" | awk 'tolower($1) ~ /^http\// { print; exit }')"
  status_code="$(printf '%s\n' "$status_line" | awk '{ print $2 }')"
  server_header="$(printf '%s\n' "$header_dump" | awk 'tolower($1)=="server:" { print tolower($0) }' | tail -n1)"

  if [[ "$status_code" == "101" ]]; then
    return 0
  fi
  if [[ "$status_code" == "200" && "$server_header" == *"nginx"* ]]; then
    return 1
  fi
  if [[ "$server_header" == *"uvicorn"* || "$server_header" == *"caddy"* ]]; then
    return 0
  fi
  return 2
}

bedolaga_verify_cabinet_ws_route() {
  local cabinet_domain="$1"
  local attempts=6
  local i=1
  local probe_result=0

  while (( i <= attempts )); do
    bedolaga_probe_cabinet_ws_route "$cabinet_domain"
    probe_result=$?
    if [[ $probe_result -eq 0 ]]; then
      paint "$CLR_OK" "$(tr_text "WebSocket маршрут кабинета проверен: /cabinet/ws доступен." "Cabinet WebSocket route verified: /cabinet/ws is reachable.")"
      return 0
    fi
    if [[ $probe_result -eq 1 ]]; then
      break
    fi
    sleep 2
    i=$((i + 1))
  done

  paint "$CLR_WARN" "$(tr_text "Похоже, /cabinet/ws попадает не в backend. Перезапускаю Caddy и проверяю снова..." "Looks like /cabinet/ws is not reaching backend. Restarting Caddy and checking again...")"
  $SUDO docker restart remnawave-caddy >/dev/null 2>&1 || true
  sleep 3

  bedolaga_probe_cabinet_ws_route "$cabinet_domain"
  probe_result=$?
  if [[ $probe_result -eq 0 ]]; then
    paint "$CLR_OK" "$(tr_text "После перезапуска Caddy маршрут /cabinet/ws восстановлен." "After Caddy restart, /cabinet/ws route recovered.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "WebSocket маршрут /cabinet/ws не прошел проверку. Проверьте Caddyfile и домен кабинета." "WebSocket route /cabinet/ws failed verification. Check Caddyfile and cabinet domain.")"
  return 1
}

run_bedolaga_stack_install_with_repos() {
  local bot_repo="$1"
  local cabinet_repo="$2"
  local bot_dir="/root/remnawave-bedolaga-telegram-bot"
  local cabinet_dir="/root/bedolaga-cabinet"
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
  local existing_env_file="${bot_dir}/.env"
  local existing_value=""

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

  # Keep DB credentials stable on reinstall if the bot is already configured.
  if [[ -f "$existing_env_file" ]]; then
    existing_value="$(bedolaga_read_env_value "$existing_env_file" "POSTGRES_DB")"
    [[ -n "$existing_value" ]] && postgres_db="$existing_value"
    existing_value="$(bedolaga_read_env_value "$existing_env_file" "POSTGRES_USER")"
    [[ -n "$existing_value" ]] && postgres_user="$existing_value"
    existing_value="$(bedolaga_read_env_value "$existing_env_file" "POSTGRES_PASSWORD")"
    [[ -n "$existing_value" ]] && postgres_password="$existing_value"
    existing_value="$(bedolaga_read_env_value "$existing_env_file" "REMNAWAVE_API_KEY")"
    [[ -n "$existing_value" ]] && remnawave_api_key="$existing_value"
    if [[ -n "$postgres_password" ]]; then
      paint "$CLR_MUTED" "$(tr_text "Обнаружен существующий POSTGRES_PASSWORD: уже задан, можно оставить пустым чтобы не менять." "Detected existing POSTGRES_PASSWORD: already set, leave empty to keep unchanged.")"
    fi
    if [[ -n "$remnawave_api_key" ]]; then
      paint "$CLR_MUTED" "$(tr_text "Обнаружен существующий REMNAWAVE_API_KEY: уже задан, можно оставить пустым чтобы не менять." "Detected existing REMNAWAVE_API_KEY: already set, leave empty to keep unchanged.")"
    fi
  fi

  hooks_domain="$(bedolaga_prompt_value "$(tr_text "Домен для bot webhook/API (пример: hooks.example.com)" "Domain for bot webhook/API (example: hooks.example.com)")" "" bedolaga_validate_domain "$(tr_text "Введите корректный домен (без https://)." "Enter a valid domain (without https://).")")"
  [[ "$hooks_domain" == "__PBM_BACK__" ]] && return 1

  cabinet_domain="$(bedolaga_prompt_value "$(tr_text "Домен для кабинета (пример: cabinet.example.com)" "Domain for cabinet (example: cabinet.example.com)")" "" bedolaga_validate_domain "$(tr_text "Введите корректный домен кабинета (без https://)." "Enter a valid cabinet domain (without https://).")")"
  [[ "$cabinet_domain" == "__PBM_BACK__" ]] && return 1

  api_domain="$(bedolaga_prompt_value "$(tr_text "Домен для API (пример: api.example.com)" "Domain for API (example: api.example.com)")" "" bedolaga_validate_domain "$(tr_text "Введите корректный домен API (без https://)." "Enter a valid API domain (without https://).")")"
  [[ "$api_domain" == "__PBM_BACK__" ]] && return 1

  bot_token="$(bedolaga_prompt_value "$(tr_text "BOT_TOKEN Telegram" "Telegram BOT_TOKEN")" "" bedolaga_validate_bot_token "$(tr_text "Неверный формат BOT_TOKEN (пример: 123456789:AA...)." "Invalid BOT_TOKEN format (example: 123456789:AA...).")")"
  [[ "$bot_token" == "__PBM_BACK__" ]] && return 1

  admin_ids="$(bedolaga_prompt_value "$(tr_text "ADMIN_IDS (через запятую)" "ADMIN_IDS (comma-separated)")" "" bedolaga_validate_admin_ids "$(tr_text "Введите ID через запятую: только числа, например 123456789,987654321." "Use comma-separated numeric IDs, e.g. 123456789,987654321.")")"
  [[ "$admin_ids" == "__PBM_BACK__" ]] && return 1

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

  remnawave_api_url="$(bedolaga_prompt_value "$(tr_text "REMNAWAVE_API_URL (URL панели, например https://panel.example.com)" "REMNAWAVE_API_URL (panel URL, for example https://panel.example.com)")" "" bedolaga_validate_https_url "$(tr_text "URL панели должен начинаться с https://." "Panel URL must start with https://.")")"
  [[ "$remnawave_api_url" == "__PBM_BACK__" ]] && return 1

  remnawave_api_key="$(bedolaga_prompt_value "$(tr_text "REMNAWAVE_API_KEY (видимый ввод, Enter = оставить текущее)" "REMNAWAVE_API_KEY (visible input, Enter = keep current)")" "$remnawave_api_key" bedolaga_validate_not_empty "$(tr_text "REMNAWAVE_API_KEY не может быть пустым." "REMNAWAVE_API_KEY cannot be empty.")")"
  [[ "$remnawave_api_key" == "__PBM_BACK__" ]] && return 1

  postgres_db="$(bedolaga_prompt_value "$(tr_text "POSTGRES_DB (база данных бота)" "POSTGRES_DB (bot database name)")" "$postgres_db" bedolaga_validate_not_empty "$(tr_text "POSTGRES_DB не может быть пустым." "POSTGRES_DB cannot be empty.")")"
  [[ "$postgres_db" == "__PBM_BACK__" ]] && return 1

  postgres_user="$(bedolaga_prompt_value "$(tr_text "POSTGRES_USER (пользователь БД бота)" "POSTGRES_USER (bot database user)")" "$postgres_user" bedolaga_validate_not_empty "$(tr_text "POSTGRES_USER не может быть пустым." "POSTGRES_USER cannot be empty.")")"
  [[ "$postgres_user" == "__PBM_BACK__" ]] && return 1

  if [[ -z "$postgres_password" ]]; then
    postgres_password="$(generate_hex 24)"
  fi
  postgres_password="$(bedolaga_prompt_secret_value "$(tr_text "POSTGRES_PASSWORD (пароль БД бота, Enter = оставить текущее)" "POSTGRES_PASSWORD (bot database password, Enter = keep current)")" "$postgres_password" bedolaga_validate_not_empty "$(tr_text "POSTGRES_PASSWORD не может быть пустым." "POSTGRES_PASSWORD cannot be empty.")")"
  [[ "$postgres_password" == "__PBM_BACK__" ]] && return 1

  if ask_yes_no "$(tr_text "Настроить уведомления админов/отчеты/подписку на канал сейчас?" "Configure admin notifications/reports/channel subscription now?")" "n"; then
    configure_notifications="1"
  fi

  if [[ "$configure_notifications" == "1" ]]; then
    admin_notifications_enabled="$(bedolaga_prompt_value "$(tr_text "ADMIN_NOTIFICATIONS_ENABLED (true/false)" "ADMIN_NOTIFICATIONS_ENABLED (true/false)")" "$admin_notifications_enabled" bedolaga_validate_bool "$(tr_text "Допустимо только true или false." "Only true or false is allowed.")")"
    [[ "$admin_notifications_enabled" == "__PBM_BACK__" ]] && return 1

    admin_notifications_chat_id="$(bedolaga_prompt_value "$(tr_text "ADMIN_NOTIFICATIONS_CHAT_ID (пример: -1001234567890)" "ADMIN_NOTIFICATIONS_CHAT_ID (example: -1001234567890)")" "$admin_notifications_chat_id" bedolaga_validate_optional_chat_id "$(tr_text "Введите числовой chat_id (например -1001234567890) или оставьте пусто." "Enter numeric chat_id (e.g. -1001234567890) or leave empty.")")"
    [[ "$admin_notifications_chat_id" == "__PBM_BACK__" ]] && return 1

    admin_notifications_topic_id="$(bedolaga_prompt_value "$(tr_text "ADMIN_NOTIFICATIONS_TOPIC_ID (опционально, пример: 2)" "ADMIN_NOTIFICATIONS_TOPIC_ID (optional, example: 2)")" "$admin_notifications_topic_id" bedolaga_validate_optional_int "$(tr_text "Введите числовой topic_id или оставьте пусто." "Enter numeric topic_id or leave empty.")")"
    [[ "$admin_notifications_topic_id" == "__PBM_BACK__" ]] && return 1

    admin_notifications_ticket_topic_id="$(bedolaga_prompt_value "$(tr_text "ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID (опционально, пример: 126)" "ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID (optional, example: 126)")" "$admin_notifications_ticket_topic_id" bedolaga_validate_optional_int "$(tr_text "Введите числовой topic_id или оставьте пусто." "Enter numeric topic_id or leave empty.")")"
    [[ "$admin_notifications_ticket_topic_id" == "__PBM_BACK__" ]] && return 1

    admin_reports_enabled="$(bedolaga_prompt_value "$(tr_text "ADMIN_REPORTS_ENABLED (true/false)" "ADMIN_REPORTS_ENABLED (true/false)")" "$admin_reports_enabled" bedolaga_validate_bool "$(tr_text "Допустимо только true или false." "Only true or false is allowed.")")"
    [[ "$admin_reports_enabled" == "__PBM_BACK__" ]] && return 1

    admin_reports_chat_id="$(bedolaga_prompt_value "$(tr_text "ADMIN_REPORTS_CHAT_ID (опционально, пример: -1001234567890)" "ADMIN_REPORTS_CHAT_ID (optional, example: -1001234567890)")" "$admin_reports_chat_id" bedolaga_validate_optional_chat_id "$(tr_text "Введите числовой chat_id (например -1001234567890) или оставьте пусто." "Enter numeric chat_id (e.g. -1001234567890) or leave empty.")")"
    [[ "$admin_reports_chat_id" == "__PBM_BACK__" ]] && return 1

    admin_reports_topic_id="$(bedolaga_prompt_value "$(tr_text "ADMIN_REPORTS_TOPIC_ID (опционально, пример: 339)" "ADMIN_REPORTS_TOPIC_ID (optional, example: 339)")" "$admin_reports_topic_id" bedolaga_validate_optional_int "$(tr_text "Введите числовой topic_id или оставьте пусто." "Enter numeric topic_id or leave empty.")")"
    [[ "$admin_reports_topic_id" == "__PBM_BACK__" ]] && return 1

    admin_reports_send_time="$(bedolaga_prompt_value "$(tr_text "ADMIN_REPORTS_SEND_TIME (HH:MM, пример: 10:00)" "ADMIN_REPORTS_SEND_TIME (HH:MM, example: 10:00)")" "$admin_reports_send_time" bedolaga_validate_hhmm "$(tr_text "Введите время в формате HH:MM (например 10:00)." "Enter time in HH:MM format (e.g. 10:00).")")"
    [[ "$admin_reports_send_time" == "__PBM_BACK__" ]] && return 1

    channel_sub_id="$(bedolaga_prompt_value "$(tr_text "CHANNEL_SUB_ID (опционально, формат: -100...)" "CHANNEL_SUB_ID (optional, format: -100...)")" "$channel_sub_id" bedolaga_validate_optional_chat_id "$(tr_text "Введите числовой ID канала (например -100...) или оставьте пусто." "Enter numeric channel ID (e.g. -100...) or leave empty.")")"
    [[ "$channel_sub_id" == "__PBM_BACK__" ]] && return 1

    channel_is_required_sub="$(bedolaga_prompt_value "$(tr_text "CHANNEL_IS_REQUIRED_SUB (true/false)" "CHANNEL_IS_REQUIRED_SUB (true/false)")" "$channel_is_required_sub" bedolaga_validate_bool "$(tr_text "Допустимо только true или false." "Only true or false is allowed.")")"
    [[ "$channel_is_required_sub" == "__PBM_BACK__" ]] && return 1

    channel_link="$(bedolaga_prompt_value "$(tr_text "CHANNEL_LINK (опционально, пример: https://t.me/your_channel)" "CHANNEL_LINK (optional, example: https://t.me/your_channel)")" "$channel_link" bedolaga_validate_optional_channel_link "$(tr_text "Введите корректную ссылку (https://...) или оставьте пусто." "Enter valid URL (https://...) or leave empty.")")"
    [[ "$channel_link" == "__PBM_BACK__" ]] && return 1
  fi

  if ask_yes_no "$(tr_text "Настроить отправку backup в Telegram сейчас?" "Configure backup send to Telegram now?")" "n"; then
    configure_backup_send="1"
  fi

  if [[ "$configure_backup_send" == "1" ]]; then
    backup_send_enabled="$(bedolaga_prompt_value "$(tr_text "BACKUP_SEND_ENABLED (true/false)" "BACKUP_SEND_ENABLED (true/false)")" "$backup_send_enabled" bedolaga_validate_bool "$(tr_text "Допустимо только true или false." "Only true or false is allowed.")")"
    [[ "$backup_send_enabled" == "__PBM_BACK__" ]] && return 1

    backup_send_chat_id="$(bedolaga_prompt_value "$(tr_text "BACKUP_SEND_CHAT_ID (формат: -100..., пример: -1001234567890)" "BACKUP_SEND_CHAT_ID (format: -100..., example: -1001234567890)")" "$backup_send_chat_id" bedolaga_validate_optional_chat_id "$(tr_text "Введите числовой chat_id (например -100...) или оставьте пусто." "Enter numeric chat_id (e.g. -100...) or leave empty.")")"
    [[ "$backup_send_chat_id" == "__PBM_BACK__" ]] && return 1

    backup_send_topic_id="$(bedolaga_prompt_value "$(tr_text "BACKUP_SEND_TOPIC_ID (опционально, пример: 8)" "BACKUP_SEND_TOPIC_ID (optional, example: 8)")" "$backup_send_topic_id" bedolaga_validate_optional_int "$(tr_text "Введите числовой topic_id или оставьте пусто." "Enter numeric topic_id or leave empty.")")"
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
  bedolaga_write_bot_compose_override "$bot_dir"
  bedolaga_write_cabinet_compose_override "$cabinet_dir"
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
  bedolaga_sanitize_bot_optional_int_env "${bot_dir}/.env"

  ( cd "$bot_dir" && $SUDO docker compose up -d --build ) || return 1

  if ! bedolaga_sync_cabinet_env "$cabinet_dir" "$bot_username" "$cabinet_port"; then
    return 1
  fi

  ( cd "$cabinet_dir" && $SUDO docker compose up -d --build ) || return 1
  bedolaga_repair_shared_network_if_needed || return 1

  if ! bedolaga_apply_caddy_block "$hooks_domain" "$cabinet_domain" "$api_domain" "$cabinet_port" "$replace_caddy_config"; then
    return 1
  fi
  if ! bedolaga_verify_cabinet_ws_route "$cabinet_domain"; then
    return 1
  fi
  if ! bedolaga_post_deploy_health_check "$cabinet_port"; then
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Bedolaga stack установлен и запущен." "Bedolaga stack installed and started.")"
  return 0
}

run_bedolaga_stack_install_flow() {
  run_bedolaga_stack_install_with_repos "$BEDOLAGA_BOT_REPO_DEFAULT" "$BEDOLAGA_CABINET_REPO_DEFAULT"
}

run_bedolaga_stack_install_fork_flow() {
  local bot_repo="$BEDOLAGA_BOT_REPO_FORK_DEFAULT"
  local cabinet_repo="$BEDOLAGA_CABINET_REPO_FORK_DEFAULT"

  bedolaga_autodetect_fork_repo_urls
  if bedolaga_validate_git_repo_url "${BEDOLAGA_BOT_REPO_LAST_CUSTOM:-}"; then
    bot_repo="${BEDOLAGA_BOT_REPO_LAST_CUSTOM}"
  fi
  if bedolaga_validate_git_repo_url "${BEDOLAGA_CABINET_REPO_LAST_CUSTOM:-}"; then
    cabinet_repo="${BEDOLAGA_CABINET_REPO_LAST_CUSTOM}"
  fi

  BEDOLAGA_BOT_REPO_LAST_CUSTOM="$bot_repo"
  BEDOLAGA_CABINET_REPO_LAST_CUSTOM="$cabinet_repo"
  draw_subheader "$(tr_text "Bedolaga: автоустановка из форка PEDZEO (бот + кабинет + Caddy)" "Bedolaga: auto install from PEDZEO fork (bot + cabinet + Caddy)")"
  paint "$CLR_MUTED" "$(tr_text "Скрипт сам использует форк-репозитории PEDZEO." "Script automatically uses PEDZEO fork repositories.")"
  paint "$CLR_MUTED" "  bot: ${bot_repo}"
  paint "$CLR_MUTED" "  cabinet: ${cabinet_repo}"
  run_bedolaga_stack_install_with_repos "$bot_repo" "$cabinet_repo"
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

  hooks_domain="$(bedolaga_prompt_value "$(tr_text "Домен webhook/API (как в установке)" "Webhook/API domain (same as install)")" "" bedolaga_validate_domain "$(tr_text "Введите корректный домен (без https://)." "Enter a valid domain (without https://).")")"
  [[ "$hooks_domain" == "__PBM_BACK__" ]] && return 1

  cabinet_domain="$(bedolaga_prompt_value "$(tr_text "Домен кабинета (как в установке)" "Cabinet domain (same as install)")" "" bedolaga_validate_domain "$(tr_text "Введите корректный домен кабинета (без https://)." "Enter a valid cabinet domain (without https://).")")"
  [[ "$cabinet_domain" == "__PBM_BACK__" ]] && return 1

  api_domain="$(bedolaga_prompt_value "$(tr_text "Домен API (как в установке)" "API domain (same as install)")" "" bedolaga_validate_domain "$(tr_text "Введите корректный домен API (без https://)." "Enter a valid API domain (without https://).")")"
  [[ "$api_domain" == "__PBM_BACK__" ]] && return 1

  cabinet_port="$(ask_value "$(tr_text "Локальный порт cabinet (для Caddy reverse proxy)" "Local cabinet port (for Caddy reverse proxy)")" "3020")"
  [[ "$cabinet_port" == "__PBM_BACK__" ]] && return 1
  if [[ ! "$cabinet_port" =~ ^[0-9]+$ ]]; then
    paint "$CLR_DANGER" "$(tr_text "Порт cabinet должен быть числом." "Cabinet port must be numeric.")"
    return 1
  fi

  bedolaga_clone_or_update_repo "$BEDOLAGA_BOT_REPO_DEFAULT" "$bot_dir" || return 1
  bedolaga_clone_or_update_repo "$BEDOLAGA_CABINET_REPO_DEFAULT" "$cabinet_dir" || return 1
  bedolaga_write_bot_compose_override "$bot_dir"
  bedolaga_write_cabinet_compose_override "$cabinet_dir"

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
  bedolaga_repair_shared_network_if_needed || return 1

  if ask_yes_no "$(tr_text "Заменить весь Caddyfile на шаблон Bedolaga? (иначе обновится только автоген-блок)" "Replace full Caddyfile with Bedolaga template? (otherwise only autogen block is updated)")" "n"; then
    replace_caddy_config="1"
  fi
  if ! bedolaga_apply_caddy_block "$hooks_domain" "$cabinet_domain" "$api_domain" "$cabinet_port" "$replace_caddy_config"; then
    return 1
  fi
  if ! bedolaga_verify_cabinet_ws_route "$cabinet_domain"; then
    return 1
  fi
  if ! bedolaga_post_deploy_health_check "$cabinet_port"; then
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Bedolaga stack обновлен." "Bedolaga stack updated.")"
  return 0
}
