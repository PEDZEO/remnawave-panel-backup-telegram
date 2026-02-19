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
