#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/panel}"
KEEP_DAYS="${KEEP_DAYS:-14}"
MAX_TG_PART_SIZE="${MAX_TG_PART_SIZE:-45M}"
TG_SINGLE_LIMIT_BYTES="${TG_SINGLE_LIMIT_BYTES:-50331648}"
REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BACKUP_ENV_PATH="${BACKUP_ENV_PATH:-/etc/panel-backup.env}"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
WORKDIR="$(mktemp -d /tmp/panel-backup.XXXXXX)"
ARCHIVE_BASE="panel-backup-${HOSTNAME_FQDN}-${TIMESTAMP}"
ARCHIVE_PATH="${BACKUP_ROOT}/${ARCHIVE_BASE}.tar.gz"
LOG_TAG="panel-backup"
declare -a BACKUP_ITEMS=()

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

log() {
  logger -t "$LOG_TAG" "$*"
  echo "$*"
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
  local response
  local thread_args=()

  if [[ -n "${TELEGRAM_THREAD_ID:-}" ]]; then
    thread_args+=(-F "message_thread_id=${TELEGRAM_THREAD_ID}")
  fi

  response="$(curl -sS --max-time 300 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_ADMIN_ID}" \
    "${thread_args[@]}" \
    -F "caption=${caption}" \
    -F "document=@${file_path}")" || return 1

  echo "$response" | grep -q '"ok":true'
}

add_backup_item() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    BACKUP_ITEMS+=("- ${label}: включено ($(du -sh "$path" | awk '{print $1}'))")
  else
    BACKUP_ITEMS+=("- ${label}: не найдено")
  fi
}

fail() {
  local msg="$1"
  log "ERROR: ${msg}"
  send_telegram_text "❌ Бэкап панели: ошибка на ${HOSTNAME_FQDN}
${msg}
Время: ${TIMESTAMP}"
  exit 1
}

if [[ -f "$BACKUP_ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$BACKUP_ENV_PATH"
fi

REMNAWAVE_DIR="${REMNAWAVE_DIR:-$(detect_remnawave_dir || true)}"

[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || fail "не найден TELEGRAM_BOT_TOKEN в ${BACKUP_ENV_PATH}"
[[ -n "${TELEGRAM_ADMIN_ID:-}" ]] || fail "не найден TELEGRAM_ADMIN_ID в ${BACKUP_ENV_PATH}"

[[ -d "$REMNAWAVE_DIR" ]] || fail "не найдена директория ${REMNAWAVE_DIR}"
[[ -f "${REMNAWAVE_DIR}/.env" ]] || fail "не найден ${REMNAWAVE_DIR}/.env"

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
add_backup_item "remnawave/docker-compose.yml" "$WORKDIR/payload/remnawave/docker-compose.yml"
add_backup_item "remnawave/.env" "$WORKDIR/payload/remnawave/.env"
add_backup_item "remnawave/caddy" "$WORKDIR/payload/remnawave/caddy"
add_backup_item "remnawave/subscription" "$WORKDIR/payload/remnawave/subscription"

cat > "$WORKDIR/payload/backup-info.txt" <<INFO
timestamp_utc=${TIMESTAMP}
host=${HOSTNAME_FQDN}
postgres_db=${POSTGRES_DB}
postgres_user=${POSTGRES_USER}
remnawave_image=$(docker inspect remnawave --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
remnawave_caddy_image=$(docker inspect remnawave-caddy --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
INFO

{
  echo "backup_contents:"
  printf '%s\n' "${BACKUP_ITEMS[@]}"
} > "$WORKDIR/payload/backup-manifest.txt"

log "Упаковываю архив"
tar -C "$WORKDIR/payload" -czf "$ARCHIVE_PATH" . || fail "ошибка упаковки архива"
ARCHIVE_SIZE_BYTES="$(stat -c '%s' "$ARCHIVE_PATH")"
ARCHIVE_SIZE_HUMAN="$(du -h "$ARCHIVE_PATH" | awk '{print $1}')"

log "Удаляю старые бэкапы (>${KEEP_DAYS} дней)"
find "$BACKUP_ROOT" -type f \( -name 'panel-backup-*.tar.gz' -o -name 'panel-backup-*.tar.gz.part.*' \) -mtime +"$KEEP_DAYS" -delete || true

send_telegram_text "📦 Бэкап панели создан
Хост: ${HOSTNAME_FQDN}
Файл: $(basename "$ARCHIVE_PATH")
Размер: ${ARCHIVE_SIZE_HUMAN}
Время: ${TIMESTAMP}

Состав бэкапа:
$(printf '%s\n' "${BACKUP_ITEMS[@]}")"

if (( ARCHIVE_SIZE_BYTES <= TG_SINGLE_LIMIT_BYTES )); then
  log "Отправляю архив одним файлом в Telegram"
  send_telegram_file "$ARCHIVE_PATH" "backup ${HOSTNAME_FQDN} ${TIMESTAMP}" \
    || fail "не удалось отправить архив в Telegram"
else
  log "Архив большой, режу на части по ${MAX_TG_PART_SIZE}"
  split -b "$MAX_TG_PART_SIZE" -d -a 3 "$ARCHIVE_PATH" "${ARCHIVE_PATH}.part."
  for part in "${ARCHIVE_PATH}.part."*; do
    send_telegram_file "$part" "backup part ${HOSTNAME_FQDN} $(basename "$part")" \
      || fail "не удалось отправить часть $(basename "$part")"
  done
fi

log "Бэкап и отправка завершены: ${ARCHIVE_PATH} (${ARCHIVE_SIZE_HUMAN})"
send_telegram_text "✅ Бэкап панели отправлен
Хост: ${HOSTNAME_FQDN}
Размер: ${ARCHIVE_SIZE_HUMAN}
Время: ${TIMESTAMP}"
