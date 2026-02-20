#!/usr/bin/env bash
# update: panel/node install and update operations for manager.sh

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
  $SUDO chmod 777 /var/log/remnanode

  if ! command -v logrotate >/dev/null 2>&1; then
    install_package "logrotate" >/dev/null 2>&1 || true
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
      - 127.0.0.1:${APP_PORT}:${APP_PORT}
      - 127.0.0.1:3001:${METRICS_PORT:-3001}
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
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
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - 127.0.0.1:6767:5432
    volumes:
      - remnawave-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
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
    driver: bridge
    external: false

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

  draw_header "$(tr_text "Установка панели Remnawave" "Install Remnawave panel")"
  panel_dir="$(ask_value "$(tr_text "Путь установки панели" "Panel installation path")" "/opt/remnawave")"
  [[ "$panel_dir" == "__PBM_BACK__" ]] && return 1

  if [[ -f "${panel_dir}/docker-compose.yml" || -f "${panel_dir}/.env" ]]; then
    paint "$CLR_WARN" "$(tr_text "Обнаружена существующая установка панели." "Existing panel installation detected.")"
    if ! ask_yes_no "$(tr_text "Перезаписать конфиги и выполнить переустановку?" "Overwrite config files and reinstall?")" "n"; then
      paint "$CLR_WARN" "$(tr_text "Установка отменена." "Installation cancelled.")"
      return 1
    fi
    reinstall_choice="1"

    if ask_yes_no "$(tr_text "Остановить контейнеры перед переустановкой?" "Stop containers before reinstall?")" "y"; then
      (cd "$panel_dir" && $SUDO docker compose down) || true
    fi

    if ask_yes_no "$(tr_text "Удалить Docker volumes панели (ПОЛНАЯ ОЧИСТКА ДАННЫХ)?" "Remove panel Docker volumes (FULL DATA WIPE)?")" "n"; then
      clean_data="1"
    fi
  fi

  while true; do
    panel_domain="$(ask_value "$(tr_text "Домен панели (без http/https)" "Panel domain (without http/https)")" "")"
    [[ "$panel_domain" == "__PBM_BACK__" ]] && return 1
    [[ -n "$panel_domain" ]] && break
    paint "$CLR_WARN" "$(tr_text "Домен панели не может быть пустым." "Panel domain cannot be empty.")"
  done

  while true; do
    sub_domain="$(ask_value "$(tr_text "Домен подписки (без http/https)" "Subscription domain (without http/https)")" "")"
    [[ "$sub_domain" == "__PBM_BACK__" ]] && return 1
    [[ -n "$sub_domain" ]] && break
    paint "$CLR_WARN" "$(tr_text "Домен подписки не может быть пустым." "Subscription domain cannot be empty.")"
  done

  while true; do
    panel_port="$(ask_value "$(tr_text "Порт панели" "Panel port")" "3000")"
    [[ "$panel_port" == "__PBM_BACK__" ]] && return 1
    if [[ "$panel_port" =~ ^[0-9]+$ ]]; then
      break
    fi
    paint "$CLR_WARN" "$(tr_text "Порт должен быть числом." "Port must be numeric.")"
  done

  if ! ensure_docker_available; then
    return 1
  fi
  if ! ensure_openssl_available; then
    return 1
  fi

  db_user="$(generate_alpha_login)"
  db_password="$(generate_hex 24)"
  jwt_auth_secret="$(generate_hex 64)"
  jwt_api_tokens_secret="$(generate_hex 64)"
  metrics_user="$(generate_alpha_login)"
  metrics_pass="$(generate_hex 64)"
  webhook_secret_header="$(generate_hex 64)"

  paint "$CLR_ACCENT" "$(tr_text "Генерирую конфигурацию панели" "Generating panel configuration")"
  if [[ -n "$reinstall_choice" ]]; then
    backup_suffix="$(date -u +%Y%m%d-%H%M%S)"
    if [[ -f "${panel_dir}/.env" ]]; then
      $SUDO cp "${panel_dir}/.env" "${panel_dir}/.env.bak-${backup_suffix}" || true
    fi
    if [[ -f "${panel_dir}/docker-compose.yml" ]]; then
      $SUDO cp "${panel_dir}/docker-compose.yml" "${panel_dir}/docker-compose.yml.bak-${backup_suffix}" || true
    fi
  fi

  write_panel_templates "$panel_dir" "$panel_domain" "$sub_domain" "$panel_port" "$db_user" "$db_password" "$jwt_auth_secret" "$jwt_api_tokens_secret" "$metrics_user" "$metrics_pass" "$webhook_secret_header"

  if [[ -n "$clean_data" ]]; then
    paint "$CLR_WARN" "$(tr_text "Удаляю volumes панели" "Removing panel volumes")"
    $SUDO docker volume rm remnawave-db-data remnawave-redis-data >/dev/null 2>&1 || true
  fi

  paint "$CLR_ACCENT" "$(tr_text "Запускаю контейнеры панели" "Starting panel containers")"
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
  draw_header "$(tr_text "Обновление панели Remnawave" "Update Remnawave panel")"
  panel_dir="$(ask_value "$(tr_text "Путь к панели" "Panel path")" "/opt/remnawave")"
  [[ "$panel_dir" == "__PBM_BACK__" ]] && return 1

  if ! ensure_docker_available; then
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

run_node_install_flow() {
  local node_dir=""
  local node_port=""
  local secret_key=""

  draw_header "$(tr_text "Установка ноды RemnaNode" "Install RemnaNode")"
  node_dir="$(ask_value "$(tr_text "Путь установки ноды" "Node installation path")" "/opt/remnanode")"
  [[ "$node_dir" == "__PBM_BACK__" ]] && return 1

  while true; do
    node_port="$(ask_value "$(tr_text "Порт ноды" "Node port")" "3001")"
    [[ "$node_port" == "__PBM_BACK__" ]] && return 1
    if [[ "$node_port" =~ ^[0-9]+$ ]]; then
      break
    fi
    paint "$CLR_WARN" "$(tr_text "Порт должен быть числом." "Port must be numeric.")"
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

  $SUDO install -d -m 755 "$target_dir"
  $SUDO bash -c "cat > '${target_dir}/.env' <<ENV
APP_PORT=${sub_port}
REMNAWAVE_PANEL_URL=https://${panel_domain}
REMNAWAVE_API_TOKEN=${api_token}
ENV"

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

  $SUDO chmod 600 "${target_dir}/.env"
  $SUDO chmod 644 "${target_dir}/docker-compose.yml"
}

run_subscription_install_flow() {
  local sub_dir=""
  local panel_domain=""
  local sub_port=""
  local api_token=""
  local backup_suffix=""

  load_existing_env_defaults

  draw_header "$(tr_text "Установка страницы подписок" "Install subscription page")"
  sub_dir="$(ask_value "$(tr_text "Путь установки subscription" "Subscription installation path")" "${REMNAWAVE_DIR:-/opt/remnawave}/subscription")"
  [[ "$sub_dir" == "__PBM_BACK__" ]] && return 1

  while true; do
    panel_domain="$(ask_value "$(tr_text "Домен панели (без http/https)" "Panel domain (without http/https)")" "")"
    [[ "$panel_domain" == "__PBM_BACK__" ]] && return 1
    [[ -n "$panel_domain" ]] && break
    paint "$CLR_WARN" "$(tr_text "Домен панели не может быть пустым." "Panel domain cannot be empty.")"
  done

  while true; do
    sub_port="$(ask_value "$(tr_text "Порт subscription" "Subscription port")" "3010")"
    [[ "$sub_port" == "__PBM_BACK__" ]] && return 1
    if [[ "$sub_port" =~ ^[0-9]+$ ]]; then
      break
    fi
    paint "$CLR_WARN" "$(tr_text "Порт должен быть числом." "Port must be numeric.")"
  done

  while true; do
    api_token="$(ask_value "$(tr_text "API токен панели (Remnawave Settings -> API Tokens)" "Panel API token (Remnawave Settings -> API Tokens)")" "")"
    [[ "$api_token" == "__PBM_BACK__" ]] && return 1
    [[ -n "$api_token" ]] && break
    paint "$CLR_WARN" "$(tr_text "API токен не может быть пустым." "API token cannot be empty.")"
  done

  if ! ensure_docker_available; then
    return 1
  fi

  if [[ -f "${sub_dir}/.env" || -f "${sub_dir}/docker-compose.yml" ]]; then
    backup_suffix="$(date -u +%Y%m%d-%H%M%S)"
    $SUDO cp "${sub_dir}/.env" "${sub_dir}/.env.bak-${backup_suffix}" 2>/dev/null || true
    $SUDO cp "${sub_dir}/docker-compose.yml" "${sub_dir}/docker-compose.yml.bak-${backup_suffix}" 2>/dev/null || true
  fi

  paint "$CLR_ACCENT" "$(tr_text "Генерирую конфигурацию subscription" "Generating subscription configuration")"
  write_subscription_template "$sub_dir" "$panel_domain" "$sub_port" "$api_token"

  paint "$CLR_ACCENT" "$(tr_text "Запускаю контейнер subscription" "Starting subscription container")"
  if compose_stack_up "$sub_dir"; then
    paint "$CLR_OK" "$(tr_text "Страница подписок установлена/обновлена." "Subscription page installed/updated.")"
    paint "$CLR_MUTED" "$(tr_text "Путь:" "Path:") ${sub_dir}"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось запустить subscription." "Failed to start subscription.")"
  return 1
}

run_subscription_update_flow() {
  local sub_dir=""

  load_existing_env_defaults

  draw_header "$(tr_text "Обновление страницы подписок" "Update subscription page")"
  sub_dir="$(ask_value "$(tr_text "Путь к subscription" "Subscription path")" "${REMNAWAVE_DIR:-/opt/remnawave}/subscription")"
  [[ "$sub_dir" == "__PBM_BACK__" ]] && return 1

  if ! ensure_docker_available; then
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Обновляю subscription" "Updating subscription")"
  if compose_stack_update "$sub_dir"; then
    paint "$CLR_OK" "$(tr_text "Страница подписок обновлена." "Subscription page updated.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Ошибка обновления subscription." "Subscription update failed.")"
  return 1
}

run_remnawave_full_install_flow() {
  draw_header "$(tr_text "Remnawave: полная установка" "Remnawave: full install")"
  paint "$CLR_MUTED" "$(tr_text "Шаг 1/2: панель, шаг 2/2: страница подписок." "Step 1/2: panel, step 2/2: subscription page.")"
  if ! run_panel_install_flow; then
    paint "$CLR_WARN" "$(tr_text "Полная установка остановлена на шаге панели." "Full install stopped at panel step.")"
    return 1
  fi
  if ! run_subscription_install_flow; then
    paint "$CLR_WARN" "$(tr_text "Панель установлена, но шаг подписок не завершен." "Panel installed, but subscription step did not finish.")"
    return 1
  fi
  paint "$CLR_OK" "$(tr_text "Полная установка Remnawave завершена." "Remnawave full install completed.")"
  return 0
}

run_remnawave_full_update_flow() {
  draw_header "$(tr_text "Remnawave: полное обновление" "Remnawave: full update")"
  paint "$CLR_MUTED" "$(tr_text "Шаг 1/2: панель, шаг 2/2: страница подписок." "Step 1/2: panel, step 2/2: subscription page.")"
  if ! run_panel_update_flow; then
    paint "$CLR_WARN" "$(tr_text "Полное обновление остановлено на шаге панели." "Full update stopped at panel step.")"
    return 1
  fi
  if ! run_subscription_update_flow; then
    paint "$CLR_WARN" "$(tr_text "Панель обновлена, но шаг подписок не завершен." "Panel updated, but subscription step did not finish.")"
    return 1
  fi
  paint "$CLR_OK" "$(tr_text "Полное обновление Remnawave завершено." "Remnawave full update completed.")"
  return 0
}

ensure_remnanode_caddy_installed() {
  if command -v caddy >/dev/null 2>&1; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Caddy не найден." "Caddy is not installed.")"
  if ! ask_yes_no "$(tr_text "Установить Caddy сейчас?" "Install Caddy now?")" "y"; then
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    paint "$CLR_ACCENT" "$(tr_text "Устанавливаю Caddy через официальный репозиторий..." "Installing Caddy from official repository...")"
    $SUDO apt-get update -y >/dev/null 2>&1 || true
    $SUDO apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg >/dev/null 2>&1 || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | $SUDO gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    $SUDO apt-get update -y >/dev/null 2>&1 || true
    $SUDO apt-get install -y caddy >/dev/null 2>&1 || true
  else
    paint "$CLR_WARN" "$(tr_text "Автоустановка Caddy поддерживается только на apt-системах. Установите Caddy вручную и повторите." "Automatic Caddy install is supported only on apt-based systems. Install Caddy manually and retry.")"
    return 1
  fi

  if ! command -v caddy >/dev/null 2>&1; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось установить Caddy." "Failed to install Caddy.")"
    return 1
  fi
  return 0
}

run_node_caddy_selfsteal_flow() {
  local domain=""
  local monitor_port=""

  draw_header "$(tr_text "RemnaNode: Caddy self-steal" "RemnaNode: Caddy self-steal")"
  while true; do
    domain="$(ask_value "$(tr_text "Домен для self-steal (пример: node.example.com)" "Domain for self-steal (example: node.example.com)")" "")"
    [[ "$domain" == "__PBM_BACK__" ]] && return 1
    [[ -n "$domain" ]] && break
    paint "$CLR_WARN" "$(tr_text "Домен не может быть пустым." "Domain cannot be empty.")"
  done

  while true; do
    monitor_port="$(ask_value "$(tr_text "Порт self-steal" "Self-steal port")" "8443")"
    [[ "$monitor_port" == "__PBM_BACK__" ]] && return 1
    if [[ "$monitor_port" =~ ^[0-9]+$ ]]; then
      break
    fi
    paint "$CLR_WARN" "$(tr_text "Порт должен быть числом." "Port must be numeric.")"
  done

  if ! ensure_remnanode_caddy_installed; then
    return 1
  fi

  $SUDO install -d -m 755 /var/www/site
  $SUDO bash -c "cat > /var/www/site/index.html <<HTML
<!doctype html>
<html lang=\"en\">
<head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>OK</title></head>
<body><h1>OK</h1></body>
</html>
HTML"

  $SUDO bash -c "cat > /etc/caddy/Caddyfile <<CADDY
${domain}:${monitor_port} {
    @local {
        remote_ip 127.0.0.1 ::1
    }

    handle @local {
        root * /var/www/site
        try_files {path} /index.html
        file_server
    }

    handle {
        abort
    }
}
CADDY"

  $SUDO systemctl enable --now caddy >/dev/null 2>&1 || true
  if $SUDO systemctl restart caddy >/dev/null 2>&1; then
    paint "$CLR_OK" "$(tr_text "Caddy self-steal настроен." "Caddy self-steal configured.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось перезапустить Caddy." "Failed to restart Caddy.")"
  return 1
}

run_node_bbr_flow() {
  draw_header "$(tr_text "RemnaNode: BBR" "RemnaNode: BBR")"
  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    paint "$CLR_OK" "$(tr_text "BBR уже включен." "BBR is already enabled.")"
    return 0
  fi

  if ! ask_yes_no "$(tr_text "Включить BBR сейчас?" "Enable BBR now?")" "y"; then
    return 1
  fi

  if ! $SUDO grep -q '^net.core.default_qdisc=fq$' /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc=fq" | $SUDO tee -a /etc/sysctl.conf >/dev/null
  fi
  if ! $SUDO grep -q '^net.ipv4.tcp_congestion_control=bbr$' /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.tcp_congestion_control=bbr" | $SUDO tee -a /etc/sysctl.conf >/dev/null
  fi

  $SUDO sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
  $SUDO sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
  $SUDO sysctl -p >/dev/null 2>&1 || true

  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    paint "$CLR_OK" "$(tr_text "BBR включен." "BBR enabled.")"
    return 0
  fi
  paint "$CLR_WARN" "$(tr_text "BBR не подтвержден. Проверьте sysctl вручную." "BBR not confirmed. Check sysctl manually.")"
  return 1
}

run_node_ipv6_toggle_flow() {
  local state=""
  local conf_file="/etc/sysctl.d/99-remnanode-ipv6.conf"

  draw_header "$(tr_text "RemnaNode: IPv6" "RemnaNode: IPv6")"
  state="$(sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk -F'= ' '{print $2}' || echo "0")"
  if [[ "$state" == "1" ]]; then
    paint "$CLR_WARN" "$(tr_text "Текущее состояние: IPv6 выключен." "Current state: IPv6 is disabled.")"
    if ! ask_yes_no "$(tr_text "Включить IPv6?" "Enable IPv6?")" "y"; then
      return 1
    fi
    $SUDO bash -c "cat > ${conf_file} <<CONF
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0
CONF"
  else
    paint "$CLR_OK" "$(tr_text "Текущее состояние: IPv6 включен." "Current state: IPv6 is enabled.")"
    if ! ask_yes_no "$(tr_text "Выключить IPv6?" "Disable IPv6?")" "n"; then
      return 1
    fi
    $SUDO bash -c "cat > ${conf_file} <<CONF
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
CONF"
  fi

  $SUDO sysctl --system >/dev/null 2>&1 || true
  paint "$CLR_OK" "$(tr_text "Настройка IPv6 применена." "IPv6 setting applied.")"
  paint "$CLR_MUTED" "  $(tr_text "Файл:" "File:") ${conf_file}"
  return 0
}

install_wgcf_binary() {
  local release_url="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
  local version=""
  local arch=""
  local wgcf_arch=""
  local bin_name=""
  local download_url=""

  version="$(curl -fsSL "$release_url" 2>/dev/null | awk -F'"' '/tag_name/ {print $4; exit}' || true)"
  [[ -n "$version" ]] || return 1

  arch="$(uname -m)"
  case "$arch" in
    x86_64) wgcf_arch="amd64" ;;
    aarch64|arm64) wgcf_arch="arm64" ;;
    armv7l) wgcf_arch="armv7" ;;
    *) wgcf_arch="amd64" ;;
  esac

  bin_name="wgcf_${version#v}_linux_${wgcf_arch}"
  download_url="https://github.com/ViRb3/wgcf/releases/download/${version}/${bin_name}"
  curl -fsSL "$download_url" -o "$TMP_DIR/$bin_name" || return 1
  chmod +x "$TMP_DIR/$bin_name"
  $SUDO mv "$TMP_DIR/$bin_name" /usr/local/bin/wgcf
  return 0
}

run_node_warp_native_flow() {
  local wgcf_dir="$TMP_DIR/wgcf"
  local reconfigure=0

  draw_header "$(tr_text "RemnaNode: WARP Native (wgcf)" "RemnaNode: WARP Native (wgcf)")"
  paint "$CLR_WARN" "$(tr_text "Режим: best-effort. Скрипт попробует настроить wgcf и интерфейс warp." "Mode: best-effort. Script will try to configure wgcf and warp interface.")"

  if command -v wgcf >/dev/null 2>&1 && [[ -f /etc/wireguard/warp.conf ]]; then
    if ask_yes_no "$(tr_text "WARP уже настроен. Переустановить/переконфигурировать?" "WARP is already configured. Reconfigure?")" "n"; then
      reconfigure=1
    else
      return 1
    fi
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    paint "$CLR_DANGER" "$(tr_text "Автонастройка WARP поддерживается только на apt-системах." "Automatic WARP setup is supported only on apt-based systems.")"
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Устанавливаю зависимости (wireguard, curl)..." "Installing dependencies (wireguard, curl)...")"
  $SUDO apt-get update -y >/dev/null 2>&1 || true
  $SUDO apt-get install -y wireguard curl >/dev/null 2>&1 || true

  if [[ "$reconfigure" == "1" ]]; then
    $SUDO systemctl disable --now wg-quick@warp >/dev/null 2>&1 || true
    $SUDO rm -f /etc/wireguard/warp.conf >/dev/null 2>&1 || true
  fi

  if ! command -v wgcf >/dev/null 2>&1; then
    paint "$CLR_ACCENT" "$(tr_text "Скачиваю wgcf..." "Downloading wgcf...")"
    if ! install_wgcf_binary; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось скачать wgcf." "Failed to download wgcf.")"
      return 1
    fi
  fi

  mkdir -p "$wgcf_dir"
  (
    cd "$wgcf_dir"
    if [[ ! -f wgcf-account.toml ]]; then
      yes | wgcf register >/dev/null 2>&1 || true
    fi
    wgcf generate >/dev/null 2>&1 || true
  )

  if [[ ! -f "$wgcf_dir/wgcf-profile.conf" ]]; then
    paint "$CLR_DANGER" "$(tr_text "wgcf не сгенерировал профиль. Проверьте доступ к Cloudflare API." "wgcf did not generate profile. Check Cloudflare API access.")"
    return 1
  fi

  $SUDO install -d -m 700 /etc/wireguard
  $SUDO cp "$wgcf_dir/wgcf-profile.conf" /etc/wireguard/warp.conf
  $SUDO sed -i '/^DNS =/d' /etc/wireguard/warp.conf || true
  if ! $SUDO grep -q '^Table = off$' /etc/wireguard/warp.conf 2>/dev/null; then
    $SUDO sed -i '/^MTU =/aTable = off' /etc/wireguard/warp.conf || true
  fi
  if ! $SUDO grep -q '^PersistentKeepalive = 25$' /etc/wireguard/warp.conf 2>/dev/null; then
    $SUDO sed -i '/^Endpoint =/aPersistentKeepalive = 25' /etc/wireguard/warp.conf || true
  fi

  $SUDO systemctl enable --now wg-quick@warp >/dev/null 2>&1 || true
  if $SUDO systemctl restart wg-quick@warp >/dev/null 2>&1; then
    paint "$CLR_OK" "$(tr_text "WARP Native настроен." "WARP Native configured.")"
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "WARP применен частично. Проверьте: systemctl status wg-quick@warp и wg show warp" "WARP was applied partially. Check: systemctl status wg-quick@warp and wg show warp")"
  return 1
}

run_remnanode_full_setup_flow() {
  draw_header "$(tr_text "RemnaNode: полная настройка" "RemnaNode: full setup")"
  paint "$CLR_MUTED" "$(tr_text "Последовательно: нода -> Caddy self-steal -> BBR -> WARP Native." "Sequence: node -> Caddy self-steal -> BBR -> WARP Native.")"

  if ! run_node_install_flow; then
    paint "$CLR_WARN" "$(tr_text "Полная настройка остановлена на установке ноды." "Full setup stopped at node installation.")"
    return 1
  fi

  if ! run_node_caddy_selfsteal_flow; then
    paint "$CLR_WARN" "$(tr_text "Нода установлена, но Caddy self-steal не настроен." "Node installed, but Caddy self-steal was not configured.")"
    return 1
  fi

  if ! run_node_bbr_flow; then
    paint "$CLR_WARN" "$(tr_text "BBR не был подтвержден." "BBR was not confirmed.")"
  fi

  if ! run_node_warp_native_flow; then
    paint "$CLR_WARN" "$(tr_text "WARP Native настроен частично или с ошибкой." "WARP Native finished partially or with errors.")"
  fi

  paint "$CLR_OK" "$(tr_text "Полная настройка RemnaNode завершена." "RemnaNode full setup completed.")"
  return 0
}
