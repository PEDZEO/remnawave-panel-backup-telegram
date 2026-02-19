#!/usr/bin/env bash
set -euo pipefail

REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
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
  all           restore everything (db + redis + env + compose + caddy + subscription)
  db            restore PostgreSQL dump
  redis         restore Redis dump.rdb
  configs       restore all config files (env + compose + caddy + subscription)
  env           restore /opt/remnawave/.env
  compose       restore /opt/remnawave/docker-compose.yml
  caddy         restore /opt/remnawave/caddy/
  subscription  restore /opt/remnawave/subscription/

Examples:
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz.gpg --only db --only redis
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz --only configs --dry-run
USAGE
}

log() {
  echo "$*"
  logger -t panel-restore "$*"
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

run_cmd() {
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] $*"
  else
    eval "$*"
  fi
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
    db|redis|env|compose|caddy|subscription)
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
REMNAWAVE_DIR="${REMNAWAVE_DIR:-$(detect_remnawave_dir || true)}"
[[ -d "$REMNAWAVE_DIR" ]] || { echo "Directory not found: $REMNAWAVE_DIR" >&2; exit 1; }

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
  else
    gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSWORD" \
      --decrypt "$ARCHIVE_PATH" > "$ARCHIVE_TO_EXTRACT"
  fi
fi

log "Extract archive: $ARCHIVE_TO_EXTRACT"
run_cmd "tar -xzf \"$ARCHIVE_TO_EXTRACT\" -C \"$EXTRACT_DIR\""

DB_DUMP="$EXTRACT_DIR/remnawave-db.dump"
REDIS_DUMP="$EXTRACT_DIR/remnawave-redis.rdb"
SRC_REMNAWAVE="$EXTRACT_DIR/remnawave"

if (( DRY_RUN == 0 )); then
  mkdir -p "$PRE_RESTORE_BACKUP_ROOT"
fi

PRESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PRE_ARCHIVE="${PRE_RESTORE_BACKUP_ROOT}/pre-restore-${PRESTAMP}.tar.gz"

if [[ -n "${WANT[env]:-}" || -n "${WANT[compose]:-}" || -n "${WANT[caddy]:-}" || -n "${WANT[subscription]:-}" ]]; then
  log "Create pre-restore snapshot: $PRE_ARCHIVE"
  run_cmd "tar -czf \"$PRE_ARCHIVE\" -C \"$REMNAWAVE_DIR\" .env docker-compose.yml caddy subscription 2>/dev/null || true"
fi

ENV_SOURCE="${SRC_REMNAWAVE}/.env"
ENV_TARGET="${REMNAWAVE_DIR}/.env"
if [[ ! -f "$ENV_SOURCE" ]]; then
  ENV_SOURCE="$ENV_TARGET"
fi

POSTGRES_USER="$(grep -E '^POSTGRES_USER=' "$ENV_SOURCE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
POSTGRES_DB="$(grep -E '^POSTGRES_DB=' "$ENV_SOURCE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"

if [[ -n "${WANT[env]:-}" ]]; then
  [[ -f "${SRC_REMNAWAVE}/.env" ]] || { echo "Missing remnawave/.env in archive" >&2; exit 1; }
  log "Restore env -> ${REMNAWAVE_DIR}/.env"
  run_cmd "cp -af \"${SRC_REMNAWAVE}/.env\" \"${REMNAWAVE_DIR}/.env\""
fi

if [[ -n "${WANT[compose]:-}" ]]; then
  [[ -f "${SRC_REMNAWAVE}/docker-compose.yml" ]] || { echo "Missing remnawave/docker-compose.yml in archive" >&2; exit 1; }
  log "Restore compose -> ${REMNAWAVE_DIR}/docker-compose.yml"
  run_cmd "cp -af \"${SRC_REMNAWAVE}/docker-compose.yml\" \"${REMNAWAVE_DIR}/docker-compose.yml\""
fi

if [[ -n "${WANT[caddy]:-}" ]]; then
  [[ -d "${SRC_REMNAWAVE}/caddy" ]] || { echo "Missing remnawave/caddy in archive" >&2; exit 1; }
  log "Restore caddy dir -> ${REMNAWAVE_DIR}/caddy"
  run_cmd "rm -rf \"${REMNAWAVE_DIR}/caddy\" && cp -a \"${SRC_REMNAWAVE}/caddy\" \"${REMNAWAVE_DIR}/caddy\""
fi

if [[ -n "${WANT[subscription]:-}" ]]; then
  [[ -d "${SRC_REMNAWAVE}/subscription" ]] || { echo "Missing remnawave/subscription in archive" >&2; exit 1; }
  log "Restore subscription dir -> ${REMNAWAVE_DIR}/subscription"
  run_cmd "rm -rf \"${REMNAWAVE_DIR}/subscription\" && cp -a \"${SRC_REMNAWAVE}/subscription\" \"${REMNAWAVE_DIR}/subscription\""
fi

if [[ -n "${WANT[db]:-}" ]]; then
  [[ -f "$DB_DUMP" ]] || { echo "Missing remnawave-db.dump in archive" >&2; exit 1; }
  [[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]] || { echo "Cannot detect POSTGRES_USER/POSTGRES_DB" >&2; exit 1; }
  log "Restore PostgreSQL -> db=${POSTGRES_DB}, user=${POSTGRES_USER}"
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] docker exec -i remnawave-db pg_restore -U $POSTGRES_USER -d $POSTGRES_DB --clean --if-exists --no-owner --no-privileges < $DB_DUMP"
  else
    docker exec -i remnawave-db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges < "$DB_DUMP"
  fi
fi

if [[ -n "${WANT[redis]:-}" ]]; then
  [[ -f "$REDIS_DUMP" ]] || { echo "Missing remnawave-redis.rdb in archive" >&2; exit 1; }
  log "Restore Redis dump"
  run_cmd "docker cp \"$REDIS_DUMP\" remnawave-redis:/data/dump.rdb"
fi

if (( NO_RESTART == 0 )); then
  if [[ -n "${WANT[redis]:-}" ]]; then
    log "Restart remnawave-redis"
    run_cmd "docker restart remnawave-redis >/dev/null"
  fi

  if [[ -n "${WANT[db]:-}" || -n "${WANT[env]:-}" || -n "${WANT[compose]:-}" ]]; then
    log "Apply compose and restart remnawave stack"
    run_cmd "cd \"$REMNAWAVE_DIR\" && docker compose up -d"
  fi

  if [[ -n "${WANT[caddy]:-}" ]]; then
    log "Restart remnawave-caddy"
    run_cmd "docker restart remnawave-caddy >/dev/null"
  fi

  if [[ -n "${WANT[subscription]:-}" ]]; then
    if docker ps -a --format '{{.Names}}' | grep -qx 'remnawave-subscription-page'; then
      log "Restart remnawave-subscription-page"
      run_cmd "docker restart remnawave-subscription-page >/dev/null"
    fi
  fi
fi

log "Restore completed"
if (( DRY_RUN == 0 )); then
  echo "Pre-restore snapshot: $PRE_ARCHIVE"
fi
