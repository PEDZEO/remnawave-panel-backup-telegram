#!/usr/bin/env bash
# update: runtime restore flow applies selected components from backup archive.
set -euo pipefail

REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-}"
BEDOLAGA_CABINET_DIR="${BEDOLAGA_CABINET_DIR:-}"
PRE_RESTORE_BACKUP_ROOT="${PRE_RESTORE_BACKUP_ROOT:-/var/backups/panel-restore-pre}"
BACKUP_ENV_PATH="${BACKUP_ENV_PATH:-/etc/panel-backup.env}"
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"
NO_RESTART=0
DRY_RUN=0
ARCHIVE_PATH=""
declare -a ONLY_RAW=()
declare -A WANT=()

usage() {
  cat <<USAGE
Usage:
  panel-restore.sh --from /path/to/panel-backup-*.tar.gz|*.tar.gz.gpg [--only COMPONENT] [--dry-run] [--no-restart]

Components:
  all               restore panel stack (db + redis + env + compose + caddy + subscription)
  db                restore panel PostgreSQL dump
  redis             restore panel Redis dump.rdb
  configs           restore panel config files (env + compose + caddy + subscription)
  env               restore /opt/remnawave/.env
  compose           restore /opt/remnawave/docker-compose.yml
  caddy             restore /opt/remnawave/caddy/
  subscription      restore /opt/remnawave/subscription/
  bedolaga          restore Bedolaga stack (bot db + bot redis + bot configs + cabinet configs)
  bedolaga-db       restore Bedolaga bot PostgreSQL dump
  bedolaga-redis    restore Bedolaga bot Redis dump.rdb
  bedolaga-bot      restore /root/remnawave-bedolaga-telegram-bot config/data
  bedolaga-cabinet  restore /root/bedolaga-cabinet config
  bedolaga-configs  restore Bedolaga configs (bot + cabinet)

Examples:
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz.gpg --only db --only redis
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz --only configs --dry-run
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/pb-0221-120000.tar.gz --only all,bedolaga
USAGE
}

log() {
  echo "$*"
  logger -t panel-restore "$*"
}

detect_remnawave_dir() {
  local guessed
  local name

  is_remnawave_panel_dir() {
    local d="$1"
    local compose_file="$d/docker-compose.yml"
    [[ -f "$d/.env" && -f "$compose_file" ]] || return 1

    if grep -Eq 'container_name:[[:space:]]*remnawave_bot(_db|_redis)?([[:space:]]|$)' "$compose_file"; then
      return 1
    fi

    if grep -Eq 'container_name:[[:space:]]*remnawave-(db|redis|caddy|subscription-page)([[:space:]]|$)' "$compose_file"; then
      return 0
    fi

    [[ -d "$d/caddy" || -d "$d/subscription" ]] || return 1
    return 0
  }

  detect_compose_workdir_by_container_names() {
    local n=""
    local wd=""
    for n in "$@"; do
      [[ -n "$n" ]] || continue
      wd="$(docker inspect "$n" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
      [[ -n "$wd" ]] || continue
      echo "$wd"
      return 0
    done
    return 1
  }

  for guessed in "${REMNAWAVE_DIR}" "/opt/remnawave" "/srv/remnawave" "/root/remnawave" "/home/remnawave"; do
    [[ -n "$guessed" ]] || continue
    if is_remnawave_panel_dir "$guessed"; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(detect_compose_workdir_by_container_names \
    remnawave remnawave-db remnawave-redis remnawave-caddy remnawave-subscription-page \
    remnawave_db remnawave_redis remnawave_caddy remnawave_subscription_page || true)"
  if [[ -n "$guessed" ]] && is_remnawave_panel_dir "$guessed"; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /opt /srv /root /home -maxdepth 4 -type f -name '.env' 2>/dev/null | while read -r f; do d="$(dirname "$f")"; is_remnawave_panel_dir "$d" || continue; echo "$d"; break; done)"
  [[ -n "$guessed" ]] && echo "$guessed"
}

detect_bedolaga_bot_dir() {
  local guessed=""

  detect_compose_workdir_by_container_names() {
    local name=""
    local wd=""
    for name in "$@"; do
      [[ -n "$name" ]] || continue
      wd="$(docker inspect "$name" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
      [[ -n "$wd" ]] || continue
      echo "$wd"
      return 0
    done
    return 1
  }
  for guessed in "${BEDOLAGA_BOT_DIR}" "/root/remnawave-bedolaga-telegram-bot" "/opt/remnawave-bedolaga-telegram-bot"; do
    [[ -n "$guessed" ]] || continue
    if [[ -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(detect_compose_workdir_by_container_names remnawave_bot remnawave-bot remnawave_bot_db remnawave_bot_redis || true)"
  if [[ -n "$guessed" && -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 6 -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do [[ -f "$d/.env" && -f "$d/docker-compose.yml" ]] || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find / -xdev -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do [[ -f "$d/.env" && -f "$d/docker-compose.yml" ]] || continue; echo "$d"; break; done)"
  [[ -n "$guessed" ]] && echo "$guessed"
}

detect_bedolaga_cabinet_dir() {
  is_bedolaga_cabinet_dir() {
    local d="$1"
    [[ -f "$d/.env" ]] || return 1
    [[ -f "$d/docker-compose.yml" || -f "$d/package.json" ]] || return 1
    return 0
  }

  local guessed=""

  detect_compose_workdir_by_container_names() {
    local name=""
    local wd=""
    for name in "$@"; do
      [[ -n "$name" ]] || continue
      wd="$(docker inspect "$name" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
      [[ -n "$wd" ]] || continue
      echo "$wd"
      return 0
    done
    return 1
  }
  for guessed in "${BEDOLAGA_CABINET_DIR}" "/root/bedolaga-cabinet" "/root/cabinet-frontend" "/opt/bedolaga-cabinet" "/opt/cabinet-frontend"; do
    [[ -n "$guessed" ]] || continue
    if is_bedolaga_cabinet_dir "$guessed"; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(detect_compose_workdir_by_container_names cabinet_frontend cabinet-frontend bedolaga-cabinet || true)"
  if [[ -n "$guessed" ]] && is_bedolaga_cabinet_dir "$guessed"; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 6 -type d \( -name 'cabinet-frontend' -o -name 'bedolaga-cabinet' \) 2>/dev/null | while read -r d; do is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find / -xdev -type d \( -name 'cabinet-frontend' -o -name 'bedolaga-cabinet' \) 2>/dev/null | while read -r d; do is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
  [[ -n "$guessed" ]] && echo "$guessed"
}

run_cmd() {
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] $*"
  else
    eval "$*"
  fi
}

backup_info_value() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

ensure_dir() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] mkdir -p \"$path\""
  else
    mkdir -p "$path"
  fi
}

container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' | grep -qx "$name"
}

component_selected() {
  local name="$1"
  [[ -n "${WANT[$name]:-}" ]]
}

expand_component() {
  local c="$1"
  case "$c" in
    all)
      WANT[db]=1
      WANT[redis]=1
      WANT[env]=1
      WANT[compose]=1
      WANT[caddy]=1
      WANT[subscription]=1
      ;;
    configs)
      WANT[env]=1
      WANT[compose]=1
      WANT[caddy]=1
      WANT[subscription]=1
      ;;
    bedolaga)
      WANT[bedolaga-db]=1
      WANT[bedolaga-redis]=1
      WANT[bedolaga-bot]=1
      WANT[bedolaga-cabinet]=1
      ;;
    bedolaga-configs)
      WANT[bedolaga-bot]=1
      WANT[bedolaga-cabinet]=1
      ;;
    db|redis|env|compose|caddy|subscription|bedolaga-db|bedolaga-redis|bedolaga-bot|bedolaga-cabinet)
      WANT["$c"]=1
      ;;
    *)
      echo "Unknown component: $c" >&2
      usage
      exit 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    --only)
      ONLY_RAW+=("${2:-}")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-restart)
      NO_RESTART=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -n "$ARCHIVE_PATH" ]] || { echo "--from is required" >&2; usage; exit 1; }
[[ -f "$ARCHIVE_PATH" ]] || { echo "Archive not found: $ARCHIVE_PATH" >&2; exit 1; }
if [[ -f "$BACKUP_ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$BACKUP_ENV_PATH"
fi

if [[ ${#ONLY_RAW[@]} -eq 0 ]]; then
  expand_component all
else
  for item in "${ONLY_RAW[@]}"; do
    IFS=',' read -r -a split_items <<< "$item"
    for c in "${split_items[@]}"; do
      c="$(echo "$c" | xargs)"
      [[ -n "$c" ]] && expand_component "$c"
    done
  done
fi

need_remnawave=0
need_bedolaga_bot=0
need_bedolaga_cabinet=0

if component_selected db || component_selected redis || component_selected env || component_selected compose || component_selected caddy || component_selected subscription; then
  need_remnawave=1
fi
if component_selected bedolaga-db || component_selected bedolaga-redis || component_selected bedolaga-bot; then
  need_bedolaga_bot=1
fi
if component_selected bedolaga-cabinet; then
  need_bedolaga_cabinet=1
fi

remnawave_dir_existed=0
bedolaga_bot_dir_existed=0
bedolaga_cabinet_dir_existed=0

TMP_DIR="$(mktemp -d /tmp/panel-restore.XXXXXX)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

ARCHIVE_TO_EXTRACT="$ARCHIVE_PATH"
if [[ "$ARCHIVE_PATH" == *.gpg ]]; then
  [[ -n "${BACKUP_PASSWORD:-}" ]] || { echo "BACKUP_PASSWORD is required for encrypted archive" >&2; exit 1; }
  command -v gpg >/dev/null 2>&1 || { echo "gpg command is required for encrypted archive" >&2; exit 1; }
  ARCHIVE_TO_EXTRACT="$TMP_DIR/decrypted.tar.gz"
  log "Decrypt archive: $ARCHIVE_PATH"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] gpg --batch --yes --pinentry-mode loopback --passphrase ***** --decrypt \"$ARCHIVE_PATH\" > \"$ARCHIVE_TO_EXTRACT\""
  fi
  gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSWORD" \
    --decrypt "$ARCHIVE_PATH" > "$ARCHIVE_TO_EXTRACT"
fi

log "Extract archive: $ARCHIVE_TO_EXTRACT"
if (( DRY_RUN == 1 )); then
  echo "[dry-run] tar -xzf \"$ARCHIVE_TO_EXTRACT\" -C \"$EXTRACT_DIR\""
fi
tar -xzf "$ARCHIVE_TO_EXTRACT" -C "$EXTRACT_DIR"

DB_DUMP="$EXTRACT_DIR/remnawave-db.dump"
REDIS_DUMP="$EXTRACT_DIR/remnawave-redis.rdb"
SRC_REMNAWAVE="$EXTRACT_DIR/remnawave"
BEDOLAGA_DB_DUMP="$EXTRACT_DIR/bedolaga-bot-db.dump"
BEDOLAGA_REDIS_DUMP="$EXTRACT_DIR/bedolaga-bot-redis.rdb"
SRC_BEDOLAGA_BOT="$EXTRACT_DIR/bedolaga/bot"
SRC_BEDOLAGA_CABINET="$EXTRACT_DIR/bedolaga/cabinet"
BACKUP_INFO_PATH="$EXTRACT_DIR/backup-info.txt"

BACKUP_REMNAWAVE_DIR="$(backup_info_value remnawave_dir "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_BOT_DIR="$(backup_info_value bedolaga_bot_dir "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_CABINET_DIR="$(backup_info_value bedolaga_cabinet_dir "$BACKUP_INFO_PATH")"
BACKUP_POSTGRES_USER="$(backup_info_value postgres_user "$BACKUP_INFO_PATH")"
BACKUP_POSTGRES_DB="$(backup_info_value postgres_db "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_POSTGRES_USER="$(backup_info_value bedolaga_postgres_user "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_POSTGRES_DB="$(backup_info_value bedolaga_postgres_db "$BACKUP_INFO_PATH")"

need_remnawave_dir=0
need_bedolaga_bot_dir=0
need_bedolaga_cabinet_dir=0
if component_selected env || component_selected compose || component_selected caddy || component_selected subscription; then
  need_remnawave_dir=1
fi
if component_selected bedolaga-bot; then
  need_bedolaga_bot_dir=1
fi
if component_selected bedolaga-cabinet; then
  need_bedolaga_cabinet_dir=1
fi

if (( need_remnawave_dir == 1 )); then
  REMNAWAVE_DIR="${REMNAWAVE_DIR:-$(detect_remnawave_dir || true)}"
  if [[ -n "$REMNAWAVE_DIR" && ! -d "$REMNAWAVE_DIR" ]]; then
    detected_remnawave_dir="$(detect_remnawave_dir || true)"
    if [[ -n "$detected_remnawave_dir" && "$detected_remnawave_dir" != "$REMNAWAVE_DIR" ]]; then
      log "WARNING: REMNAWAVE_DIR does not exist, using detected path: $detected_remnawave_dir"
      REMNAWAVE_DIR="$detected_remnawave_dir"
    fi
  fi
  [[ -n "$REMNAWAVE_DIR" ]] || REMNAWAVE_DIR="$BACKUP_REMNAWAVE_DIR"
  [[ -n "$REMNAWAVE_DIR" ]] || { echo "Cannot detect remnawave dir. Set REMNAWAVE_DIR or restore archive with backup-info.txt" >&2; exit 1; }
  [[ -d "$REMNAWAVE_DIR" ]] && remnawave_dir_existed=1
  ensure_dir "$REMNAWAVE_DIR"
fi
if (( need_bedolaga_bot_dir == 1 )); then
  BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-$(detect_bedolaga_bot_dir || true)}"
  if [[ -n "$BEDOLAGA_BOT_DIR" && ! -d "$BEDOLAGA_BOT_DIR" ]]; then
    detected_bedolaga_bot_dir="$(detect_bedolaga_bot_dir || true)"
    if [[ -n "$detected_bedolaga_bot_dir" && "$detected_bedolaga_bot_dir" != "$BEDOLAGA_BOT_DIR" ]]; then
      log "WARNING: BEDOLAGA_BOT_DIR does not exist, using detected path: $detected_bedolaga_bot_dir"
      BEDOLAGA_BOT_DIR="$detected_bedolaga_bot_dir"
    fi
  fi
  [[ -n "$BEDOLAGA_BOT_DIR" ]] || BEDOLAGA_BOT_DIR="$BACKUP_BEDOLAGA_BOT_DIR"
  [[ -n "$BEDOLAGA_BOT_DIR" ]] || { echo "Cannot detect Bedolaga bot dir. Set BEDOLAGA_BOT_DIR or restore archive with backup-info.txt" >&2; exit 1; }
  [[ -d "$BEDOLAGA_BOT_DIR" ]] && bedolaga_bot_dir_existed=1
  ensure_dir "$BEDOLAGA_BOT_DIR"
fi
if (( need_bedolaga_cabinet_dir == 1 )); then
  BEDOLAGA_CABINET_DIR="${BEDOLAGA_CABINET_DIR:-$(detect_bedolaga_cabinet_dir || true)}"
  if [[ -n "$BEDOLAGA_CABINET_DIR" && ! -d "$BEDOLAGA_CABINET_DIR" ]]; then
    detected_bedolaga_cabinet_dir="$(detect_bedolaga_cabinet_dir || true)"
    if [[ -n "$detected_bedolaga_cabinet_dir" && "$detected_bedolaga_cabinet_dir" != "$BEDOLAGA_CABINET_DIR" ]]; then
      log "WARNING: BEDOLAGA_CABINET_DIR does not exist, using detected path: $detected_bedolaga_cabinet_dir"
      BEDOLAGA_CABINET_DIR="$detected_bedolaga_cabinet_dir"
    fi
  fi
  [[ -n "$BEDOLAGA_CABINET_DIR" ]] || BEDOLAGA_CABINET_DIR="$BACKUP_BEDOLAGA_CABINET_DIR"
  [[ -n "$BEDOLAGA_CABINET_DIR" ]] || { echo "Cannot detect Bedolaga cabinet dir. Set BEDOLAGA_CABINET_DIR or restore archive with backup-info.txt" >&2; exit 1; }
  [[ -d "$BEDOLAGA_CABINET_DIR" ]] && bedolaga_cabinet_dir_existed=1
  ensure_dir "$BEDOLAGA_CABINET_DIR"
fi

if component_selected db && ! container_exists remnawave-db; then
  echo "Container remnawave-db not found, cannot restore PostgreSQL dump" >&2
  exit 1
fi
if component_selected redis && ! container_exists remnawave-redis; then
  echo "Container remnawave-redis not found, cannot restore Redis dump" >&2
  exit 1
fi
if component_selected bedolaga-db && ! container_exists remnawave_bot_db; then
  echo "Container remnawave_bot_db not found, cannot restore Bedolaga PostgreSQL dump" >&2
  exit 1
fi
if component_selected bedolaga-redis && ! container_exists remnawave_bot_redis; then
  echo "Container remnawave_bot_redis not found, cannot restore Bedolaga Redis dump" >&2
  exit 1
fi

if (( DRY_RUN == 0 )); then
  mkdir -p "$PRE_RESTORE_BACKUP_ROOT"
fi

PRESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PRE_ARCHIVE_PANEL="${PRE_RESTORE_BACKUP_ROOT}/pre-restore-panel-${PRESTAMP}.tar.gz"
PRE_ARCHIVE_BEDOLAGA_BOT="${PRE_RESTORE_BACKUP_ROOT}/pre-restore-bedolaga-bot-${PRESTAMP}.tar.gz"
PRE_ARCHIVE_BEDOLAGA_CABINET="${PRE_RESTORE_BACKUP_ROOT}/pre-restore-bedolaga-cabinet-${PRESTAMP}.tar.gz"

if (( need_remnawave_dir == 1 && remnawave_dir_existed == 1 )); then
  log "Create pre-restore snapshot: $PRE_ARCHIVE_PANEL"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] tar -czf \"$PRE_ARCHIVE_PANEL\" -C \"$REMNAWAVE_DIR\" .env docker-compose.yml caddy subscription"
  else
    if ! tar -czf "$PRE_ARCHIVE_PANEL" -C "$REMNAWAVE_DIR" .env docker-compose.yml caddy subscription 2>/dev/null; then
      log "WARNING: panel pre-restore snapshot failed, restore will continue"
    fi
  fi
fi

if (( need_bedolaga_bot_dir == 1 && bedolaga_bot_dir_existed == 1 )); then
  log "Create pre-restore snapshot: $PRE_ARCHIVE_BEDOLAGA_BOT"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] tar -czf \"$PRE_ARCHIVE_BEDOLAGA_BOT\" -C \"$BEDOLAGA_BOT_DIR\" .env docker-compose.yml docker-compose.override.yml data logs locales vpn_logo.png"
  else
    if ! tar -czf "$PRE_ARCHIVE_BEDOLAGA_BOT" -C "$BEDOLAGA_BOT_DIR" .env docker-compose.yml docker-compose.override.yml data logs locales vpn_logo.png 2>/dev/null; then
      log "WARNING: bedolaga bot pre-restore snapshot failed, restore will continue"
    fi
  fi
fi

if (( need_bedolaga_cabinet_dir == 1 && bedolaga_cabinet_dir_existed == 1 )); then
  log "Create pre-restore snapshot: $PRE_ARCHIVE_BEDOLAGA_CABINET"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] tar -czf \"$PRE_ARCHIVE_BEDOLAGA_CABINET\" -C \"$BEDOLAGA_CABINET_DIR\" .env docker-compose.yml docker-compose.override.yml"
  else
    if ! tar -czf "$PRE_ARCHIVE_BEDOLAGA_CABINET" -C "$BEDOLAGA_CABINET_DIR" .env docker-compose.yml docker-compose.override.yml 2>/dev/null; then
      log "WARNING: bedolaga cabinet pre-restore snapshot failed, restore will continue"
    fi
  fi
fi

POSTGRES_USER=""
POSTGRES_DB=""
if (( need_remnawave == 1 )); then
  ENV_SOURCE="${SRC_REMNAWAVE}/.env"
  ENV_TARGET=""
  if [[ -n "${REMNAWAVE_DIR:-}" ]]; then
    ENV_TARGET="${REMNAWAVE_DIR}/.env"
  fi
  if [[ ! -f "$ENV_SOURCE" ]]; then
    ENV_SOURCE="$ENV_TARGET"
  fi
  POSTGRES_USER="$(grep -E '^POSTGRES_USER=' "$ENV_SOURCE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  POSTGRES_DB="$(grep -E '^POSTGRES_DB=' "$ENV_SOURCE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
fi
[[ -n "$POSTGRES_USER" ]] || POSTGRES_USER="$BACKUP_POSTGRES_USER"
[[ -n "$POSTGRES_DB" ]] || POSTGRES_DB="$BACKUP_POSTGRES_DB"

BEDOLAGA_POSTGRES_USER=""
BEDOLAGA_POSTGRES_DB=""
if (( need_bedolaga_bot == 1 )); then
  BEDOLAGA_ENV_SOURCE="${SRC_BEDOLAGA_BOT}/.env"
  BEDOLAGA_ENV_TARGET=""
  if [[ -n "${BEDOLAGA_BOT_DIR:-}" ]]; then
    BEDOLAGA_ENV_TARGET="${BEDOLAGA_BOT_DIR}/.env"
  fi
  if [[ ! -f "$BEDOLAGA_ENV_SOURCE" ]]; then
    BEDOLAGA_ENV_SOURCE="$BEDOLAGA_ENV_TARGET"
  fi
  BEDOLAGA_POSTGRES_USER="$(grep -E '^POSTGRES_USER=' "$BEDOLAGA_ENV_SOURCE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  BEDOLAGA_POSTGRES_DB="$(grep -E '^POSTGRES_DB=' "$BEDOLAGA_ENV_SOURCE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
fi
[[ -n "$BEDOLAGA_POSTGRES_USER" ]] || BEDOLAGA_POSTGRES_USER="$BACKUP_BEDOLAGA_POSTGRES_USER"
[[ -n "$BEDOLAGA_POSTGRES_DB" ]] || BEDOLAGA_POSTGRES_DB="$BACKUP_BEDOLAGA_POSTGRES_DB"

if component_selected env; then
  [[ -f "${SRC_REMNAWAVE}/.env" ]] || { echo "Missing remnawave/.env in archive" >&2; exit 1; }
  log "Restore env -> ${REMNAWAVE_DIR}/.env"
  run_cmd "cp -af \"${SRC_REMNAWAVE}/.env\" \"${REMNAWAVE_DIR}/.env\""
fi

if component_selected compose; then
  [[ -f "${SRC_REMNAWAVE}/docker-compose.yml" ]] || { echo "Missing remnawave/docker-compose.yml in archive" >&2; exit 1; }
  log "Restore compose -> ${REMNAWAVE_DIR}/docker-compose.yml"
  run_cmd "cp -af \"${SRC_REMNAWAVE}/docker-compose.yml\" \"${REMNAWAVE_DIR}/docker-compose.yml\""
fi

if component_selected caddy; then
  [[ -d "${SRC_REMNAWAVE}/caddy" ]] || { echo "Missing remnawave/caddy in archive" >&2; exit 1; }
  log "Restore caddy dir -> ${REMNAWAVE_DIR}/caddy"
  run_cmd "rm -rf \"${REMNAWAVE_DIR}/caddy\" && cp -a \"${SRC_REMNAWAVE}/caddy\" \"${REMNAWAVE_DIR}/caddy\""
fi

if component_selected subscription; then
  [[ -d "${SRC_REMNAWAVE}/subscription" ]] || { echo "Missing remnawave/subscription in archive" >&2; exit 1; }
  log "Restore subscription dir -> ${REMNAWAVE_DIR}/subscription"
  run_cmd "rm -rf \"${REMNAWAVE_DIR}/subscription\" && cp -a \"${SRC_REMNAWAVE}/subscription\" \"${REMNAWAVE_DIR}/subscription\""
fi

if component_selected db; then
  [[ -f "$DB_DUMP" ]] || { echo "Missing remnawave-db.dump in archive" >&2; exit 1; }
  [[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]] || { echo "Cannot detect POSTGRES_USER/POSTGRES_DB" >&2; exit 1; }
  log "Restore PostgreSQL -> db=${POSTGRES_DB}, user=${POSTGRES_USER}"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] docker exec -i remnawave-db pg_restore -U $POSTGRES_USER -d $POSTGRES_DB --clean --if-exists --no-owner --no-privileges < $DB_DUMP"
  else
    docker exec -i remnawave-db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges < "$DB_DUMP"
  fi
fi

if component_selected redis; then
  [[ -f "$REDIS_DUMP" ]] || { echo "Missing remnawave-redis.rdb in archive" >&2; exit 1; }
  log "Restore Redis dump"
  run_cmd "docker cp \"$REDIS_DUMP\" remnawave-redis:/data/dump.rdb"
fi

if component_selected bedolaga-bot; then
  [[ -d "$SRC_BEDOLAGA_BOT" ]] || { echo "Missing bedolaga/bot in archive" >&2; exit 1; }
  log "Restore Bedolaga bot files -> ${BEDOLAGA_BOT_DIR}"
  run_cmd "mkdir -p \"${BEDOLAGA_BOT_DIR}\""

  [[ -f "${SRC_BEDOLAGA_BOT}/.env" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_BOT}/.env\" \"${BEDOLAGA_BOT_DIR}/.env\""
  [[ -f "${SRC_BEDOLAGA_BOT}/docker-compose.yml" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_BOT}/docker-compose.yml\" \"${BEDOLAGA_BOT_DIR}/docker-compose.yml\""
  [[ -f "${SRC_BEDOLAGA_BOT}/docker-compose.override.yml" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_BOT}/docker-compose.override.yml\" \"${BEDOLAGA_BOT_DIR}/docker-compose.override.yml\""
  [[ -f "${SRC_BEDOLAGA_BOT}/vpn_logo.png" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_BOT}/vpn_logo.png\" \"${BEDOLAGA_BOT_DIR}/vpn_logo.png\""

  [[ -d "${SRC_BEDOLAGA_BOT}/data" ]] && run_cmd "mkdir -p \"${BEDOLAGA_BOT_DIR}/data\" && cp -a \"${SRC_BEDOLAGA_BOT}/data/.\" \"${BEDOLAGA_BOT_DIR}/data/\""
  [[ -d "${SRC_BEDOLAGA_BOT}/logs" ]] && run_cmd "rm -rf \"${BEDOLAGA_BOT_DIR}/logs\" && cp -a \"${SRC_BEDOLAGA_BOT}/logs\" \"${BEDOLAGA_BOT_DIR}/logs\""
  [[ -d "${SRC_BEDOLAGA_BOT}/locales" ]] && run_cmd "rm -rf \"${BEDOLAGA_BOT_DIR}/locales\" && cp -a \"${SRC_BEDOLAGA_BOT}/locales\" \"${BEDOLAGA_BOT_DIR}/locales\""
fi

if component_selected bedolaga-cabinet; then
  [[ -d "$SRC_BEDOLAGA_CABINET" ]] || { echo "Missing bedolaga/cabinet in archive" >&2; exit 1; }
  log "Restore Bedolaga cabinet files -> ${BEDOLAGA_CABINET_DIR}"
  run_cmd "mkdir -p \"${BEDOLAGA_CABINET_DIR}\""

  [[ -f "${SRC_BEDOLAGA_CABINET}/.env" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/.env\" \"${BEDOLAGA_CABINET_DIR}/.env\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/docker-compose.yml" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/docker-compose.yml\" \"${BEDOLAGA_CABINET_DIR}/docker-compose.yml\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/docker-compose.override.yml" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/docker-compose.override.yml\" \"${BEDOLAGA_CABINET_DIR}/docker-compose.override.yml\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/package.json" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/package.json\" \"${BEDOLAGA_CABINET_DIR}/package.json\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/package-lock.json" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/package-lock.json\" \"${BEDOLAGA_CABINET_DIR}/package-lock.json\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/yarn.lock" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/yarn.lock\" \"${BEDOLAGA_CABINET_DIR}/yarn.lock\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/pnpm-lock.yaml" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/pnpm-lock.yaml\" \"${BEDOLAGA_CABINET_DIR}/pnpm-lock.yaml\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/npm-shrinkwrap.json" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/npm-shrinkwrap.json\" \"${BEDOLAGA_CABINET_DIR}/npm-shrinkwrap.json\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/ecosystem.config.js" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/ecosystem.config.js\" \"${BEDOLAGA_CABINET_DIR}/ecosystem.config.js\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/ecosystem.config.cjs" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/ecosystem.config.cjs\" \"${BEDOLAGA_CABINET_DIR}/ecosystem.config.cjs\""
  [[ -f "${SRC_BEDOLAGA_CABINET}/nginx.conf" ]] && run_cmd "cp -af \"${SRC_BEDOLAGA_CABINET}/nginx.conf\" \"${BEDOLAGA_CABINET_DIR}/nginx.conf\""
  [[ -d "${SRC_BEDOLAGA_CABINET}/dist" ]] && run_cmd "rm -rf \"${BEDOLAGA_CABINET_DIR}/dist\" && cp -a \"${SRC_BEDOLAGA_CABINET}/dist\" \"${BEDOLAGA_CABINET_DIR}/dist\""
  [[ -d "${SRC_BEDOLAGA_CABINET}/public" ]] && run_cmd "rm -rf \"${BEDOLAGA_CABINET_DIR}/public\" && cp -a \"${SRC_BEDOLAGA_CABINET}/public\" \"${BEDOLAGA_CABINET_DIR}/public\""
fi

if component_selected bedolaga-db; then
  [[ -f "$BEDOLAGA_DB_DUMP" ]] || { echo "Missing bedolaga-bot-db.dump in archive" >&2; exit 1; }
  [[ -n "$BEDOLAGA_POSTGRES_USER" && -n "$BEDOLAGA_POSTGRES_DB" ]] || { echo "Cannot detect Bedolaga POSTGRES_USER/POSTGRES_DB" >&2; exit 1; }
  log "Restore Bedolaga PostgreSQL -> db=${BEDOLAGA_POSTGRES_DB}, user=${BEDOLAGA_POSTGRES_USER}"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] docker exec -i remnawave_bot_db pg_restore -U $BEDOLAGA_POSTGRES_USER -d $BEDOLAGA_POSTGRES_DB --clean --if-exists --no-owner --no-privileges < $BEDOLAGA_DB_DUMP"
  else
    docker exec -i remnawave_bot_db pg_restore -U "$BEDOLAGA_POSTGRES_USER" -d "$BEDOLAGA_POSTGRES_DB" --clean --if-exists --no-owner --no-privileges < "$BEDOLAGA_DB_DUMP"
  fi
fi

if component_selected bedolaga-redis; then
  [[ -f "$BEDOLAGA_REDIS_DUMP" ]] || { echo "Missing bedolaga-bot-redis.rdb in archive" >&2; exit 1; }
  log "Restore Bedolaga Redis dump"
  run_cmd "docker cp \"$BEDOLAGA_REDIS_DUMP\" remnawave_bot_redis:/data/dump.rdb"
fi

if (( NO_RESTART == 0 )); then
  if component_selected redis; then
    log "Restart remnawave-redis"
    run_cmd "docker restart remnawave-redis >/dev/null"
  fi

  if component_selected db || component_selected env || component_selected compose; then
    log "Apply compose and restart remnawave stack"
    run_cmd "cd \"$REMNAWAVE_DIR\" && docker compose up -d"
  fi

  if component_selected caddy; then
    log "Restart remnawave-caddy"
    run_cmd "docker restart remnawave-caddy >/dev/null"
  fi

  if component_selected subscription; then
    if docker ps -a --format '{{.Names}}' | grep -qx 'remnawave-subscription-page'; then
      log "Restart remnawave-subscription-page"
      run_cmd "docker restart remnawave-subscription-page >/dev/null"
    fi
  fi

  if component_selected bedolaga-redis; then
    log "Restart remnawave_bot_redis"
    run_cmd "docker restart remnawave_bot_redis >/dev/null"
  fi

  if component_selected bedolaga-db || component_selected bedolaga-bot; then
    log "Apply compose and restart Bedolaga bot stack"
    run_cmd "cd \"$BEDOLAGA_BOT_DIR\" && docker compose up -d"
  fi

  if component_selected bedolaga-cabinet; then
    if [[ -f "${BEDOLAGA_CABINET_DIR}/docker-compose.yml" || -f "${BEDOLAGA_CABINET_DIR}/docker-compose.caddy.yml" || -f "${BEDOLAGA_CABINET_DIR}/compose.yaml" || -f "${BEDOLAGA_CABINET_DIR}/compose.yml" ]]; then
      log "Apply compose and restart Bedolaga cabinet stack"
      run_cmd "cd \"$BEDOLAGA_CABINET_DIR\" && docker compose up -d"
    elif systemctl list-unit-files 2>/dev/null | grep -Eq '^(cabinet-frontend|bedolaga-cabinet)\.service'; then
      log "Restart Bedolaga cabinet systemd service"
      if systemctl list-unit-files 2>/dev/null | grep -Eq '^cabinet-frontend\.service'; then
        run_cmd "systemctl restart cabinet-frontend"
      else
        run_cmd "systemctl restart bedolaga-cabinet"
      fi
    elif command -v pm2 >/dev/null 2>&1; then
      log "Restart Bedolaga cabinet via PM2 (if configured)"
      run_cmd "pm2 restart cabinet-frontend >/dev/null 2>&1 || pm2 restart bedolaga-cabinet >/dev/null 2>&1 || true"
    else
      log "WARNING: Bedolaga cabinet restart skipped (no compose/systemd/pm2 target found)"
    fi
  fi
fi

log "Restore completed"
if (( DRY_RUN == 0 )); then
  if [[ -f "$PRE_ARCHIVE_PANEL" ]]; then
    echo "Pre-restore snapshot (panel): $PRE_ARCHIVE_PANEL"
  fi
  if [[ -f "$PRE_ARCHIVE_BEDOLAGA_BOT" ]]; then
    echo "Pre-restore snapshot (bedolaga bot): $PRE_ARCHIVE_BEDOLAGA_BOT"
  fi
  if [[ -f "$PRE_ARCHIVE_BEDOLAGA_CABINET" ]]; then
    echo "Pre-restore snapshot (bedolaga cabinet): $PRE_ARCHIVE_BEDOLAGA_CABINET"
  fi
fi
