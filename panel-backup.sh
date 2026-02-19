#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/panel}"
KEEP_DAYS="${KEEP_DAYS:-14}"
MAX_TG_PART_SIZE="${MAX_TG_PART_SIZE:-45M}"
TG_SINGLE_LIMIT_BYTES="${TG_SINGLE_LIMIT_BYTES:-50331648}"
REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BACKUP_ENV_PATH="${BACKUP_ENV_PATH:-/etc/panel-backup.env}"
BACKUP_LANG="${BACKUP_LANG:-ru}"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TIMESTAMP_SHORT="$(date -u +%m%d-%H%M%S)"
TIMESTAMP_LOCAL="$(date '+%Y-%m-%d %H:%M:%S %Z')"
TIMESTAMP_UTC_HUMAN="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
WORKDIR="$(mktemp -d /tmp/panel-backup.XXXXXX)"
ARCHIVE_BASE="pb-${TIMESTAMP_SHORT}"
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

normalize_backup_lang() {
  case "${BACKUP_LANG,,}" in
    en|eu) BACKUP_LANG="en" ;;
    *) BACKUP_LANG="ru" ;;
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
    BACKUP_ITEMS+=("- ${label}: $(t "включено" "included") ($(du -sh "$path" | awk '{print $1}'))")
  else
    BACKUP_ITEMS+=("- ${label}: $(t "не найдено" "not found")")
  fi
}

fail() {
  local msg="$1"
  log "ERROR: ${msg}"
  send_telegram_text "❌ $(t "Ошибка backup панели" "Panel backup error"): ${HOSTNAME_FQDN}
${msg}
$(t "Время (локальное):" "Time (local):") ${TIMESTAMP_LOCAL}
$(t "Время (UTC):" "Time (UTC):") ${TIMESTAMP_UTC_HUMAN}"
  exit 1
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
  printf '%s' "📦 ${file_label}
$(t "Хост" "Host"): ${HOSTNAME_FQDN}
$(t "Время" "Time"): ${TIMESTAMP_LOCAL}
$(t "Размер" "Size"): ${ARCHIVE_SIZE_HUMAN}
$(t "Версия панели" "Panel version"): ${PANEL_VERSION}
$(t "Версия подписки" "Subscription version"): ${SUBSCRIPTION_VERSION}
$(t "Состав" "Contents"): PostgreSQL, Redis, .env, compose, caddy, subscription"
}

normalize_env_file_format
if [[ -f "$BACKUP_ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$BACKUP_ENV_PATH"
fi
normalize_backup_lang

REMNAWAVE_DIR="${REMNAWAVE_DIR:-$(detect_remnawave_dir || true)}"
PANEL_VERSION="$(container_version_label remnawave)"
SUBSCRIPTION_VERSION="$(container_version_label remnawave-subscription-page)"

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
ARCHIVE_SIZE_BYTES="$(stat -c '%s' "$ARCHIVE_PATH")"
ARCHIVE_SIZE_HUMAN="$(du -h "$ARCHIVE_PATH" | awk '{print $1}')"

log "Удаляю старые бэкапы (>${KEEP_DAYS} дней)"
find "$BACKUP_ROOT" -type f \( -name 'pb-*.tar.gz' -o -name 'pb-*.tar.gz.part.*' -o -name 'panel-backup-*.tar.gz' -o -name 'panel-backup-*.tar.gz.part.*' \) -mtime +"$KEEP_DAYS" -delete || true

send_telegram_text "📦 $(t "Backup панели создан" "Panel backup created")
$(t "Хост" "Host"): ${HOSTNAME_FQDN}
$(t "Файл" "File"): $(basename "$ARCHIVE_PATH")
$(t "Размер" "Size"): ${ARCHIVE_SIZE_HUMAN}
$(t "Время (локальное)" "Time (local)"): ${TIMESTAMP_LOCAL}
$(t "Время (UTC)" "Time (UTC)"): ${TIMESTAMP_UTC_HUMAN}
$(t "Версия панели" "Panel version"): ${PANEL_VERSION}
$(t "Версия подписки" "Subscription version"): ${SUBSCRIPTION_VERSION}
$(t "Описание" "Description"): PostgreSQL + Redis + Remnawave configs

$(t "Состав бэкапа" "Backup contents"):
$(printf '%s\n' "${BACKUP_ITEMS[@]}")"

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
send_telegram_text "✅ $(t "Backup панели отправлен" "Panel backup sent")
$(t "Хост" "Host"): ${HOSTNAME_FQDN}
$(t "Размер" "Size"): ${ARCHIVE_SIZE_HUMAN}
$(t "Время (локальное)" "Time (local)"): ${TIMESTAMP_LOCAL}
$(t "Время (UTC)" "Time (UTC)"): ${TIMESTAMP_UTC_HUMAN}
$(t "Версия панели" "Panel version"): ${PANEL_VERSION}
$(t "Версия подписки" "Subscription version"): ${SUBSCRIPTION_VERSION}
$(t "Описание" "Description"): $(t "архив отправлен в Telegram" "archive was sent to Telegram")"
