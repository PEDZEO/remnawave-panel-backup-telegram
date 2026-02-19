#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/panel}"
KEEP_DAYS="${KEEP_DAYS:-14}"
MAX_TG_PART_SIZE="${MAX_TG_PART_SIZE:-45M}"
TG_SINGLE_LIMIT_BYTES="${TG_SINGLE_LIMIT_BYTES:-50331648}"
REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BACKUP_ENV_PATH="${BACKUP_ENV_PATH:-/etc/panel-backup.env}"
BACKUP_LANG="${BACKUP_LANG:-ru}"
BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-0}"
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TIMESTAMP_SHORT="$(date -u +%m%d-%H%M%S)"
TIMESTAMP_LOCAL="$(date '+%Y-%m-%d %H:%M:%S %Z')"
TIMESTAMP_UTC_HUMAN="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
WORKDIR="$(mktemp -d /tmp/panel-backup.XXXXXX)"
ARCHIVE_BASE="pb-${TIMESTAMP_SHORT}"
ARCHIVE_PATH="${BACKUP_ROOT}/${ARCHIVE_BASE}.tar.gz"
LOG_TAG="panel-backup"
LOCK_FILE="${LOCK_FILE:-/var/lock/panel-backup.lock}"
declare -a BACKUP_ITEMS=()

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

log() {
  logger -t "$LOG_TAG" "$*"
  echo "$*"
}

normalize_backup_lang() {
  case "${BACKUP_LANG,,}" in
    en|eu) BACKUP_LANG="en" ;;
    *) BACKUP_LANG="ru" ;;
  esac
}

normalize_backup_encrypt() {
  case "${BACKUP_ENCRYPT,,}" in
    1|true|yes|on|y|да) BACKUP_ENCRYPT="1" ;;
    *) BACKUP_ENCRYPT="0" ;;
  esac
}

t() {
  local ru="$1"
  local en="$2"
  if [[ "$BACKUP_LANG" == "en" ]]; then
    printf '%s' "$en"
  else
    printf '%s' "$ru"
  fi
}

detect_remnawave_dir() {
  local guessed
  for guessed in "${REMNAWAVE_DIR}" "/opt/remnawave" "/srv/remnawave" "/root/remnawave" "/home/remnawave"; do
    [[ -n "$guessed" ]] || continue
    if [[ -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(docker inspect remnawave --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
  if [[ -n "$guessed" && -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /opt /srv /root /home -maxdepth 3 -type f -name '.env' 2>/dev/null | while read -r f; do d="$(dirname "$f")"; [[ -f "$d/docker-compose.yml" ]] || continue; grep -q '^POSTGRES_USER=' "$f" 2>/dev/null || continue; grep -q '^POSTGRES_DB=' "$f" 2>/dev/null || continue; echo "$d"; break; done)"
  [[ -n "$guessed" ]] && echo "$guessed"
}

container_image_ref() {
  local name="$1"
  docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null || true
}

container_version_label() {
  local name="$1"
  local tail=""
  local image_ref=""
  local image_id=""
  local version=""
  local revision=""
  local env_version=""

  image_ref="$(container_image_ref "$name")"
  image_id="$(docker inspect -f '{{.Image}}' "$name" 2>/dev/null || true)"

  if [[ -n "$image_id" ]]; then
    version="$(docker image inspect -f '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$image_id" 2>/dev/null || true)"
    [[ "$version" == "<no value>" ]] && version=""
    if [[ -z "$version" ]]; then
      version="$(docker image inspect -f '{{ index .Config.Labels "org.label-schema.version" }}' "$image_id" 2>/dev/null || true)"
      [[ "$version" == "<no value>" ]] && version=""
    fi
    if [[ -z "$version" ]]; then
      revision="$(docker image inspect -f '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image_id" 2>/dev/null || true)"
      [[ "$revision" == "<no value>" ]] && revision=""
      if [[ -n "$revision" ]]; then
        if [[ ${#revision} -gt 12 ]]; then
          version="${revision:0:12}"
        else
          version="$revision"
        fi
      fi
    fi
  fi

  if [[ -z "$version" && -n "$image_ref" ]]; then
    tail="${image_ref##*/}"
    if [[ "$tail" == *:* ]]; then
      version="${tail##*:}"
      if [[ "$version" == "latest" ]]; then
        version=""
      fi
    fi
  fi

  if [[ -z "$version" ]]; then
    env_version="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null | awk -F= '
      $1=="__RW_METADATA_VERSION" {print $2; exit}
      $1=="REMNAWAVE_VERSION" {print $2; exit}
      $1=="SUBSCRIPTION_VERSION" {print $2; exit}
      $1=="APP_VERSION" {print $2; exit}
    ' || true)"
    if [[ -n "$env_version" ]]; then
      version="$env_version"
    fi
  fi

  if [[ -n "$version" ]]; then
    printf '%s' "$version"
    return 0
  fi

  if [[ -n "$image_id" ]]; then
    image_id="${image_id#sha256:}"
    printf '%s' "sha-${image_id:0:12}"
    return 0
  fi

  if [[ -z "$image_ref" ]]; then
    printf '%s' "unknown"
    return 0
  fi

  tail="${image_ref##*/}"
  if [[ "$tail" == *:* ]]; then
    printf '%s' "${tail##*:}"
    return 0
  fi
  if [[ "$tail" == *@* ]]; then
    printf '%s' "${tail##*@}"
    return 0
  fi
  printf '%s' "$tail"
}

send_telegram_text() {
  local text="$1"
  local thread_args=()
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_ADMIN_ID:-}" ]]; then
    return 0
  fi
  if [[ -n "${TELEGRAM_THREAD_ID:-}" ]]; then
    thread_args+=(-d "message_thread_id=${TELEGRAM_THREAD_ID}")
  fi
  curl -sS --max-time 20 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_ADMIN_ID}" \
    "${thread_args[@]}" \
    --data-urlencode "text=${text}" \
    >/dev/null || true
}

send_telegram_file() {
  local file_path="$1"
  local caption="$2"
  local fallback_caption=""
  local response
  local thread_args=()

  if [[ -n "${TELEGRAM_THREAD_ID:-}" ]]; then
    thread_args+=(-F "message_thread_id=${TELEGRAM_THREAD_ID}")
  fi

  response="$(curl -sS --max-time 300 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_ADMIN_ID}" \
    "${thread_args[@]}" \
    -F "parse_mode=HTML" \
    -F "caption=${caption}" \
    -F "document=@${file_path}")" || return 1

  if echo "$response" | grep -q '"ok":true'; then
    return 0
  fi

  log "$(t "Предупреждение: Telegram отклонил HTML-caption, пробую безопасный текстовый caption" "Warning: Telegram rejected HTML caption, trying safe plain-text caption")"
  fallback_caption="$(build_caption_plain "$(basename "$file_path")")"
  response="$(curl -sS --max-time 300 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_ADMIN_ID}" \
    "${thread_args[@]}" \
    -F "caption=${fallback_caption}" \
    -F "document=@${file_path}")" || return 1

  echo "$response" | grep -q '"ok":true'
}

escape_html() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

add_backup_item() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    BACKUP_ITEMS+=("- ${label}: $(t "включено" "included") ($(du -sh "$path" | awk '{print $1}'))")
  else
    BACKUP_ITEMS+=("- ${label}: $(t "не найдено" "not found")")
  fi
}

fail() {
  local msg="$1"
  log "ERROR: ${msg}"
  send_telegram_text "ERROR: $(t "Ошибка backup панели" "Panel backup error"): ${HOSTNAME_FQDN}
${msg}
$(t "Время (локальное):" "Time (local):") ${TIMESTAMP_LOCAL}
$(t "Время (UTC):" "Time (UTC):") ${TIMESTAMP_UTC_HUMAN}"
  exit 1
}

ensure_dependencies() {
  local cmd=""
  for cmd in docker tar curl split du stat find awk grep sed flock; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$(t "не найдена команда" "missing command"): $cmd"
  done
  if [[ "${BACKUP_ENCRYPT:-0}" == "1" ]]; then
    command -v gpg >/dev/null 2>&1 || fail "$(t "не найдена команда" "missing command"): gpg"
  fi
}

check_container_present() {
  local name="$1"
  docker inspect "$name" >/dev/null 2>&1 || fail "$(t "контейнер не найден" "container not found"): $name"
}

estimate_required_bytes() {
  local rem_size=0
  local safety_bytes=$((200 * 1024 * 1024))
  rem_size="$(du -sb "$REMNAWAVE_DIR" 2>/dev/null | awk '{print $1}' || echo 0)"
  if [[ ! "$rem_size" =~ ^[0-9]+$ ]]; then
    rem_size=0
  fi
  echo $((rem_size + safety_bytes))
}

available_backup_root_bytes() {
  df -Pk "$BACKUP_ROOT" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' || echo 0
}

preflight_checks() {
  local need_bytes=0
  local free_bytes=0

  ensure_dependencies
  check_container_present remnawave-db
  check_container_present remnawave-redis
  check_container_present remnawave

  mkdir -p "$BACKUP_ROOT"
  need_bytes="$(estimate_required_bytes)"
  free_bytes="$(available_backup_root_bytes)"

  if [[ "$need_bytes" =~ ^[0-9]+$ && "$free_bytes" =~ ^[0-9]+$ ]]; then
    if (( free_bytes < need_bytes )); then
      fail "$(t "недостаточно места для backup" "not enough free disk space for backup"): $(t "нужно" "need") ${need_bytes} $(t "байт, доступно" "bytes, available") ${free_bytes}"
    fi
  fi
}

normalize_env_file_format() {
  local fix_pattern='^BACKUP_ON_CALENDAR=[^"].* [^"].*$'
  if [[ ! -f "$BACKUP_ENV_PATH" ]]; then
    return 0
  fi
  if grep -qE "$fix_pattern" "$BACKUP_ENV_PATH" 2>/dev/null; then
    sed -i -E 's/^BACKUP_ON_CALENDAR=(.*)$/BACKUP_ON_CALENDAR="\1"/' "$BACKUP_ENV_PATH"
  fi
}

build_caption() {
  local file_label="$1"
  local file_label_e=""
  local host_e=""
  local time_e=""
  local size_e=""
  local panel_e=""
  local sub_e=""
  local enc_label=""
  file_label_e="$(escape_html "$file_label")"
  host_e="$(escape_html "$HOSTNAME_FQDN")"
  time_e="$(escape_html "$TIMESTAMP_LOCAL")"
  size_e="$(escape_html "$ARCHIVE_SIZE_HUMAN")"
  panel_e="$(escape_html "$PANEL_VERSION")"
  sub_e="$(escape_html "$SUBSCRIPTION_VERSION")"

  if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
    enc_label="$(t "включено (GPG)" "enabled (GPG)")"
  else
    enc_label="$(t "выключено" "disabled")"
  fi

  printf '%s' "📦 <b>Backup Remnawave</b>
📁 <b>$(t "Файл" "File"):</b> <code>${file_label_e}</code>
🖥 <b>$(t "Хост" "Host"):</b> <code>${host_e}</code>
🕒 <b>$(t "Время" "Time"):</b> <code>${time_e}</code>
📏 <b>$(t "Размер" "Size"):</b> <code>${size_e}</code>
🧩 <b>$(t "Версия панели" "Panel version"):</b> <code>${panel_e}</code>
🧷 <b>$(t "Версия подписки" "Subscription version"):</b> <code>${sub_e}</code>
🔐 <b>$(t "Шифрование" "Encryption"):</b> <code>${enc_label}</code>
📋 <b>$(t "Состав" "Contents"):</b> PostgreSQL, Redis, .env, compose, caddy, subscription"
}

build_caption_plain() {
  local file_label="$1"
  local enc_label=""

  if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
    enc_label="$(t "включено (GPG)" "enabled (GPG)")"
  else
    enc_label="$(t "выключено" "disabled")"
  fi

  printf '%s' "Backup Remnawave
$(t "Файл" "File"): ${file_label}
$(t "Хост" "Host"): ${HOSTNAME_FQDN}
$(t "Время" "Time"): ${TIMESTAMP_LOCAL}
$(t "Размер" "Size"): ${ARCHIVE_SIZE_HUMAN}
$(t "Версия панели" "Panel version"): ${PANEL_VERSION}
$(t "Версия подписки" "Subscription version"): ${SUBSCRIPTION_VERSION}
$(t "Шифрование" "Encryption"): ${enc_label}
$(t "Состав" "Contents"): PostgreSQL, Redis, .env, compose, caddy, subscription"
}

normalize_env_file_format
if [[ -f "$BACKUP_ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$BACKUP_ENV_PATH"
fi
normalize_backup_lang
normalize_backup_encrypt

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  fail "$(t "backup уже выполняется (блокировка активна)" "backup is already running (lock is active)")"
fi

REMNAWAVE_DIR="${REMNAWAVE_DIR:-$(detect_remnawave_dir || true)}"
PANEL_VERSION="$(container_version_label remnawave)"
SUBSCRIPTION_VERSION="$(container_version_label remnawave-subscription-page)"

[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || fail "не найден TELEGRAM_BOT_TOKEN в ${BACKUP_ENV_PATH}"
[[ -n "${TELEGRAM_ADMIN_ID:-}" ]] || fail "не найден TELEGRAM_ADMIN_ID в ${BACKUP_ENV_PATH}"

[[ -d "$REMNAWAVE_DIR" ]] || fail "не найдена директория ${REMNAWAVE_DIR}"
[[ -f "${REMNAWAVE_DIR}/.env" ]] || fail "не найден ${REMNAWAVE_DIR}/.env"
preflight_checks

POSTGRES_USER="$(grep -E '^POSTGRES_USER=' "${REMNAWAVE_DIR}/.env" | head -n1 | cut -d= -f2-)"
POSTGRES_DB="$(grep -E '^POSTGRES_DB=' "${REMNAWAVE_DIR}/.env" | head -n1 | cut -d= -f2-)"
[[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]] || fail "не удалось прочитать POSTGRES_USER/POSTGRES_DB"

mkdir -p "$BACKUP_ROOT"
mkdir -p "$WORKDIR/payload/remnawave"

log "Создаю дамп PostgreSQL (${POSTGRES_DB})"
docker exec remnawave-db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -Z9 > "$WORKDIR/payload/remnawave-db.dump" \
  || fail "ошибка pg_dump remnawave-db"
BACKUP_ITEMS+=("- PostgreSQL dump: включено ($(du -h "$WORKDIR/payload/remnawave-db.dump" | awk '{print $1}'))")

log "Сохраняю Redis dump"
docker exec remnawave-redis sh -lc 'valkey-cli save >/dev/null 2>&1 || redis-cli save >/dev/null 2>&1 || true' || true
docker cp remnawave-redis:/data/dump.rdb "$WORKDIR/payload/remnawave-redis.rdb" 2>/dev/null || true
if [[ -f "$WORKDIR/payload/remnawave-redis.rdb" ]]; then
  BACKUP_ITEMS+=("- Redis dump: включено ($(du -h "$WORKDIR/payload/remnawave-redis.rdb" | awk '{print $1}'))")
else
  BACKUP_ITEMS+=("- Redis dump: не найден или не создан")
fi

log "Копирую конфиги Remnawave"
cp -a "${REMNAWAVE_DIR}/docker-compose.yml" "$WORKDIR/payload/remnawave/" 2>/dev/null || true
cp -a "${REMNAWAVE_DIR}/.env" "$WORKDIR/payload/remnawave/" 2>/dev/null || true
cp -a "${REMNAWAVE_DIR}/caddy" "$WORKDIR/payload/remnawave/" 2>/dev/null || true
cp -a "${REMNAWAVE_DIR}/subscription" "$WORKDIR/payload/remnawave/" 2>/dev/null || true
add_backup_item "Docker Compose (remnawave/docker-compose.yml)" "$WORKDIR/payload/remnawave/docker-compose.yml"
add_backup_item "ENV (remnawave/.env)" "$WORKDIR/payload/remnawave/.env"
add_backup_item "Caddy config (remnawave/caddy)" "$WORKDIR/payload/remnawave/caddy"
add_backup_item "Subscription page (remnawave/subscription)" "$WORKDIR/payload/remnawave/subscription"

cat > "$WORKDIR/payload/backup-info.txt" <<INFO
timestamp_utc=${TIMESTAMP}
host=${HOSTNAME_FQDN}
postgres_db=${POSTGRES_DB}
postgres_user=${POSTGRES_USER}
remnawave_image=$(docker inspect remnawave --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
remnawave_caddy_image=$(docker inspect remnawave-caddy --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
panel_version=${PANEL_VERSION}
subscription_version=${SUBSCRIPTION_VERSION}
INFO

{
  echo "backup_contents:"
  printf '%s\n' "${BACKUP_ITEMS[@]}"
} > "$WORKDIR/payload/backup-manifest.txt"

log "Упаковываю архив"
tar -C "$WORKDIR/payload" -czf "$ARCHIVE_PATH" . || fail "ошибка упаковки архива"

if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
  [[ -n "${BACKUP_PASSWORD:-}" ]] || fail "$(t "включено шифрование, но не задан BACKUP_PASSWORD" "encryption is enabled but BACKUP_PASSWORD is not set")"
  log "$(t "Шифрую архив (GPG symmetric)" "Encrypting archive (GPG symmetric)")"
  gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSWORD" \
    --cipher-algo AES256 --symmetric --output "${ARCHIVE_PATH}.gpg" "$ARCHIVE_PATH" \
    || fail "$(t "ошибка шифрования архива" "archive encryption failed")"
  rm -f "$ARCHIVE_PATH"
  ARCHIVE_PATH="${ARCHIVE_PATH}.gpg"
fi

ARCHIVE_SIZE_BYTES="$(stat -c '%s' "$ARCHIVE_PATH")"
ARCHIVE_SIZE_HUMAN="$(du -h "$ARCHIVE_PATH" | awk '{print $1}')"

log "Удаляю старые бэкапы (>${KEEP_DAYS} дней)"
find "$BACKUP_ROOT" -type f \( -name 'pb-*.tar.gz' -o -name 'pb-*.tar.gz.gpg' -o -name 'pb-*.tar.gz.part.*' -o -name 'pb-*.tar.gz.gpg.part.*' -o -name 'panel-backup-*.tar.gz' -o -name 'panel-backup-*.tar.gz.gpg' -o -name 'panel-backup-*.tar.gz.part.*' -o -name 'panel-backup-*.tar.gz.gpg.part.*' \) -mtime +"$KEEP_DAYS" -delete || true

if (( ARCHIVE_SIZE_BYTES <= TG_SINGLE_LIMIT_BYTES )); then
  log "Отправляю архив одним файлом в Telegram"
  send_telegram_file "$ARCHIVE_PATH" "$(build_caption "$(basename "$ARCHIVE_PATH")")" \
    || fail "не удалось отправить архив в Telegram"
else
  log "Архив большой, режу на части по ${MAX_TG_PART_SIZE}"
  split -b "$MAX_TG_PART_SIZE" -d -a 3 "$ARCHIVE_PATH" "${ARCHIVE_PATH}.part."
  for part in "${ARCHIVE_PATH}.part."*; do
    send_telegram_file "$part" "$(build_caption "$(basename "$part")")" \
      || fail "не удалось отправить часть $(basename "$part")"
  done
fi

log "Бэкап и отправка завершены: ${ARCHIVE_PATH} (${ARCHIVE_SIZE_HUMAN})"
