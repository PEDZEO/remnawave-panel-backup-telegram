#!/usr/bin/env bash
# Bedolaga Caddy runtime detection, templating and reload helpers.

CADDY_MODE=""
CADDY_CONTAINER_NAME=""
CADDY_FILE_PATH=""
BEDOLAGA_CADDY_DIR="/root/caddy"
BEDOLAGA_CADDY_COMPOSE_FILE="${BEDOLAGA_CADDY_DIR}/docker-compose.yml"

bedolaga_write_default_caddyfile() {
  local target_file="$1"
  cat > "$target_file" <<'CADDY'
{
    servers :443 {
        protocols h1 h2 h3
    }
    servers :80 {
        protocols h1
    }
}
CADDY
}

bedolaga_write_caddy_compose_file() {
  local network_name="${BEDOLAGA_SHARED_NETWORK:-bedolaga-network}"
  cat > "$BEDOLAGA_CADDY_COMPOSE_FILE" <<EOF
services:
  caddy:
    image: caddy:2-alpine
    container_name: remnawave-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./data:/data
      - ./config:/config
      - ./logs:/var/log/caddy
    networks:
      - ${network_name}

networks:
  ${network_name}:
    external: true
EOF
}

bedolaga_disable_host_caddy_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi
  if ! $SUDO systemctl list-unit-files 2>/dev/null | grep -q '^caddy\.service'; then
    return 0
  fi
  $SUDO systemctl stop caddy >/dev/null 2>&1 || true
  $SUDO systemctl disable caddy >/dev/null 2>&1 || true
}

bedolaga_bootstrap_docker_caddy() {
  local source_caddy_file="${1:-}"
  local network_name="${BEDOLAGA_SHARED_NETWORK:-bedolaga-network}"
  local target_caddy_file="${BEDOLAGA_CADDY_DIR}/Caddyfile"

  $SUDO install -d -m 755 "$BEDOLAGA_CADDY_DIR" "${BEDOLAGA_CADDY_DIR}/data" "${BEDOLAGA_CADDY_DIR}/config" "${BEDOLAGA_CADDY_DIR}/logs" || return 1

  if [[ -n "$source_caddy_file" && -f "$source_caddy_file" ]]; then
    $SUDO cp "$source_caddy_file" "$target_caddy_file" || return 1
  elif [[ ! -f "$target_caddy_file" ]]; then
    bedolaga_write_default_caddyfile "$target_caddy_file" || return 1
  fi

  bedolaga_write_caddy_compose_file || return 1

  if ! $SUDO docker network inspect "$network_name" >/dev/null 2>&1; then
    $SUDO docker network create "$network_name" >/dev/null || return 1
  fi

  if ! (cd "$BEDOLAGA_CADDY_DIR" && $SUDO docker compose up -d); then
    paint "$CLR_DANGER" "$(tr_text "Не удалось запустить Docker Caddy в /root/caddy." "Failed to start Docker Caddy in /root/caddy.")"
    return 1
  fi

  if ! bedolaga_detect_caddy_runtime; then
    paint "$CLR_DANGER" "$(tr_text "Docker Caddy запущен, но не удалось определить Caddyfile." "Docker Caddy started, but Caddyfile path was not detected.")"
    return 1
  fi
  if [[ "$CADDY_MODE" != "container" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Ожидался container mode для Caddy, но определен другой режим." "Expected container mode for Caddy, but detected another mode.")"
    return 1
  fi
  return 0
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
  local detected_mode=""
  local detected_file=""

  if bedolaga_detect_caddy_runtime; then
    detected_mode="$CADDY_MODE"
    detected_file="$CADDY_FILE_PATH"
    if [[ "$detected_mode" == "container" ]]; then
      return 0
    fi
    paint "$CLR_WARN" "$(tr_text "Обнаружен системный Caddy. Для Bedolaga рекомендуется Docker Caddy в /root/caddy." "System Caddy detected. Docker Caddy in /root/caddy is recommended for Bedolaga.")"
    if ! ask_yes_no "$(tr_text "Перенести Caddy в Docker и отключить системный caddy.service?" "Migrate Caddy to Docker and disable system caddy.service?")" "y"; then
      paint "$CLR_DANGER" "$(tr_text "Операция отменена: Bedolaga использует только Docker Caddy." "Operation canceled: Bedolaga supports Docker Caddy only.")"
      return 1
    fi
    bedolaga_disable_host_caddy_service
    if ! bedolaga_bootstrap_docker_caddy "$detected_file"; then
      return 1
    fi
    paint "$CLR_OK" "$(tr_text "Caddy перенесен в Docker (/root/caddy), системный сервис отключен." "Caddy migrated to Docker (/root/caddy), system service disabled.")"
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Caddy не найден, для Bedolaga будет установлен Docker Caddy." "Caddy was not found, Docker Caddy will be installed for Bedolaga.")"
  if ! ask_yes_no "$(tr_text "Установить Docker Caddy в /root/caddy сейчас?" "Install Docker Caddy in /root/caddy now?")" "y"; then
    return 1
  fi

  bedolaga_disable_host_caddy_service
  if ! bedolaga_bootstrap_docker_caddy; then
    return 1
  fi
  paint "$CLR_OK" "$(tr_text "Docker Caddy установлен и запущен." "Docker Caddy installed and started.")"
  return 0
}

bedolaga_validate_and_reload_caddy() {
  local validate_output=""
  local reload_output=""

  if [[ "$CADDY_MODE" == "container" ]]; then
    $SUDO docker exec "$CADDY_CONTAINER_NAME" sh -lc 'mkdir -p /var/log/caddy' >/dev/null 2>&1 || true
  else
    $SUDO install -d -m 755 /var/log/caddy >/dev/null 2>&1 || true
    if id -u caddy >/dev/null 2>&1; then
      $SUDO chown caddy:caddy /var/log/caddy >/dev/null 2>&1 || true
    fi
  fi

  if [[ "$CADDY_MODE" == "container" ]]; then
    if ! validate_output="$($SUDO docker exec "$CADDY_CONTAINER_NAME" caddy validate --config /etc/caddy/Caddyfile 2>&1)"; then
      paint "$CLR_DANGER" "$(tr_text "Ошибка проверки Caddy (container mode):" "Caddy validation error (container mode):")"
      printf "%s\n" "$validate_output"
      return 1
    fi

    if reload_output="$($SUDO docker exec "$CADDY_CONTAINER_NAME" caddy reload --config /etc/caddy/Caddyfile 2>&1)"; then
      return 0
    fi
    paint "$CLR_WARN" "$(tr_text "Не удалось выполнить caddy reload, пробую restart контейнера." "caddy reload failed, trying container restart.")"
    printf "%s\n" "$reload_output"
    $SUDO docker restart "$CADDY_CONTAINER_NAME" >/dev/null 2>&1
    return $?
  fi

  if ! validate_output="$($SUDO caddy validate --config "$CADDY_FILE_PATH" 2>&1)"; then
    paint "$CLR_DANGER" "$(tr_text "Ошибка проверки Caddy (host mode):" "Caddy validation error (host mode):")"
    printf "%s\n" "$validate_output"
    return 1
  fi
  if ! reload_output="$($SUDO systemctl reload caddy 2>&1)"; then
    paint "$CLR_DANGER" "$(tr_text "systemctl reload caddy завершился ошибкой:" "systemctl reload caddy failed:")"
    printf "%s\n" "$reload_output"
    return 1
  fi
  if [[ -n "$reload_output" ]]; then
    paint "$CLR_MUTED" "$(tr_text "systemctl reload caddy: " "systemctl reload caddy: ")${reload_output}"
  fi
  return 0
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

    @cabinet_ws path /cabinet/ws*
    handle @cabinet_ws {
        reverse_proxy ${bot_upstream} {
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

  # Keep file inode stable for bind-mounted /etc/caddy/Caddyfile in Docker.
  # Using mv may switch inode and container can keep reading stale file until restart.
  $SUDO cp "$tmp_file" "$caddy_file"
  rm -f "$tmp_file"
  $SUDO chmod 644 "$caddy_file"
  $SUDO chown root:root "$caddy_file" >/dev/null 2>&1 || true

  if ! bedolaga_validate_and_reload_caddy; then
    paint "$CLR_DANGER" "$(tr_text "Проверка Caddyfile не прошла, откатываю изменения." "Caddyfile validation failed, rolling back changes.")"
    paint "$CLR_MUTED" "$(tr_text "Частая причина: в Caddyfile уже есть блоки с теми же доменами. Попробуйте режим полной замены Caddyfile." "Common reason: Caddyfile already has blocks for the same domains. Try full Caddyfile replace mode.")"
    $SUDO cp "$backup_file" "$caddy_file"
    bedolaga_validate_and_reload_caddy >/dev/null 2>&1 || true
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Caddy обновлен: " "Caddy updated: ")${caddy_file}"
  return 0
}
