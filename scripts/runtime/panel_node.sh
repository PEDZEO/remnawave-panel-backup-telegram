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

  if [[ -n "$clean_data" ]]; then
    paint "$CLR_WARN" "$(tr_text "Удаляю volumes панели" "Removing panel volumes")"
    if ! $SUDO docker volume rm remnawave-db-data remnawave-redis-data >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Часть volumes не удалена (возможно, уже отсутствуют)." "Some volumes were not removed (possibly already absent).")"
    fi
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
