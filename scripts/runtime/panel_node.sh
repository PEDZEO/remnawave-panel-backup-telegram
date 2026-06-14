#!/usr/bin/env bash
# update: panel/node install and update operations for manager.sh

REMNAWAVE_LAST_PANEL_DOMAIN=""
REMNAWAVE_LAST_SUB_DOMAIN=""
REMNAWAVE_LAST_PANEL_PORT=""
REMNAWAVE_LAST_SUB_PORT=""
REMNAWAVE_LAST_SUB_MODE=""
REMNAWAVE_LAST_API_TOKEN=""

remnawave_env_value() {
  local env_file="$1"
  local key="$2"

  [[ -f "$env_file" ]] || return 0
  awk -v key="$key" '
    index($0, key "=") == 1 {
      value = substr($0, length(key) + 2)
      sub(/\r$/, "", value)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
      exit
    }
  ' "$env_file" 2>/dev/null || true
}

remnawave_domain_from_url() {
  local value="${1:-}"

  value="${value#http://}"
  value="${value#https://}"
  value="${value%%/*}"
  printf '%s' "$value"
}

load_panel_install_defaults() {
  local panel_dir="$1"
  local env_file="${panel_dir}/.env"
  local value=""

  value="$(remnawave_env_value "$env_file" "FRONT_END_DOMAIN")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_PANEL_DOMAIN="$value"
  value="$(remnawave_env_value "$env_file" "SUB_PUBLIC_DOMAIN")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_SUB_DOMAIN="$value"
  value="$(remnawave_env_value "$env_file" "APP_PORT")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_PANEL_PORT="$value"
}

load_subscription_install_defaults() {
  local sub_dir="$1"
  local env_file="${sub_dir}/.env"
  local value=""

  value="$(remnawave_env_value "$env_file" "APP_PORT")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_SUB_PORT="$value"
  value="$(remnawave_env_value "$env_file" "PBM_SUBSCRIPTION_DOMAIN")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_SUB_DOMAIN="$value"
  value="$(remnawave_env_value "$env_file" "REMNAWAVE_PANEL_URL")"
  value="$(remnawave_domain_from_url "$value")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_PANEL_DOMAIN="$value"
  value="$(remnawave_env_value "$env_file" "REMNAWAVE_API_TOKEN")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_API_TOKEN="$value"
  value="$(remnawave_env_value "$env_file" "PBM_SUBSCRIPTION_MODE")"
  [[ -n "$value" ]] && REMNAWAVE_LAST_SUB_MODE="$value"
}

ensure_docker_available() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Docker не найден." "Docker is not installed.")"
  if ! ask_yes_no "$(tr_text "Установить Docker сейчас?" "Install Docker now?")" "y"; then
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Устанавливаю Docker..." "Installing Docker...")"
  curl -fsSL https://get.docker.com -o "$TMP_DIR/get-docker.sh"
  $SUDO sh "$TMP_DIR/get-docker.sh"
  rm -f "$TMP_DIR/get-docker.sh"

  if ! command -v docker >/dev/null 2>&1; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось установить Docker." "Failed to install Docker.")"
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Docker установлен." "Docker installed.")"
  return 0
}

ensure_openssl_available() {
  if command -v openssl >/dev/null 2>&1; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "openssl не найден." "openssl is not installed.")"
  if ! ask_yes_no "$(tr_text "Установить openssl сейчас?" "Install openssl now?")" "y"; then
    return 1
  fi

  if ! install_package "openssl" >/dev/null 2>&1; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось установить openssl автоматически." "Failed to install openssl automatically.")"
    return 1
  fi

  command -v openssl >/dev/null 2>&1
}

generate_hex() {
  local size="$1"
  openssl rand -hex "$size"
}

generate_alpha_login() {
  tr -dc 'a-zA-Z' < /dev/urandom | head -c 15
}

setup_remnanode_logs() {
  paint "$CLR_ACCENT" "$(tr_text "Подготавливаю логи RemnaNode" "Preparing RemnaNode logs")"
  $SUDO mkdir -p /var/log/remnanode
  $SUDO chown 1000:1000 /var/log/remnanode >/dev/null 2>&1 || true
  $SUDO chmod 775 /var/log/remnanode

  if ! command -v logrotate >/dev/null 2>&1; then
    if ! install_package "logrotate" >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Не удалось установить logrotate автоматически." "Failed to install logrotate automatically.")"
    fi
  fi

  $SUDO bash -c "cat > /etc/logrotate.d/remnanode <<ROTATE
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
ROTATE"
}

write_panel_templates() {
  local target_dir="$1"
  local panel_domain="$2"
  local sub_domain="$3"
  local panel_port="$4"
  local db_user="$5"
  local db_password="$6"
  local jwt_auth_secret="$7"
  local jwt_api_tokens_secret="$8"
  local metrics_user="$9"
  local metrics_pass="${10}"
  local webhook_secret_header="${11}"

  $SUDO install -d -m 755 "$target_dir"

  $SUDO bash -c "cat > '${target_dir}/.env' <<ENV
APP_PORT=${panel_port}
METRICS_PORT=3001
API_INSTANCES=1
DATABASE_URL=\"postgresql://${db_user}:${db_password}@remnawave-db:5432/postgres\"
REDIS_HOST=remnawave-redis
REDIS_PORT=6379
JWT_AUTH_SECRET=${jwt_auth_secret}
JWT_API_TOKENS_SECRET=${jwt_api_tokens_secret}
IS_TELEGRAM_NOTIFICATIONS_ENABLED=false
TELEGRAM_BOT_TOKEN=change_me
TELEGRAM_NOTIFY_USERS_CHAT_ID=change_me
TELEGRAM_NOTIFY_NODES_CHAT_ID=change_me
TELEGRAM_NOTIFY_CRM_CHAT_ID=change_me
TELEGRAM_NOTIFY_USERS_THREAD_ID=
TELEGRAM_NOTIFY_NODES_THREAD_ID=
TELEGRAM_NOTIFY_CRM_THREAD_ID=
FRONT_END_DOMAIN=${panel_domain}
SUB_PUBLIC_DOMAIN=${sub_domain}
SWAGGER_PATH=/docs
SCALAR_PATH=/scalar
IS_DOCS_ENABLED=false
METRICS_USER=${metrics_user}
METRICS_PASS=${metrics_pass}
WEBHOOK_ENABLED=false
WEBHOOK_URL=https://your-webhook-url.com/endpoint
WEBHOOK_SECRET_HEADER=${webhook_secret_header}
BANDWIDTH_USAGE_NOTIFICATIONS_ENABLED=false
BANDWIDTH_USAGE_NOTIFICATIONS_THRESHOLD=[60, 80]
NOT_CONNECTED_USERS_NOTIFICATIONS_ENABLED=false
NOT_CONNECTED_USERS_NOTIFICATIONS_AFTER_HOURS=[6, 24, 48]
POSTGRES_USER=${db_user}
POSTGRES_PASSWORD=${db_password}
POSTGRES_DB=postgres
ENV"

  $SUDO bash -c "cat > '${target_dir}/docker-compose.yml' <<'COMPOSE'
x-common: &common
  ulimits:
    nofile:
      soft: 1048576
      hard: 1048576
  restart: always
  networks:
    - remnawave-network

x-logging: &logging
  logging:
    driver: json-file
    options:
      max-size: 100m
      max-file: 5

x-env: &env
  env_file: .env

services:
  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    hostname: remnawave
    <<: [*common, *logging, *env]
    ports:
      - 127.0.0.1:\${APP_PORT}:\${APP_PORT}
      - 127.0.0.1:3001:\${METRICS_PORT:-3001}
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:\${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy

  remnawave-db:
    image: postgres:17.6
    container_name: remnawave-db
    hostname: remnawave-db
    <<: [*common, *logging, *env]
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
      - TZ=UTC
    ports:
      - 127.0.0.1:6767:5432
    volumes:
      - remnawave-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U \$\${POSTGRES_USER} -d \$\${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3

  remnawave-redis:
    image: valkey/valkey:8.1-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    <<: [*common, *logging]
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory-policy noeviction
      --loglevel warning
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 3s
      retries: 3

networks:
  remnawave-network:
    name: remnawave-network
    external: true

volumes:
  remnawave-db-data:
    name: remnawave-db-data
    driver: local
    external: false
COMPOSE"

  $SUDO chmod 600 "${target_dir}/.env"
  $SUDO chmod 644 "${target_dir}/docker-compose.yml"
}

write_node_template() {
  local target_dir="$1"
  local node_port="$2"
  local secret_key="$3"

  $SUDO install -d -m 755 "$target_dir"
  $SUDO bash -c "cat > '${target_dir}/docker-compose.yml' <<COMPOSE
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    environment:
      - NODE_PORT=${node_port}
      - SECRET_KEY=${secret_key}
    volumes:
      - /var/log/remnanode:/var/log/remnanode
COMPOSE"
  $SUDO chmod 644 "${target_dir}/docker-compose.yml"
}

compose_stack_up() {
  local target_dir="$1"
  if [[ ! -f "${target_dir}/docker-compose.yml" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не найден docker-compose.yml" "docker-compose.yml not found"): ${target_dir}"
    return 1
  fi

  (
    cd "$target_dir"
    $SUDO docker compose up -d
  )
}

compose_stack_update() {
  local target_dir="$1"
  if [[ ! -f "${target_dir}/docker-compose.yml" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не найден docker-compose.yml" "docker-compose.yml not found"): ${target_dir}"
    return 1
  fi

  (
    cd "$target_dir"
    $SUDO docker compose pull
    $SUDO docker compose down
    $SUDO docker compose up -d
  )
}

ensure_remnawave_shared_network() {
  if ! $SUDO docker network inspect remnawave-network >/dev/null 2>&1; then
    paint "$CLR_ACCENT" "$(tr_text "Создаю общую Docker сеть remnawave-network" "Creating shared Docker network remnawave-network")"
    if ! $SUDO docker network create remnawave-network >/dev/null 2>&1; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось создать сеть remnawave-network." "Failed to create remnawave-network.")"
      return 1
    fi
  fi
  return 0
}

write_panel_caddy_templates() {
  local caddy_dir="$1"
  local panel_domain="$2"
  local sub_domain="$3"
  local panel_port="$4"
  local sub_port="$5"

  $SUDO install -d -m 755 "$caddy_dir"

  $SUDO bash -c "cat > '${caddy_dir}/Caddyfile' <<CADDY
{
  admin off
}

${panel_domain} {
  encode gzip zstd
  reverse_proxy remnawave:${panel_port}
}

${sub_domain} {
  encode gzip zstd
  reverse_proxy remnawave-subscription-page:${sub_port}
}
CADDY"

  $SUDO bash -c "cat > '${caddy_dir}/docker-compose.yml' <<'COMPOSE'
services:
  remnawave-caddy:
    image: caddy:2-alpine
    container_name: remnawave-caddy
    hostname: remnawave-caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - remnawave-network

networks:
  remnawave-network:
    name: remnawave-network
    external: true

volumes:
  caddy_data:
  caddy_config:
COMPOSE"

  $SUDO chmod 644 "${caddy_dir}/Caddyfile" "${caddy_dir}/docker-compose.yml"
}

run_panel_install_flow() {
  local panel_dir=""
  local panel_domain=""
  local sub_domain=""
  local panel_port=""
  local reinstall_choice=""
  local clean_data=""
  local backup_suffix=""
  local db_user=""
  local db_password=""
  local jwt_auth_secret=""
  local jwt_api_tokens_secret=""
  local metrics_user=""
  local metrics_pass=""
  local webhook_secret_header=""
  local panel_env_file=""

  load_existing_env_defaults
  draw_header "$(tr_text "Установка панели Remnawave" "Install Remnawave panel")"
  panel_dir="$(ask_value "$(tr_text "Путь установки панели" "Panel installation path")" "${REMNAWAVE_DIR:-/opt/remnawave}")"
  [[ "$panel_dir" == "__PBM_BACK__" ]] && return 1
  if ! validate_project_path_or_warn "REMNAWAVE_DIR" "$panel_dir"; then
    return 1
  fi
  REMNAWAVE_DIR="$panel_dir"
  panel_env_file="${panel_dir}/.env"
  load_panel_install_defaults "$panel_dir"

  if [[ -f "${panel_dir}/docker-compose.yml" || -f "$panel_env_file" ]]; then
    paint "$CLR_WARN" "$(tr_text "Обнаружена существующая установка панели." "Existing panel installation detected.")"
    paint "$CLR_MUTED" "  $(tr_text "Путь:" "Path:") ${panel_dir}"
    paint "$CLR_MUTED" "  $(tr_text "Домен панели:" "Panel domain:") ${REMNAWAVE_LAST_PANEL_DOMAIN:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Домен подписки:" "Subscription domain:") ${REMNAWAVE_LAST_SUB_DOMAIN:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Порт панели:" "Panel port:") ${REMNAWAVE_LAST_PANEL_PORT:-3000}"
    if ! ask_yes_no "$(tr_text "Точно переустановить панель? Текущие значения будут предложены по умолчанию." "Reinstall panel? Current values will be offered as defaults.")" "n"; then
      paint "$CLR_WARN" "$(tr_text "Переустановка отменена. Текущая панель не изменена." "Reinstall cancelled. Current panel was not changed.")"
      return 2
    fi
    reinstall_choice="1"
    paint "$CLR_MUTED" "$(tr_text "Дальше можно нажимать Enter, чтобы оставить значение в скобках, или ввести свое." "Next prompts: press Enter to keep the value in brackets, or type a new one.")"

    if ask_yes_no "$(tr_text "Остановить контейнеры перед переустановкой?" "Stop containers before reinstall?")" "y"; then
      if ! (cd "$panel_dir" && $SUDO docker compose down); then
        paint "$CLR_DANGER" "$(tr_text "Не удалось корректно остановить контейнеры." "Failed to stop containers cleanly.")"
        if ! ask_yes_no "$(tr_text "Продолжить переустановку без успешной остановки контейнеров?" "Continue reinstall without successful container stop?")" "n"; then
          paint "$CLR_WARN" "$(tr_text "Установка отменена пользователем." "Installation cancelled by user.")"
          return 1
        fi
      fi
    fi

    if ask_yes_no "$(tr_text "Удалить Docker volumes панели (ПОЛНАЯ ОЧИСТКА ДАННЫХ)?" "Remove panel Docker volumes (FULL DATA WIPE)?")" "n"; then
      clean_data="1"
    fi
  fi

  while true; do
    panel_domain="$(ask_value "$(tr_text "Домен панели (без http/https)" "Panel domain (without http/https)")" "${REMNAWAVE_LAST_PANEL_DOMAIN}")"
    [[ "$panel_domain" == "__PBM_BACK__" ]] && return 1
    validate_domain_or_warn "FRONT_END_DOMAIN" "$panel_domain" && break
  done

  while true; do
    sub_domain="$(ask_value "$(tr_text "Домен подписки (без http/https)" "Subscription domain (without http/https)")" "${REMNAWAVE_LAST_SUB_DOMAIN}")"
    [[ "$sub_domain" == "__PBM_BACK__" ]] && return 1
    validate_domain_or_warn "SUB_PUBLIC_DOMAIN" "$sub_domain" && break
  done

  while true; do
    panel_port="$(ask_value "$(tr_text "Порт панели" "Panel port")" "${REMNAWAVE_LAST_PANEL_PORT:-3000}")"
    [[ "$panel_port" == "__PBM_BACK__" ]] && return 1
    validate_tcp_port_or_warn "APP_PORT" "$panel_port" && break
  done

  if ! ensure_docker_available; then
    return 1
  fi
  if ! ensure_openssl_available; then
    return 1
  fi

  if [[ -f "$panel_env_file" && -z "$clean_data" ]]; then
    db_user="$(remnawave_env_value "$panel_env_file" "POSTGRES_USER")"
    db_password="$(remnawave_env_value "$panel_env_file" "POSTGRES_PASSWORD")"
    jwt_auth_secret="$(remnawave_env_value "$panel_env_file" "JWT_AUTH_SECRET")"
    jwt_api_tokens_secret="$(remnawave_env_value "$panel_env_file" "JWT_API_TOKENS_SECRET")"
    metrics_user="$(remnawave_env_value "$panel_env_file" "METRICS_USER")"
    metrics_pass="$(remnawave_env_value "$panel_env_file" "METRICS_PASS")"
    webhook_secret_header="$(remnawave_env_value "$panel_env_file" "WEBHOOK_SECRET_HEADER")"
  fi
  [[ -n "$db_user" ]] || db_user="$(generate_alpha_login)"
  [[ -n "$db_password" ]] || db_password="$(generate_hex 24)"
  [[ -n "$jwt_auth_secret" ]] || jwt_auth_secret="$(generate_hex 64)"
  [[ -n "$jwt_api_tokens_secret" ]] || jwt_api_tokens_secret="$(generate_hex 64)"
  [[ -n "$metrics_user" ]] || metrics_user="$(generate_alpha_login)"
  [[ -n "$metrics_pass" ]] || metrics_pass="$(generate_hex 64)"
  [[ -n "$webhook_secret_header" ]] || webhook_secret_header="$(generate_hex 64)"

  paint "$CLR_ACCENT" "$(tr_text "Генерирую конфигурацию панели" "Generating panel configuration")"
  if [[ -n "$reinstall_choice" ]]; then
    backup_suffix="$(date -u +%Y%m%d-%H%M%S)"
    if [[ -f "${panel_dir}/.env" ]]; then
      if ! $SUDO cp "${panel_dir}/.env" "${panel_dir}/.env.bak-${backup_suffix}"; then
        paint "$CLR_WARN" "$(tr_text "Не удалось создать backup .env перед переустановкой." "Failed to create .env backup before reinstall.")"
      fi
    fi
    if [[ -f "${panel_dir}/docker-compose.yml" ]]; then
      if ! $SUDO cp "${panel_dir}/docker-compose.yml" "${panel_dir}/docker-compose.yml.bak-${backup_suffix}"; then
        paint "$CLR_WARN" "$(tr_text "Не удалось создать backup docker-compose.yml перед переустановкой." "Failed to create docker-compose.yml backup before reinstall.")"
      fi
    fi
  fi

  write_panel_templates "$panel_dir" "$panel_domain" "$sub_domain" "$panel_port" "$db_user" "$db_password" "$jwt_auth_secret" "$jwt_api_tokens_secret" "$metrics_user" "$metrics_pass" "$webhook_secret_header"
  REMNAWAVE_DIR="$panel_dir"
  REMNAWAVE_LAST_PANEL_DOMAIN="$panel_domain"
  REMNAWAVE_LAST_SUB_DOMAIN="$sub_domain"
  REMNAWAVE_LAST_PANEL_PORT="$panel_port"

  if [[ -n "$clean_data" ]]; then
    paint "$CLR_WARN" "$(tr_text "Удаляю volumes панели" "Removing panel volumes")"
    if ! $SUDO docker volume rm remnawave-db-data remnawave-redis-data >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Часть volumes не удалена (возможно, уже отсутствуют)." "Some volumes were not removed (possibly already absent).")"
    fi
  fi

  paint "$CLR_ACCENT" "$(tr_text "Запускаю контейнеры панели" "Starting panel containers")"
  if ! ensure_remnawave_shared_network; then
    return 1
  fi
  if compose_stack_up "$panel_dir"; then
    paint "$CLR_OK" "$(tr_text "Панель установлена/обновлена." "Panel installed/updated.")"
    paint "$CLR_MUTED" "$(tr_text "Путь:" "Path:") ${panel_dir}"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось запустить контейнеры панели." "Failed to start panel containers.")"
  return 1
}

run_panel_update_flow() {
  local panel_dir=""
  local env_file=""
  draw_header "$(tr_text "Обновление панели Remnawave" "Update Remnawave panel")"
  panel_dir="$(ask_value "$(tr_text "Путь к панели" "Panel path")" "/opt/remnawave")"
  [[ "$panel_dir" == "__PBM_BACK__" ]] && return 1
  if ! validate_project_path_or_warn "REMNAWAVE_DIR" "$panel_dir"; then
    return 1
  fi

  REMNAWAVE_DIR="$panel_dir"
  env_file="${panel_dir}/.env"
  if [[ -f "$env_file" ]]; then
    REMNAWAVE_LAST_PANEL_DOMAIN="$(awk -F= '/^FRONT_END_DOMAIN=/{print $2; exit}' "$env_file")"
    REMNAWAVE_LAST_SUB_DOMAIN="$(awk -F= '/^SUB_PUBLIC_DOMAIN=/{print $2; exit}' "$env_file")"
    REMNAWAVE_LAST_PANEL_PORT="$(awk -F= '/^APP_PORT=/{print $2; exit}' "$env_file")"
  fi

  if ! ensure_docker_available; then
    return 1
  fi
  if ! ensure_remnawave_shared_network; then
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Обновляю панель" "Updating panel")"
  if compose_stack_update "$panel_dir"; then
    paint "$CLR_OK" "$(tr_text "Панель обновлена." "Panel updated.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Ошибка обновления панели." "Panel update failed.")"
  return 1
}

run_panel_caddy_install_flow() {
  local panel_dir=""
  local caddy_dir=""
  local panel_domain=""
  local sub_domain=""
  local panel_port=""
  local sub_port=""
  local backup_suffix=""
  local panel_env_file=""
  local sub_env_file=""

  if [[ "${AUTO_PANEL_CADDY:-0}" == "1" ]]; then
    panel_dir="${REMNAWAVE_DIR:-/opt/remnawave}"
    caddy_dir="${panel_dir}/caddy"
    panel_domain="${REMNAWAVE_LAST_PANEL_DOMAIN}"
    sub_domain="${REMNAWAVE_LAST_SUB_DOMAIN}"
    panel_port="${REMNAWAVE_LAST_PANEL_PORT:-3000}"
    sub_port="${REMNAWAVE_LAST_SUB_PORT:-3010}"
  else
    panel_dir="$(ask_value "$(tr_text "Путь к панели Remnawave" "Remnawave panel path")" "${REMNAWAVE_DIR:-/opt/remnawave}")"
    [[ "$panel_dir" == "__PBM_BACK__" ]] && return 1

    panel_env_file="${panel_dir}/.env"
    sub_env_file="${panel_dir}/subscription/.env"
    if [[ -f "$panel_env_file" ]]; then
      [[ -z "$REMNAWAVE_LAST_PANEL_DOMAIN" ]] && REMNAWAVE_LAST_PANEL_DOMAIN="$(awk -F= '/^FRONT_END_DOMAIN=/{print $2; exit}' "$panel_env_file")"
      [[ -z "$REMNAWAVE_LAST_SUB_DOMAIN" ]] && REMNAWAVE_LAST_SUB_DOMAIN="$(awk -F= '/^SUB_PUBLIC_DOMAIN=/{print $2; exit}' "$panel_env_file")"
      [[ -z "$REMNAWAVE_LAST_PANEL_PORT" ]] && REMNAWAVE_LAST_PANEL_PORT="$(awk -F= '/^APP_PORT=/{print $2; exit}' "$panel_env_file")"
    fi
    if [[ -f "$sub_env_file" ]]; then
      [[ -z "$REMNAWAVE_LAST_SUB_PORT" ]] && REMNAWAVE_LAST_SUB_PORT="$(awk -F= '/^APP_PORT=/{print $2; exit}' "$sub_env_file")"
    fi

    caddy_dir="$(ask_value "$(tr_text "Путь установки Caddy для панели" "Caddy installation path for panel")" "${panel_dir}/caddy")"
    [[ "$caddy_dir" == "__PBM_BACK__" ]] && return 1

    panel_domain="$(ask_value "$(tr_text "Домен панели (без http/https)" "Panel domain (without http/https)")" "${REMNAWAVE_LAST_PANEL_DOMAIN}")"
    [[ "$panel_domain" == "__PBM_BACK__" ]] && return 1
    sub_domain="$(ask_value "$(tr_text "Домен подписки (без http/https)" "Subscription domain (without http/https)")" "${REMNAWAVE_LAST_SUB_DOMAIN}")"
    [[ "$sub_domain" == "__PBM_BACK__" ]] && return 1
    panel_port="$(ask_value "$(tr_text "Локальный порт панели" "Panel local port")" "${REMNAWAVE_LAST_PANEL_PORT:-3000}")"
    [[ "$panel_port" == "__PBM_BACK__" ]] && return 1
    sub_port="$(ask_value "$(tr_text "Локальный порт subscription" "Subscription local port")" "${REMNAWAVE_LAST_SUB_PORT:-3010}")"
    [[ "$sub_port" == "__PBM_BACK__" ]] && return 1
  fi

  if ! validate_project_path_or_warn "REMNAWAVE_DIR" "$panel_dir"; then
    return 1
  fi
  if ! validate_project_path_or_warn "PANEL_CADDY_DIR" "$caddy_dir"; then
    return 1
  fi
  if ! validate_domain_or_warn "FRONT_END_DOMAIN" "$panel_domain"; then
    return 1
  fi
  if ! validate_domain_or_warn "SUB_PUBLIC_DOMAIN" "$sub_domain"; then
    return 1
  fi
  if ! validate_tcp_port_or_warn "APP_PORT" "$panel_port"; then
    return 1
  fi
  if ! validate_tcp_port_or_warn "SUBSCRIPTION_PORT" "$sub_port"; then
    return 1
  fi

  if ! ensure_docker_available; then
    return 1
  fi
  if ! ensure_remnawave_shared_network; then
    return 1
  fi

  if [[ -f "${caddy_dir}/Caddyfile" || -f "${caddy_dir}/docker-compose.yml" ]]; then
    backup_suffix="$(date -u +%Y%m%d-%H%M%S)"
    $SUDO cp "${caddy_dir}/Caddyfile" "${caddy_dir}/Caddyfile.bak-${backup_suffix}" >/dev/null 2>&1 || true
    $SUDO cp "${caddy_dir}/docker-compose.yml" "${caddy_dir}/docker-compose.yml.bak-${backup_suffix}" >/dev/null 2>&1 || true
  fi

  paint "$CLR_ACCENT" "$(tr_text "Генерирую конфигурацию Caddy для панели" "Generating Caddy configuration for panel")"
  write_panel_caddy_templates "$caddy_dir" "$panel_domain" "$sub_domain" "$panel_port" "$sub_port"

  paint "$CLR_ACCENT" "$(tr_text "Запускаю Caddy для панели" "Starting panel Caddy")"
  if compose_stack_up "$caddy_dir"; then
    paint "$CLR_OK" "$(tr_text "Caddy для панели установлен/обновлен." "Panel Caddy installed/updated.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось запустить Caddy для панели." "Failed to start panel Caddy.")"
  return 1
}

run_panel_caddy_update_flow() {
  local panel_dir=""
  local caddy_dir=""

  if [[ "${AUTO_PANEL_CADDY:-0}" == "1" ]]; then
    panel_dir="${REMNAWAVE_DIR:-/opt/remnawave}"
    caddy_dir="${panel_dir}/caddy"
  else
    panel_dir="$(ask_value "$(tr_text "Путь к панели Remnawave" "Remnawave panel path")" "${REMNAWAVE_DIR:-/opt/remnawave}")"
    [[ "$panel_dir" == "__PBM_BACK__" ]] && return 1
    caddy_dir="$(ask_value "$(tr_text "Путь к Caddy панели" "Panel Caddy path")" "${panel_dir}/caddy")"
    [[ "$caddy_dir" == "__PBM_BACK__" ]] && return 1
  fi
  if ! validate_project_path_or_warn "REMNAWAVE_DIR" "$panel_dir"; then
    return 1
  fi
  if ! validate_project_path_or_warn "PANEL_CADDY_DIR" "$caddy_dir"; then
    return 1
  fi

  if [[ ! -f "${caddy_dir}/docker-compose.yml" ]]; then
    paint "$CLR_WARN" "$(tr_text "Caddy для панели не найден, запускаю установку." "Panel Caddy not found, starting install flow.")"
    run_panel_caddy_install_flow
    return $?
  fi

  if ! ensure_docker_available; then
    return 1
  fi
  if ! ensure_remnawave_shared_network; then
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Обновляю Caddy для панели" "Updating panel Caddy")"
  if compose_stack_update "$caddy_dir"; then
    paint "$CLR_OK" "$(tr_text "Caddy для панели обновлен." "Panel Caddy updated.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Ошибка обновления Caddy для панели." "Panel Caddy update failed.")"
  return 1
}

run_node_install_flow() {
  local node_dir=""
  local node_port=""
  local secret_key=""

  draw_header "$(tr_text "Установка ноды RemnaNode" "Install RemnaNode")"
  node_dir="$(ask_value "$(tr_text "Путь установки ноды" "Node installation path")" "/opt/remnanode")"
  [[ "$node_dir" == "__PBM_BACK__" ]] && return 1
  if ! validate_project_path_or_warn "REMNANODE_DIR" "$node_dir"; then
    return 1
  fi

  while true; do
    node_port="$(ask_value "$(tr_text "Порт ноды" "Node port")" "3001")"
    [[ "$node_port" == "__PBM_BACK__" ]] && return 1
    validate_tcp_port_or_warn "NODE_PORT" "$node_port" && break
  done

  while true; do
    secret_key="$(ask_value "$(tr_text "SECRET_KEY (обязательно)" "SECRET_KEY (required)")" "")"
    [[ "$secret_key" == "__PBM_BACK__" ]] && return 1
    [[ -n "$secret_key" ]] && break
    paint "$CLR_WARN" "$(tr_text "SECRET_KEY не может быть пустым." "SECRET_KEY cannot be empty.")"
  done

  if ! ensure_docker_available; then
    return 1
  fi

  setup_remnanode_logs
  paint "$CLR_ACCENT" "$(tr_text "Генерирую конфигурацию ноды" "Generating node configuration")"
  write_node_template "$node_dir" "$node_port" "$secret_key"

  paint "$CLR_ACCENT" "$(tr_text "Запускаю контейнер ноды" "Starting node container")"
  if compose_stack_up "$node_dir"; then
    paint "$CLR_OK" "$(tr_text "Нода установлена/обновлена." "Node installed/updated.")"
    paint "$CLR_MUTED" "$(tr_text "Путь:" "Path:") ${node_dir}"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось запустить контейнер ноды." "Failed to start node container.")"
  return 1
}

run_node_update_flow() {
  local node_dir=""
  draw_header "$(tr_text "Обновление ноды RemnaNode" "Update RemnaNode")"
  node_dir="$(ask_value "$(tr_text "Путь к ноде" "Node path")" "/opt/remnanode")"
  [[ "$node_dir" == "__PBM_BACK__" ]] && return 1
  if ! validate_project_path_or_warn "REMNANODE_DIR" "$node_dir"; then
    return 1
  fi

  if ! ensure_docker_available; then
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Обновляю ноду" "Updating node")"
  if compose_stack_update "$node_dir"; then
    paint "$CLR_OK" "$(tr_text "Нода обновлена." "Node updated.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Ошибка обновления ноды." "Node update failed.")"
  return 1
}

write_subscription_template() {
  local target_dir="$1"
  local panel_domain="$2"
  local sub_port="$3"
  local api_token="$4"
  local deploy_mode="${5:-same-server}"
  local sub_domain="${6:-}"

  $SUDO install -d -m 755 "$target_dir"
  $SUDO bash -c "cat > '${target_dir}/.env' <<ENV
APP_PORT=${sub_port}
REMNAWAVE_PANEL_URL=https://${panel_domain}
REMNAWAVE_API_TOKEN=${api_token}
PBM_SUBSCRIPTION_MODE=${deploy_mode}
PBM_SUBSCRIPTION_DOMAIN=${sub_domain}
ENV"

  if [[ "$deploy_mode" == "same-server" ]]; then
    $SUDO bash -c "cat > '${target_dir}/docker-compose.yml' <<COMPOSE
services:
  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    env_file:
      - .env
    networks:
      - remnawave-network
    ports:
      - 127.0.0.1:${sub_port}:${sub_port}

networks:
  remnawave-network:
    name: remnawave-network
    external: true
COMPOSE"
  else
    $SUDO bash -c "cat > '${target_dir}/docker-compose.yml' <<COMPOSE
services:
  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    env_file:
      - .env
    ports:
      - 127.0.0.1:${sub_port}:${sub_port}
COMPOSE"
  fi

  $SUDO chmod 600 "${target_dir}/.env"
  $SUDO chmod 644 "${target_dir}/docker-compose.yml"
}

write_subscription_caddy_template() {
  local caddy_dir="$1"
  local sub_domain="$2"
  local sub_port="$3"

  $SUDO install -d -m 755 "$caddy_dir"
  $SUDO bash -c "cat > '${caddy_dir}/Caddyfile' <<CADDY
{
  admin off
}

${sub_domain} {
  encode gzip zstd
  reverse_proxy 127.0.0.1:${sub_port}
}
CADDY"

  $SUDO bash -c "cat > '${caddy_dir}/docker-compose.yml' <<'COMPOSE'
services:
  remnawave-subscription-caddy:
    image: caddy:2-alpine
    container_name: remnawave-subscription-caddy
    hostname: remnawave-subscription-caddy
    restart: always
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - subscription_caddy_data:/data
      - subscription_caddy_config:/config

volumes:
  subscription_caddy_data:
  subscription_caddy_config:
COMPOSE"

  $SUDO chmod 644 "${caddy_dir}/Caddyfile" "${caddy_dir}/docker-compose.yml"
}

run_subscription_caddy_install_flow() {
  local caddy_dir="${1:-}"
  local sub_domain="${2:-}"
  local sub_port="${3:-}"
  local backup_suffix=""

  if [[ -z "$caddy_dir" ]]; then
    caddy_dir="$(ask_value "$(tr_text "Путь установки Caddy для подписок" "Subscription Caddy installation path")" "${REMNAWAVE_DIR:-/opt/remnawave}/subscription-caddy")"
    [[ "$caddy_dir" == "__PBM_BACK__" ]] && return 1
  fi
  if ! validate_project_path_or_warn "SUBSCRIPTION_CADDY_DIR" "$caddy_dir"; then
    return 1
  fi

  while true; do
    if [[ -z "$sub_domain" ]]; then
      sub_domain="$(ask_value "$(tr_text "Домен подписок (без http/https)" "Subscription domain (without http/https)")" "${REMNAWAVE_LAST_SUB_DOMAIN}")"
      [[ "$sub_domain" == "__PBM_BACK__" ]] && return 1
    fi
    validate_domain_or_warn "PBM_SUBSCRIPTION_DOMAIN" "$sub_domain" && break
    sub_domain=""
  done

  while true; do
    if [[ -z "$sub_port" ]]; then
      sub_port="$(ask_value "$(tr_text "Локальный порт subscription" "Subscription local port")" "${REMNAWAVE_LAST_SUB_PORT:-3010}")"
      [[ "$sub_port" == "__PBM_BACK__" ]] && return 1
    fi
    validate_tcp_port_or_warn "SUBSCRIPTION_PORT" "$sub_port" && break
    sub_port=""
  done

  if ! ensure_docker_available; then
    return 1
  fi

  if [[ -f "${caddy_dir}/Caddyfile" || -f "${caddy_dir}/docker-compose.yml" ]]; then
    backup_suffix="$(date -u +%Y%m%d-%H%M%S)"
    $SUDO cp "${caddy_dir}/Caddyfile" "${caddy_dir}/Caddyfile.bak-${backup_suffix}" >/dev/null 2>&1 || true
    $SUDO cp "${caddy_dir}/docker-compose.yml" "${caddy_dir}/docker-compose.yml.bak-${backup_suffix}" >/dev/null 2>&1 || true
  fi

  paint "$CLR_ACCENT" "$(tr_text "Генерирую Caddy для подписок" "Generating subscription Caddy configuration")"
  write_subscription_caddy_template "$caddy_dir" "$sub_domain" "$sub_port"

  paint "$CLR_ACCENT" "$(tr_text "Запускаю Caddy для подписок" "Starting subscription Caddy")"
  if compose_stack_up "$caddy_dir"; then
    paint "$CLR_OK" "$(tr_text "Caddy для подписок установлен/обновлен." "Subscription Caddy installed/updated.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось запустить Caddy для подписок." "Failed to start subscription Caddy.")"
  return 1
}

run_subscription_install_flow() {
  local sub_dir=""
  local panel_domain=""
  local sub_domain=""
  local sub_port=""
  local api_token=""
  local backup_suffix=""
  local install_with_panel="1"
  local panel_dir=""
  local default_same_server="y"
  local yn_rc=0
  local deploy_mode="same-server"
  local install_caddy_for_separate="0"
  local caddy_dir=""
  local reinstall_choice=""

  load_existing_env_defaults
  panel_dir="${REMNAWAVE_DIR:-/opt/remnawave}"
  load_panel_install_defaults "$panel_dir"

  draw_header "$(tr_text "Установка страницы подписок" "Install subscription page")"
  sub_dir="$(ask_value "$(tr_text "Путь установки subscription" "Subscription installation path")" "${REMNAWAVE_DIR:-/opt/remnawave}/subscription")"
  [[ "$sub_dir" == "__PBM_BACK__" ]] && return 1
  if ! validate_project_path_or_warn "SUBSCRIPTION_DIR" "$sub_dir"; then
    return 1
  fi
  if ! validate_project_path_or_warn "REMNAWAVE_DIR" "$panel_dir"; then
    return 1
  fi
  load_subscription_install_defaults "$sub_dir"

  if [[ ! -f "${panel_dir}/.env" && ! -f "${panel_dir}/docker-compose.yml" ]]; then
    default_same_server="n"
  fi
  if [[ "${REMNAWAVE_LAST_SUB_MODE:-}" == "separate-server" ]]; then
    default_same_server="n"
  elif [[ "${REMNAWAVE_LAST_SUB_MODE:-}" == "same-server" ]]; then
    default_same_server="y"
  fi

  if [[ -f "${sub_dir}/.env" || -f "${sub_dir}/docker-compose.yml" ]]; then
    paint "$CLR_WARN" "$(tr_text "Обнаружена существующая установка страницы подписок." "Existing subscription page installation detected.")"
    paint "$CLR_MUTED" "  $(tr_text "Путь:" "Path:") ${sub_dir}"
    paint "$CLR_MUTED" "  $(tr_text "Домен панели:" "Panel domain:") ${REMNAWAVE_LAST_PANEL_DOMAIN:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Домен подписки:" "Subscription domain:") ${REMNAWAVE_LAST_SUB_DOMAIN:-n/a}"
    paint "$CLR_MUTED" "  $(tr_text "Порт subscription:" "Subscription port:") ${REMNAWAVE_LAST_SUB_PORT:-3010}"
    paint "$CLR_MUTED" "  $(tr_text "Режим:" "Mode:") ${REMNAWAVE_LAST_SUB_MODE:-same-server}"
    if [[ -n "${REMNAWAVE_LAST_API_TOKEN:-}" ]]; then
      paint "$CLR_MUTED" "  API token: $(tr_text "задан" "set")"
    else
      paint "$CLR_MUTED" "  API token: $(tr_text "не задан" "not set")"
    fi
    if ! ask_yes_no "$(tr_text "Точно переустановить страницу подписок? Текущие значения будут предложены по умолчанию." "Reinstall subscription page? Current values will be offered as defaults.")" "n"; then
      paint "$CLR_WARN" "$(tr_text "Переустановка отменена. Текущая страница подписок не изменена." "Reinstall cancelled. Current subscription page was not changed.")"
      return 2
    fi
    reinstall_choice="1"
    paint "$CLR_MUTED" "$(tr_text "Дальше можно нажимать Enter, чтобы оставить значение в скобках, или ввести свое." "Next prompts: press Enter to keep the value in brackets, or type a new one.")"
  fi

  if [[ "${AUTO_REMNAWAVE_FULL:-0}" != "1" ]]; then
    while true; do
      if ask_yes_no "$(tr_text "Страница подписок на том же сервере, что и панель?" "Install subscription on the same server as panel?")" "$default_same_server"; then
        if [[ -f "${panel_dir}/.env" || -f "${panel_dir}/docker-compose.yml" ]]; then
          install_with_panel="1"
          break
        fi
        paint "$CLR_WARN" "$(tr_text "Панель в ${REMNAWAVE_DIR:-/opt/remnawave} не найдена. Для отдельного сервера выберите 'n'." "Panel was not found in ${REMNAWAVE_DIR:-/opt/remnawave}. Select 'n' for separate server mode.")"
      else
        yn_rc=$?
        if [[ "$yn_rc" -eq 2 ]]; then
          return 1
        fi
        install_with_panel="0"
        break
      fi
    done
  fi

  while true; do
    panel_domain="$(ask_value "$(tr_text "Домен панели (без http/https)" "Panel domain (without http/https)")" "${REMNAWAVE_LAST_PANEL_DOMAIN}")"
    [[ "$panel_domain" == "__PBM_BACK__" ]] && return 1
    validate_domain_or_warn "FRONT_END_DOMAIN" "$panel_domain" && break
  done

  if [[ "$install_with_panel" == "0" ]]; then
    while true; do
      sub_domain="$(ask_value "$(tr_text "Домен подписок (без http/https)" "Subscription domain (without http/https)")" "${REMNAWAVE_LAST_SUB_DOMAIN}")"
      [[ "$sub_domain" == "__PBM_BACK__" ]] && return 1
      validate_domain_or_warn "PBM_SUBSCRIPTION_DOMAIN" "$sub_domain" && break
    done
  else
    sub_domain="${REMNAWAVE_LAST_SUB_DOMAIN}"
    while [[ -z "$sub_domain" ]] || ! validate_domain_or_warn "SUB_PUBLIC_DOMAIN" "$sub_domain"; do
      sub_domain="$(ask_value "$(tr_text "Домен подписок (без http/https)" "Subscription domain (without http/https)")" "${REMNAWAVE_LAST_SUB_DOMAIN}")"
      [[ "$sub_domain" == "__PBM_BACK__" ]] && return 1
    done
  fi

  while true; do
    sub_port="$(ask_value "$(tr_text "Порт subscription" "Subscription port")" "${REMNAWAVE_LAST_SUB_PORT:-3010}")"
    [[ "$sub_port" == "__PBM_BACK__" ]] && return 1
    validate_tcp_port_or_warn "SUBSCRIPTION_PORT" "$sub_port" && break
  done

  while true; do
    api_token="$(ask_secret_value "$(tr_text "API токен панели (Remnawave Settings -> API Tokens)" "Panel API token (Remnawave Settings -> API Tokens)")" "${REMNAWAVE_LAST_API_TOKEN}")"
    [[ "$api_token" == "__PBM_BACK__" ]] && return 1
    [[ -n "$api_token" ]] && break
    paint "$CLR_WARN" "$(tr_text "API токен не может быть пустым." "API token cannot be empty.")"
  done

  if ! ensure_docker_available; then
    return 1
  fi

  if [[ -n "$reinstall_choice" ]]; then
    backup_suffix="$(date -u +%Y%m%d-%H%M%S)"
    if [[ -f "${sub_dir}/.env" ]]; then
      if ! $SUDO cp "${sub_dir}/.env" "${sub_dir}/.env.bak-${backup_suffix}" 2>/dev/null; then
        paint "$CLR_WARN" "$(tr_text "Не удалось создать backup subscription .env." "Failed to create subscription .env backup.")"
      fi
    fi
    if [[ -f "${sub_dir}/docker-compose.yml" ]]; then
      if ! $SUDO cp "${sub_dir}/docker-compose.yml" "${sub_dir}/docker-compose.yml.bak-${backup_suffix}" 2>/dev/null; then
        paint "$CLR_WARN" "$(tr_text "Не удалось создать backup subscription docker-compose.yml." "Failed to create subscription docker-compose.yml backup.")"
      fi
    fi
  fi

  paint "$CLR_ACCENT" "$(tr_text "Генерирую конфигурацию subscription" "Generating subscription configuration")"
  if [[ "$install_with_panel" == "1" ]]; then
    deploy_mode="same-server"
  else
    deploy_mode="separate-server"
  fi
  write_subscription_template "$sub_dir" "$panel_domain" "$sub_port" "$api_token" "$deploy_mode" "$sub_domain"
  REMNAWAVE_DIR="$(dirname "$sub_dir")"
  REMNAWAVE_LAST_PANEL_DOMAIN="$panel_domain"
  REMNAWAVE_LAST_SUB_DOMAIN="$sub_domain"
  REMNAWAVE_LAST_SUB_PORT="$sub_port"

  paint "$CLR_ACCENT" "$(tr_text "Запускаю контейнер subscription" "Starting subscription container")"
  if [[ "$install_with_panel" == "1" ]]; then
    if ! ensure_remnawave_shared_network; then
      return 1
    fi
  fi
  if compose_stack_up "$sub_dir"; then
    paint "$CLR_OK" "$(tr_text "Страница подписок установлена/обновлена." "Subscription page installed/updated.")"
    paint "$CLR_MUTED" "$(tr_text "Путь:" "Path:") ${sub_dir}"
    if [[ "$install_with_panel" == "0" ]]; then
      if ask_yes_no "$(tr_text "Установить Caddy для подписок на этом сервере?" "Install Caddy for subscription on this server?")" "y"; then
        caddy_dir="${REMNAWAVE_DIR:-/opt/remnawave}/subscription-caddy"
        install_caddy_for_separate="1"
      fi
      if [[ "$install_caddy_for_separate" == "1" ]]; then
        if ! run_subscription_caddy_install_flow "$caddy_dir" "$sub_domain" "$sub_port"; then
          paint "$CLR_WARN" "$(tr_text "Subscription запущен, но Caddy для подписок не настроен." "Subscription is running, but subscription Caddy was not configured.")"
          return 1
        fi
      fi
    fi
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось запустить subscription." "Failed to start subscription.")"
  return 1
}

run_subscription_update_flow() {
  local sub_dir=""
  local env_file=""
  local deploy_mode="same-server"
  local caddy_dir=""

  load_existing_env_defaults

  draw_header "$(tr_text "Обновление страницы подписок" "Update subscription page")"
  sub_dir="$(ask_value "$(tr_text "Путь к subscription" "Subscription path")" "${REMNAWAVE_DIR:-/opt/remnawave}/subscription")"
  [[ "$sub_dir" == "__PBM_BACK__" ]] && return 1
  if ! validate_project_path_or_warn "SUBSCRIPTION_DIR" "$sub_dir"; then
    return 1
  fi

  env_file="${sub_dir}/.env"
  if [[ -f "$env_file" ]]; then
    REMNAWAVE_LAST_SUB_PORT="$(awk -F= '/^APP_PORT=/{print $2; exit}' "$env_file")"
    REMNAWAVE_LAST_SUB_DOMAIN="$(awk -F= '/^PBM_SUBSCRIPTION_DOMAIN=/{print $2; exit}' "$env_file")"
    deploy_mode="$(awk -F= '/^PBM_SUBSCRIPTION_MODE=/{print $2; exit}' "$env_file")"
    [[ -z "$deploy_mode" ]] && deploy_mode="same-server"
  fi

  if ! ensure_docker_available; then
    return 1
  fi
  if [[ "$deploy_mode" == "same-server" ]]; then
    if ! ensure_remnawave_shared_network; then
      return 1
    fi
  fi

  paint "$CLR_ACCENT" "$(tr_text "Обновляю subscription" "Updating subscription")"
  if compose_stack_update "$sub_dir"; then
    paint "$CLR_OK" "$(tr_text "Страница подписок обновлена." "Subscription page updated.")"
    if [[ "$deploy_mode" == "separate-server" ]]; then
      caddy_dir="${REMNAWAVE_DIR:-/opt/remnawave}/subscription-caddy"
      if [[ -f "${caddy_dir}/docker-compose.yml" ]]; then
        paint "$CLR_ACCENT" "$(tr_text "Обновляю Caddy для подписок" "Updating subscription Caddy")"
        if ! compose_stack_update "$caddy_dir"; then
          paint "$CLR_WARN" "$(tr_text "Subscription обновлен, но Caddy для подписок не обновлен." "Subscription updated, but subscription Caddy update failed.")"
        fi
      fi
    fi
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Ошибка обновления subscription." "Subscription update failed.")"
  return 1
}

run_remnawave_full_install_flow() {
  local prev_auto_caddy="${AUTO_PANEL_CADDY:-0}"
  local panel_step_rc=0
  draw_header "$(tr_text "Remnawave: установка панели + Caddy" "Remnawave: panel + Caddy install")"
  paint "$CLR_MUTED" "$(tr_text "Шаг 1/2: панель, шаг 2/2: Caddy." "Step 1/2: panel, step 2/2: Caddy.")"
  if ! run_panel_install_flow; then
    panel_step_rc=$?
  fi

  if [[ "$panel_step_rc" -eq 1 ]]; then
    paint "$CLR_WARN" "$(tr_text "Полная установка остановлена на шаге панели." "Full install stopped at panel step.")"
    return 1
  fi

  if [[ "$panel_step_rc" -eq 2 ]]; then
    paint "$CLR_MUTED" "$(tr_text "Шаг панели пропущен: используется текущая установка." "Panel step skipped: using existing installation.")"
  fi

  AUTO_PANEL_CADDY=1
  if ! run_panel_caddy_install_flow; then
    AUTO_PANEL_CADDY="$prev_auto_caddy"
    paint "$CLR_WARN" "$(tr_text "Панель установлена, но шаг Caddy не завершен." "Panel installed, but Caddy step did not finish.")"
    return 1
  fi
  AUTO_PANEL_CADDY="$prev_auto_caddy"
  paint "$CLR_OK" "$(tr_text "Установка панели и Caddy завершена. Подписку можно установить отдельно в меню." "Panel and Caddy install completed. Subscription can be installed separately from the menu.")"
  return 0
}

run_remnawave_full_update_flow() {
  local prev_auto_caddy="${AUTO_PANEL_CADDY:-0}"
  draw_header "$(tr_text "Remnawave: обновление панели + Caddy" "Remnawave: panel + Caddy update")"
  paint "$CLR_MUTED" "$(tr_text "Шаг 1/2: панель, шаг 2/2: Caddy." "Step 1/2: panel, step 2/2: Caddy.")"
  if ! run_panel_update_flow; then
    paint "$CLR_WARN" "$(tr_text "Полное обновление остановлено на шаге панели." "Full update stopped at panel step.")"
    return 1
  fi
  AUTO_PANEL_CADDY=1
  if ! run_panel_caddy_update_flow; then
    AUTO_PANEL_CADDY="$prev_auto_caddy"
    paint "$CLR_WARN" "$(tr_text "Панель обновлена, но шаг Caddy не завершен." "Panel updated, but Caddy step did not finish.")"
    return 1
  fi
  AUTO_PANEL_CADDY="$prev_auto_caddy"
  paint "$CLR_OK" "$(tr_text "Обновление панели и Caddy завершено. Подписку можно обновить отдельно в меню." "Panel and Caddy update completed. Subscription can be updated separately from the menu.")"
  return 0
}
