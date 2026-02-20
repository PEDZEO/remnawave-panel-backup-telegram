#!/usr/bin/env bash
# Bedolaga Caddy runtime detection, templating and reload helpers.

CADDY_MODE=""
CADDY_CONTAINER_NAME=""
CADDY_FILE_PATH=""

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
