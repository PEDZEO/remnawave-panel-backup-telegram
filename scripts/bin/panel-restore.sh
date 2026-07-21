#!/usr/bin/env bash
# update: runtime restore flow applies selected components from backup archive.
set -euo pipefail

REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-}"
BEDOLAGA_CABINET_DIR="${BEDOLAGA_CABINET_DIR:-}"
BEDOLAGA_STACK_PROFILE="${BEDOLAGA_STACK_PROFILE:-auto}"
BEDOLAGA_DB_CONTAINER="${BEDOLAGA_DB_CONTAINER:-}"
BEDOLAGA_REDIS_CONTAINER="${BEDOLAGA_REDIS_CONTAINER:-}"
PRE_RESTORE_BACKUP_ROOT="${PRE_RESTORE_BACKUP_ROOT:-/var/backups/panel-restore-pre}"
RESTORE_ALLOW_NO_SNAPSHOT="${RESTORE_ALLOW_NO_SNAPSHOT:-0}"
RESTORE_ALLOW_BEDOLAGA_PROFILE_MISMATCH="${RESTORE_ALLOW_BEDOLAGA_PROFILE_MISMATCH:-0}"
BACKUP_ENV_PATH="${BACKUP_ENV_PATH:-/etc/panel-backup.env}"
PBM_DEEP_AUTODETECT="${PBM_DEEP_AUTODETECT:-0}"
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"
NO_RESTART=0
ARCHIVE_PATH=""
declare -a ONLY_RAW=()
declare -A WANT=()
BEDOLAGA_REQUIRED_PROFILE=""

usage() {
  cat <<USAGE
Usage:
  panel-restore.sh --from /path/to/panel-backup-*.tar.gz|*.tar.gz.gpg [--only COMPONENT] [--no-restart]

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
  bedolaga-fork-db  restore Bedolaga fork PostgreSQL dump only when archive/target are fork
  bedolaga-official-db restore official Bedolaga PostgreSQL dump only when archive/target are official
  bedolaga-redis    restore Bedolaga bot Redis dump.rdb
  bedolaga-bot      restore /root/remnawave-bedolaga-telegram-bot config/data
  bedolaga-cabinet  restore /root/bedolaga-cabinet config
  bedolaga-configs  restore Bedolaga configs (bot + cabinet)

Examples:
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/panel-backup-host-20260219T120000Z.tar.gz.gpg --only db --only redis
  sudo /usr/local/bin/panel-restore.sh --from /var/backups/panel/pb-0221-120000.tar.gz --only all,bedolaga
USAGE
}

log() {
  echo "$*"
  if command -v logger >/dev/null 2>&1; then
    logger -t panel-restore "$*" || true
  fi
}

run_cmd() {
  "$@"
}

run_quiet_allow_fail() {
  "$@" >/dev/null 2>&1 || true
}

run_compose_up() {
  local dir="$1"
  (cd "$dir" && docker compose up -d)
}

replace_dir() {
  local source_dir="$1"
  local target_dir="$2"
  local target_parent=""
  local target_base=""
  local staged_dir=""
  local old_dir=""

  target_parent="$(dirname "$target_dir")"
  target_base="$(basename "$target_dir")"
  mkdir -p "$target_parent"

  staged_dir="$(mktemp -d "${target_parent}/.${target_base}.restore.XXXXXX")"
  if ! cp -a "${source_dir}/." "${staged_dir}/"; then
    rm -rf "$staged_dir"
    return 1
  fi

  if [[ -e "$target_dir" || -L "$target_dir" ]]; then
    old_dir="$(mktemp -d "${target_parent}/.${target_base}.old.XXXXXX")"
    rmdir "$old_dir"
    if ! mv "$target_dir" "$old_dir"; then
      rm -rf "$staged_dir"
      return 1
    fi
  fi

  if ! mv "$staged_dir" "$target_dir"; then
    if [[ -n "$old_dir" && -e "$old_dir" ]]; then
      mv "$old_dir" "$target_dir" >/dev/null 2>&1 || true
    fi
    rm -rf "$staged_dir"
    return 1
  fi

  [[ -n "$old_dir" ]] && rm -rf "$old_dir"
}

abort_pre_restore_snapshot_failure() {
  local label="$1"
  local archive_path="$2"

  if [[ "${RESTORE_ALLOW_NO_SNAPSHOT:-0}" == "1" ]]; then
    log "WARNING: ${label} pre-restore snapshot failed, continuing because RESTORE_ALLOW_NO_SNAPSHOT=1"
    return 0
  fi

  echo "ERROR: ${label} pre-restore snapshot failed: ${archive_path}" >&2
  echo "Restore was stopped before changing data. Set RESTORE_ALLOW_NO_SNAPSHOT=1 to bypass this guard." >&2
  exit 1
}

create_pre_restore_snapshot() {
  local archive_path="$1"
  local source_dir="$2"
  shift 2
  local entries=()
  local entry=""

  for entry in "$@"; do
    [[ -e "${source_dir}/${entry}" ]] && entries+=("$entry")
  done

  if [[ ${#entries[@]} -eq 0 ]]; then
    log "WARNING: pre-restore snapshot skipped, no files found in ${source_dir}"
    return 0
  fi

  tar -czf "$archive_path" -C "$source_dir" "${entries[@]}"
}

simple_env_value() {
  local env_file="$1"
  local key="$2"
  local value=""

  [[ -f "$env_file" ]] || return 0
  value="$(grep -E "^${key}=" "$env_file" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  value="${value%$'\r'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s' "$value"
}

redis_url_password() {
  local url="$1"
  local auth=""

  [[ "$url" == *"://"* && "$url" == *"@"* ]] || return 0
  auth="${url#*://}"
  auth="${auth%%@*}"
  [[ "$auth" == *":"* ]] || return 0
  printf '%s' "${auth#*:}"
}

redis_container_cli() {
  local container_name="$1"

  docker exec "$container_name" sh -lc '
    if command -v valkey-cli >/dev/null 2>&1; then
      command -v valkey-cli
    elif command -v redis-cli >/dev/null 2>&1; then
      command -v redis-cli
    fi
  ' 2>/dev/null | head -n1 | tr -d '\r' || true
}

redis_container_socket() {
  local container_name="$1"

  docker exec "$container_name" sh -lc '
    for socket_path in \
      /var/run/valkey/valkey.sock \
      /run/valkey/valkey.sock \
      /var/run/redis/redis.sock \
      /run/redis/redis.sock \
      /tmp/valkey.sock \
      /tmp/redis.sock; do
      if [ -S "$socket_path" ]; then
        printf "%s\n" "$socket_path"
        exit 0
      fi
    done
    find /var/run /run /tmp -maxdepth 3 -type s \( -name "*valkey*.sock" -o -name "*redis*.sock" \) 2>/dev/null | head -n1
  ' 2>/dev/null | head -n1 | tr -d '\r' || true
}

redis_container_password() {
  local container_name="$1"
  local env_file="$2"
  local value=""
  local url=""

  value="$(docker inspect "$container_name" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | awk -F= '$1=="REDIS_PASSWORD" || $1=="VALKEY_PASSWORD" {print substr($0,index($0,"=")+1); exit}' || true)"
  if [[ -z "$value" ]]; then
    url="$(docker inspect "$container_name" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
      | awk -F= '$1=="REDIS_URL" || $1=="REDIS_URI" || $1=="VALKEY_URL" {print substr($0,index($0,"=")+1); exit}' || true)"
    value="$(redis_url_password "$url")"
  fi
  if [[ -z "$value" && -n "$env_file" ]]; then
    value="$(simple_env_value "$env_file" "REDIS_PASSWORD")"
  fi
  if [[ -z "$value" && -n "$env_file" ]]; then
    value="$(simple_env_value "$env_file" "VALKEY_PASSWORD")"
  fi
  if [[ -z "$value" && -n "$env_file" ]]; then
    url="$(simple_env_value "$env_file" "REDIS_URL")"
    [[ -n "$url" ]] || url="$(simple_env_value "$env_file" "REDIS_URI")"
    [[ -n "$url" ]] || url="$(simple_env_value "$env_file" "VALKEY_URL")"
    value="$(redis_url_password "$url")"
  fi
  printf '%s' "$value"
}

redis_exec_cli() {
  local container_name="$1"
  local cli="$2"
  local password="$3"
  shift 3
  local exec_args=()
  local socket_path=""

  if [[ -n "$password" ]]; then
    exec_args=(-e "REDISCLI_AUTH=${password}" -e "VALKEYCLI_AUTH=${password}")
  fi
  socket_path="$(redis_container_socket "$container_name")"
  if [[ -n "$socket_path" ]]; then
    docker exec "${exec_args[@]}" "$container_name" "$cli" -s "$socket_path" "$@"
  else
    docker exec "${exec_args[@]}" "$container_name" "$cli" "$@"
  fi
}

redis_config_value() {
  local container_name="$1"
  local cli="$2"
  local password="$3"
  local key="$4"
  local value=""

  value="$(redis_exec_cli "$container_name" "$cli" "$password" --raw CONFIG GET "$key" 2>/dev/null | tail -n1 | tr -d '\r' || true)"
  printf '%s' "$value"
}

redis_dump_target_path() {
  local container_name="$1"
  local env_file="${2:-}"
  local cli=""
  local password=""
  local redis_dir=""
  local redis_dbfilename=""

  cli="$(redis_container_cli "$container_name")"
  password="$(redis_container_password "$container_name" "$env_file")"
  if [[ -n "$cli" ]]; then
    redis_dir="$(redis_config_value "$container_name" "$cli" "$password" "dir")"
    redis_dbfilename="$(redis_config_value "$container_name" "$cli" "$password" "dbfilename")"
  fi

  [[ -n "$redis_dir" ]] || redis_dir="/data"
  [[ -n "$redis_dbfilename" ]] || redis_dbfilename="dump.rdb"
  printf '%s/%s' "${redis_dir%/}" "$redis_dbfilename"
}

restore_redis_dump() {
  local dump_path="$1"
  local container_name="$2"
  local label="$3"
  local env_file="${4:-}"
  local target_path=""
  local fallback_path="/data/dump.rdb"

  log "Stop ${label}"
  target_path="$(redis_dump_target_path "$container_name" "$env_file")"
  docker stop "$container_name" >/dev/null 2>&1 || true
  if ! docker cp "$dump_path" "${container_name}:${target_path}"; then
    if [[ "$target_path" != "$fallback_path" ]]; then
      docker cp "$dump_path" "${container_name}:${fallback_path}" || {
        docker start "$container_name" >/dev/null 2>&1 || true
        echo "ERROR: failed to copy Redis dump into ${label}: ${target_path}, ${fallback_path}" >&2
        exit 1
      }
    else
      docker start "$container_name" >/dev/null 2>&1 || true
      echo "ERROR: failed to copy Redis dump into ${label}: ${target_path}" >&2
      exit 1
    fi
  fi
  docker start "$container_name" >/dev/null
}

validate_restore_target_dir() {
  local path="$1"
  local label="$2"
  local trimmed=""

  [[ -n "$path" ]] || return 0
  case "$path" in
    *[[:space:]]*|*"'"*|*'"'*|*'`'*|*'$'*|*\\*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*)
      echo "Unsafe ${label}: path contains whitespace or shell characters: $path" >&2
      exit 1
      ;;
    *'/../'*|*'/..'|*'/./'*|*'/.')
      echo "Unsafe ${label}: path contains . or .. segments: $path" >&2
      exit 1
      ;;
  esac
  if [[ "$path" != /* ]]; then
    echo "Unsafe ${label}: path must be absolute: $path" >&2
    exit 1
  fi
  trimmed="${path%/}"
  [[ -n "$trimmed" ]] || trimmed="/"
  case "$trimmed" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      echo "Unsafe ${label}: refusing to use system directory as restore target: $path" >&2
      exit 1
      ;;
  esac
  case "$path" in
    *$'\n'*|*$'\r'*)
      echo "Unsafe ${label}: path contains a newline" >&2
      exit 1
      ;;
  esac
}

normalize_restore_target_dir() {
  local path="$1"
  path="${path%/}"
  [[ -n "$path" ]] || path="/"
  printf '%s' "$path"
}

validate_restore_target_pair_distinct() {
  local label_a="$1"
  local path_a="$2"
  local label_b="$3"
  local path_b="$4"
  local norm_a=""
  local norm_b=""

  [[ -n "$path_a" && -n "$path_b" ]] || return 0
  norm_a="$(normalize_restore_target_dir "$path_a")"
  norm_b="$(normalize_restore_target_dir "$path_b")"

  if [[ "$norm_a" == "$norm_b" || "$norm_a" == "$norm_b/"* || "$norm_b" == "$norm_a/"* ]]; then
    echo "Unsafe restore targets: ${label_a} (${norm_a}) and ${label_b} (${norm_b}) overlap" >&2
    exit 1
  fi
}

validate_restore_target_collisions() {
  if (( need_remnawave_dir == 1 && need_bedolaga_bot_dir == 1 )); then
    validate_restore_target_pair_distinct "REMNAWAVE_DIR" "$REMNAWAVE_DIR" "BEDOLAGA_BOT_DIR" "$BEDOLAGA_BOT_DIR"
  fi
  if (( need_remnawave_dir == 1 && need_bedolaga_cabinet_dir == 1 )); then
    validate_restore_target_pair_distinct "REMNAWAVE_DIR" "$REMNAWAVE_DIR" "BEDOLAGA_CABINET_DIR" "$BEDOLAGA_CABINET_DIR"
  fi
  if (( need_bedolaga_bot_dir == 1 && need_bedolaga_cabinet_dir == 1 )); then
    validate_restore_target_pair_distinct "BEDOLAGA_BOT_DIR" "$BEDOLAGA_BOT_DIR" "BEDOLAGA_CABINET_DIR" "$BEDOLAGA_CABINET_DIR"
  fi
}

validate_archive_members() {
  local archive_path="$1"
  local member=""
  local listing_path="$TMP_DIR/archive-members.txt"

  if ! tar -tzf "$archive_path" > "$listing_path"; then
    echo "Cannot list archive members: ${archive_path}" >&2
    exit 1
  fi

  while IFS= read -r member; do
    case "$member" in
      ""|/*|../*|*/../*|*/..|..)
        echo "Unsafe archive member path: ${member}" >&2
        exit 1
        ;;
    esac
  done < "$listing_path"
}

verify_archive_checksum_if_present() {
  local archive_path="$1"
  local checksum_path="${archive_path}.sha256"
  local archive_dir=""
  local checksum_name=""

  [[ -f "$checksum_path" ]] || return 0
  command -v sha256sum >/dev/null 2>&1 || {
    echo "Checksum file exists, but sha256sum command is missing: ${checksum_path}" >&2
    exit 1
  }

  archive_dir="$(dirname "$archive_path")"
  checksum_name="$(basename "$checksum_path")"
  log "Verify checksum: ${checksum_path}"
  if ! (cd "$archive_dir" && sha256sum -c "$checksum_name"); then
    echo "Checksum verification failed: ${checksum_path}" >&2
    exit 1
  fi
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
  local compose_file=""

  is_bedolaga_bot_dir() {
    local d="$1"
    [[ -f "$d/docker-compose.yml" ]] || return 1
    return 0
  }

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
    if is_bedolaga_bot_dir "$guessed"; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(detect_compose_workdir_by_container_names remnawave_bot remnawave-bot remnawave_bot_db remnawave_bot_redis || true)"
  if [[ -n "$guessed" ]] && is_bedolaga_bot_dir "$guessed"; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 6 -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do is_bedolaga_bot_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 7 -type f -name 'docker-compose.yml' 2>/dev/null | while read -r compose_file; do d="$(dirname "$compose_file")"; grep -Eq 'container_name:[[:space:]]*(remnawave_bot|remnawave-bot|remnawave_bot_db|remnawave_bot_redis)([[:space:]]|$)' "$compose_file" || continue; is_bedolaga_bot_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  if [[ "${PBM_DEEP_AUTODETECT:-0}" == "1" ]]; then
    guessed="$(find / -xdev -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do is_bedolaga_bot_dir "$d" || continue; echo "$d"; break; done)"
    [[ -n "$guessed" ]] && echo "$guessed"
  fi
}

detect_bedolaga_cabinet_dir() {
  is_bedolaga_cabinet_dir() {
    local d="$1"
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
  for guessed in "${BEDOLAGA_CABINET_DIR}" "/root/bedolaga-cabinet" "/root/cabinet-frontend" "/opt/bedolaga-cabinet" "/opt/bedolaga-cabine" "/opt/cabinet-frontend"; do
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

  guessed="$(find /home /opt /srv /root -maxdepth 7 -type f -name 'docker-compose.yml' 2>/dev/null | while read -r compose_file; do d="$(dirname "$compose_file")"; grep -Eq 'container_name:[[:space:]]*(cabinet_frontend|cabinet-frontend|bedolaga-cabinet)([[:space:]]|$)' "$compose_file" || continue; is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home /opt /srv /root -maxdepth 6 -type d \( -name 'cabinet-frontend' -o -name 'bedolaga-cabinet' -o -name 'bedolaga-cabine' \) 2>/dev/null | while read -r d; do is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  if [[ "${PBM_DEEP_AUTODETECT:-0}" == "1" ]]; then
    guessed="$(find / -xdev -type d \( -name 'cabinet-frontend' -o -name 'bedolaga-cabinet' -o -name 'bedolaga-cabine' \) 2>/dev/null | while read -r d; do is_bedolaga_cabinet_dir "$d" || continue; echo "$d"; break; done)"
    [[ -n "$guessed" ]] && echo "$guessed"
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
  mkdir -p "$path"
}

container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' | grep -qx "$name"
}

normalize_bedolaga_stack_profile() {
  local value="${1:-auto}"
  value="${value,,}"
  case "$value" in
    pedzeo|fork|fork-pedzeo|pedzeo-fork) printf '%s' "fork" ;;
    official|main|upstream|bedolaga-dev) printf '%s' "official" ;;
    custom) printf '%s' "custom" ;;
    unknown|"") printf '%s' "unknown" ;;
    auto) printf '%s' "auto" ;;
    *) printf '%s' "$value" ;;
  esac
}

bedolaga_repo_origin_url() {
  local repo_dir="$1"
  [[ -n "$repo_dir" && -d "${repo_dir}/.git" ]] || return 0
  git -C "$repo_dir" remote get-url origin 2>/dev/null || true
}

detect_bedolaga_stack_profile() {
  local bot_dir="$1"
  local configured=""
  local origin=""
  local normalized_origin=""

  configured="$(normalize_bedolaga_stack_profile "${BEDOLAGA_STACK_PROFILE:-auto}")"
  if [[ "$configured" != "auto" ]]; then
    printf '%s' "$configured"
    return 0
  fi

  origin="$(bedolaga_repo_origin_url "$bot_dir")"
  normalized_origin="${origin,,}"
  case "$normalized_origin" in
    *github.com/pedzeo/remnawave-bedolaga-telegram-bot*|*github.com:pedzeo/remnawave-bedolaga-telegram-bot*)
      printf '%s' "fork"
      return 0
      ;;
    *github.com/bedolaga-dev/remnawave-bedolaga-telegram-bot*|*github.com:bedolaga-dev/remnawave-bedolaga-telegram-bot*)
      printf '%s' "official"
      return 0
      ;;
  esac

  if [[ -n "$origin" ]]; then
    printf '%s' "custom"
  else
    printf '%s' "unknown"
  fi
}

compose_container_name_for_service() {
  local compose_file="$1"
  local service_name="$2"

  [[ -f "$compose_file" ]] || return 0
  awk -v svc="$service_name" '
    $0 ~ "^[[:space:]]{2}" svc ":[[:space:]]*$" { in_service=1; next }
    in_service && $0 ~ "^[[:space:]]{2}[A-Za-z0-9_.-]+:[[:space:]]*$" { in_service=0 }
    in_service && $0 ~ "^[[:space:]]*container_name:[[:space:]]*" {
      sub(/^[[:space:]]*container_name:[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      print
      exit
    }
  ' "$compose_file" 2>/dev/null || true
}

detect_bedolaga_db_container() {
  local bot_dir="$1"
  local fallback="${2:-remnawave_bot_db}"
  local detected=""

  if [[ -n "${BEDOLAGA_DB_CONTAINER:-}" ]]; then
    printf '%s' "$BEDOLAGA_DB_CONTAINER"
    return 0
  fi
  detected="$(compose_container_name_for_service "${bot_dir}/docker-compose.yml" "postgres")"
  printf '%s' "${detected:-$fallback}"
}

detect_bedolaga_redis_container() {
  local bot_dir="$1"
  local fallback="${2:-remnawave_bot_redis}"
  local detected=""

  if [[ -n "${BEDOLAGA_REDIS_CONTAINER:-}" ]]; then
    printf '%s' "$BEDOLAGA_REDIS_CONTAINER"
    return 0
  fi
  detected="$(compose_container_name_for_service "${bot_dir}/docker-compose.yml" "redis")"
  printf '%s' "${detected:-$fallback}"
}

is_known_bedolaga_profile() {
  case "${1:-unknown}" in
    official|fork|custom) return 0 ;;
    *) return 1 ;;
  esac
}

guard_bedolaga_db_profile_restore() {
  local backup_profile="$1"
  local target_profile="$2"
  local required_profile="${BEDOLAGA_REQUIRED_PROFILE:-}"

  backup_profile="$(normalize_bedolaga_stack_profile "$backup_profile")"
  target_profile="$(normalize_bedolaga_stack_profile "$target_profile")"
  required_profile="$(normalize_bedolaga_stack_profile "$required_profile")"

  if [[ "$required_profile" != "auto" && "$required_profile" != "unknown" && -n "$required_profile" && "$backup_profile" != "$required_profile" ]]; then
    echo "Archive Bedolaga DB profile is ${backup_profile}, but selected restore component requires ${required_profile}." >&2
    exit 1
  fi

  if [[ "${RESTORE_ALLOW_BEDOLAGA_PROFILE_MISMATCH:-0}" == "1" ]]; then
    log "WARNING: Bedolaga DB profile guard bypassed by RESTORE_ALLOW_BEDOLAGA_PROFILE_MISMATCH=1"
    return 0
  fi

  if is_known_bedolaga_profile "$backup_profile" && is_known_bedolaga_profile "$target_profile" && [[ "$backup_profile" != "$target_profile" ]]; then
    echo "Refusing Bedolaga DB/Redis restore: archive profile is ${backup_profile}, target profile is ${target_profile}." >&2
    echo "Official and fork DB schemas can differ. Restore bot/cabinet files only, or set RESTORE_ALLOW_BEDOLAGA_PROFILE_MISMATCH=1 if you intentionally accept the risk." >&2
    exit 1
  fi
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
    bedolaga-official)
      WANT[bedolaga-db]=1
      WANT[bedolaga-redis]=1
      WANT[bedolaga-bot]=1
      WANT[bedolaga-cabinet]=1
      BEDOLAGA_REQUIRED_PROFILE="official"
      ;;
    bedolaga-fork)
      WANT[bedolaga-db]=1
      WANT[bedolaga-redis]=1
      WANT[bedolaga-bot]=1
      WANT[bedolaga-cabinet]=1
      BEDOLAGA_REQUIRED_PROFILE="fork"
      ;;
    bedolaga-configs)
      WANT[bedolaga-bot]=1
      WANT[bedolaga-cabinet]=1
      ;;
    bedolaga-official-db)
      WANT[bedolaga-db]=1
      BEDOLAGA_REQUIRED_PROFILE="official"
      ;;
    bedolaga-fork-db)
      WANT[bedolaga-db]=1
      BEDOLAGA_REQUIRED_PROFILE="fork"
      ;;
    bedolaga-official-redis)
      WANT[bedolaga-redis]=1
      BEDOLAGA_REQUIRED_PROFILE="official"
      ;;
    bedolaga-fork-redis)
      WANT[bedolaga-redis]=1
      BEDOLAGA_REQUIRED_PROFILE="fork"
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

verify_archive_checksum_if_present "$ARCHIVE_PATH"

ARCHIVE_TO_EXTRACT="$ARCHIVE_PATH"
if [[ "$ARCHIVE_PATH" == *.gpg ]]; then
  [[ -n "${BACKUP_PASSWORD:-}" ]] || { echo "BACKUP_PASSWORD is required for encrypted archive" >&2; exit 1; }
  command -v gpg >/dev/null 2>&1 || { echo "gpg command is required for encrypted archive" >&2; exit 1; }
  ARCHIVE_TO_EXTRACT="$TMP_DIR/decrypted.tar.gz"
  log "Decrypt archive: $ARCHIVE_PATH"
  gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSWORD" \
    --decrypt "$ARCHIVE_PATH" > "$ARCHIVE_TO_EXTRACT"
fi

log "Extract archive: $ARCHIVE_TO_EXTRACT"
validate_archive_members "$ARCHIVE_TO_EXTRACT"
tar -xzf "$ARCHIVE_TO_EXTRACT" -C "$EXTRACT_DIR"

DB_DUMP="$EXTRACT_DIR/remnawave-db.dump"
REDIS_DUMP="$EXTRACT_DIR/remnawave-redis.rdb"
REDIS_EMPTY_MARKER="$EXTRACT_DIR/remnawave-redis.rdb.empty"
SRC_REMNAWAVE="$EXTRACT_DIR/remnawave"
BEDOLAGA_DB_DUMP="$EXTRACT_DIR/bedolaga-bot-db.dump"
BEDOLAGA_REDIS_DUMP="$EXTRACT_DIR/bedolaga-bot-redis.rdb"
BEDOLAGA_REDIS_EMPTY_MARKER="$EXTRACT_DIR/bedolaga-bot-redis.rdb.empty"
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
BACKUP_BEDOLAGA_STACK_PROFILE="$(backup_info_value bedolaga_stack_profile "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_DB_DUMP_PROFILE="$(backup_info_value bedolaga_db_dump_profile "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_DB_CONTAINER="$(backup_info_value bedolaga_db_container "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_REDIS_CONTAINER="$(backup_info_value bedolaga_redis_container "$BACKUP_INFO_PATH")"
BACKUP_BEDOLAGA_STACK_PROFILE="$(normalize_bedolaga_stack_profile "${BACKUP_BEDOLAGA_STACK_PROFILE:-unknown}")"
BACKUP_BEDOLAGA_DB_DUMP_PROFILE="$(normalize_bedolaga_stack_profile "${BACKUP_BEDOLAGA_DB_DUMP_PROFILE:-$BACKUP_BEDOLAGA_STACK_PROFILE}")"

if [[ -f "$EXTRACT_DIR/bedolaga/db/${BACKUP_BEDOLAGA_DB_DUMP_PROFILE}/postgres.dump" ]]; then
  BEDOLAGA_DB_DUMP="$EXTRACT_DIR/bedolaga/db/${BACKUP_BEDOLAGA_DB_DUMP_PROFILE}/postgres.dump"
fi
if [[ -f "$EXTRACT_DIR/bedolaga/redis/${BACKUP_BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb" ]]; then
  BEDOLAGA_REDIS_DUMP="$EXTRACT_DIR/bedolaga/redis/${BACKUP_BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb"
fi
if [[ -f "$EXTRACT_DIR/bedolaga/redis/${BACKUP_BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb.empty" ]]; then
  BEDOLAGA_REDIS_EMPTY_MARKER="$EXTRACT_DIR/bedolaga/redis/${BACKUP_BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb.empty"
fi

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
  validate_restore_target_dir "$REMNAWAVE_DIR" "REMNAWAVE_DIR"
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
  validate_restore_target_dir "$BEDOLAGA_BOT_DIR" "BEDOLAGA_BOT_DIR"
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
  validate_restore_target_dir "$BEDOLAGA_CABINET_DIR" "BEDOLAGA_CABINET_DIR"
  [[ -d "$BEDOLAGA_CABINET_DIR" ]] && bedolaga_cabinet_dir_existed=1
  ensure_dir "$BEDOLAGA_CABINET_DIR"
fi

validate_restore_target_collisions

TARGET_BEDOLAGA_STACK_PROFILE="unknown"
if component_selected bedolaga-db || component_selected bedolaga-redis || component_selected bedolaga-bot || component_selected bedolaga-cabinet; then
  BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-$(detect_bedolaga_bot_dir || true)}"
  TARGET_BEDOLAGA_STACK_PROFILE="$(detect_bedolaga_stack_profile "${BEDOLAGA_BOT_DIR:-}")"
  if [[ "$TARGET_BEDOLAGA_STACK_PROFILE" == "unknown" && -n "$BACKUP_BEDOLAGA_STACK_PROFILE" && "$BACKUP_BEDOLAGA_STACK_PROFILE" != "unknown" ]] && component_selected bedolaga-bot; then
    TARGET_BEDOLAGA_STACK_PROFILE="$BACKUP_BEDOLAGA_STACK_PROFILE"
  fi
  BEDOLAGA_DB_CONTAINER="$(detect_bedolaga_db_container "${BEDOLAGA_BOT_DIR:-}" "${BACKUP_BEDOLAGA_DB_CONTAINER:-remnawave_bot_db}")"
  BEDOLAGA_REDIS_CONTAINER="$(detect_bedolaga_redis_container "${BEDOLAGA_BOT_DIR:-}" "${BACKUP_BEDOLAGA_REDIS_CONTAINER:-remnawave_bot_redis}")"
  log "Bedolaga archive profile: ${BACKUP_BEDOLAGA_STACK_PROFILE:-unknown}; target profile: ${TARGET_BEDOLAGA_STACK_PROFILE}; DB container: ${BEDOLAGA_DB_CONTAINER}; Redis container: ${BEDOLAGA_REDIS_CONTAINER}"
fi

if component_selected bedolaga-db || component_selected bedolaga-redis; then
  guard_bedolaga_db_profile_restore "${BACKUP_BEDOLAGA_STACK_PROFILE:-unknown}" "${TARGET_BEDOLAGA_STACK_PROFILE:-unknown}"
fi

if component_selected db && ! container_exists remnawave-db; then
  echo "Container remnawave-db not found, cannot restore PostgreSQL dump" >&2
  exit 1
fi
if component_selected redis && ! container_exists remnawave-redis; then
  echo "Container remnawave-redis not found, cannot restore Redis dump" >&2
  exit 1
fi
if component_selected bedolaga-db && ! container_exists "$BEDOLAGA_DB_CONTAINER"; then
  echo "Container ${BEDOLAGA_DB_CONTAINER} not found, cannot restore Bedolaga PostgreSQL dump" >&2
  exit 1
fi
if component_selected bedolaga-redis && ! container_exists "$BEDOLAGA_REDIS_CONTAINER"; then
  echo "Container ${BEDOLAGA_REDIS_CONTAINER} not found, cannot restore Bedolaga Redis dump" >&2
  exit 1
fi

mkdir -p "$PRE_RESTORE_BACKUP_ROOT"

PRESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PRE_ARCHIVE_PANEL="${PRE_RESTORE_BACKUP_ROOT}/pre-restore-panel-${PRESTAMP}.tar.gz"
PRE_ARCHIVE_BEDOLAGA_BOT="${PRE_RESTORE_BACKUP_ROOT}/pre-restore-bedolaga-bot-${PRESTAMP}.tar.gz"
PRE_ARCHIVE_BEDOLAGA_CABINET="${PRE_RESTORE_BACKUP_ROOT}/pre-restore-bedolaga-cabinet-${PRESTAMP}.tar.gz"

if (( need_remnawave_dir == 1 && remnawave_dir_existed == 1 )); then
  log "Create pre-restore snapshot: $PRE_ARCHIVE_PANEL"
  if ! create_pre_restore_snapshot "$PRE_ARCHIVE_PANEL" "$REMNAWAVE_DIR" .env docker-compose.yml caddy subscription; then
    abort_pre_restore_snapshot_failure "panel" "$PRE_ARCHIVE_PANEL"
  fi
fi

if (( need_bedolaga_bot_dir == 1 && bedolaga_bot_dir_existed == 1 )); then
  log "Create pre-restore snapshot: $PRE_ARCHIVE_BEDOLAGA_BOT"
  if ! create_pre_restore_snapshot "$PRE_ARCHIVE_BEDOLAGA_BOT" "$BEDOLAGA_BOT_DIR" .env docker-compose.yml docker-compose.override.yml data logs locales vpn_logo.png; then
    abort_pre_restore_snapshot_failure "bedolaga bot" "$PRE_ARCHIVE_BEDOLAGA_BOT"
  fi
fi

if (( need_bedolaga_cabinet_dir == 1 && bedolaga_cabinet_dir_existed == 1 )); then
  log "Create pre-restore snapshot: $PRE_ARCHIVE_BEDOLAGA_CABINET"
  if ! create_pre_restore_snapshot "$PRE_ARCHIVE_BEDOLAGA_CABINET" "$BEDOLAGA_CABINET_DIR" .env docker-compose.yml docker-compose.override.yml; then
    abort_pre_restore_snapshot_failure "bedolaga cabinet" "$PRE_ARCHIVE_BEDOLAGA_CABINET"
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
  run_cmd cp -af "${SRC_REMNAWAVE}/.env" "${REMNAWAVE_DIR}/.env"
fi

if component_selected compose; then
  [[ -f "${SRC_REMNAWAVE}/docker-compose.yml" ]] || { echo "Missing remnawave/docker-compose.yml in archive" >&2; exit 1; }
  log "Restore compose -> ${REMNAWAVE_DIR}/docker-compose.yml"
  run_cmd cp -af "${SRC_REMNAWAVE}/docker-compose.yml" "${REMNAWAVE_DIR}/docker-compose.yml"
fi

if component_selected caddy; then
  if [[ -d "${SRC_REMNAWAVE}/caddy" ]]; then
    log "Restore caddy dir -> ${REMNAWAVE_DIR}/caddy"
    replace_dir "${SRC_REMNAWAVE}/caddy" "${REMNAWAVE_DIR}/caddy"
  else
    log "WARNING: remnawave/caddy is missing in archive, skipping caddy restore"
  fi
fi

if component_selected subscription; then
  if [[ -d "${SRC_REMNAWAVE}/subscription" ]]; then
    log "Restore subscription dir -> ${REMNAWAVE_DIR}/subscription"
    replace_dir "${SRC_REMNAWAVE}/subscription" "${REMNAWAVE_DIR}/subscription"
  else
    log "WARNING: remnawave/subscription is missing in archive, skipping subscription restore"
  fi
fi

if component_selected db; then
  [[ -f "$DB_DUMP" ]] || { echo "Missing remnawave-db.dump in archive" >&2; exit 1; }
  [[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]] || { echo "Cannot detect POSTGRES_USER/POSTGRES_DB" >&2; exit 1; }
  log "Restore PostgreSQL -> db=${POSTGRES_DB}, user=${POSTGRES_USER}"
  docker exec -i remnawave-db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges < "$DB_DUMP"
fi

if component_selected redis; then
  if [[ -f "$REDIS_DUMP" ]]; then
    log "Restore Redis dump"
    restore_redis_dump "$REDIS_DUMP" remnawave-redis "remnawave-redis" "${REMNAWAVE_DIR}/.env"
  elif [[ -f "$REDIS_EMPTY_MARKER" ]]; then
    log "Redis archive marker says source Redis was empty, skipping Redis restore"
  else
    echo "Missing remnawave-redis.rdb in archive" >&2
    exit 1
  fi
fi

if component_selected bedolaga-bot; then
  [[ -d "$SRC_BEDOLAGA_BOT" ]] || { echo "Missing bedolaga/bot in archive" >&2; exit 1; }
  log "Restore Bedolaga bot files -> ${BEDOLAGA_BOT_DIR}"
  run_cmd mkdir -p "${BEDOLAGA_BOT_DIR}"

  [[ -f "${SRC_BEDOLAGA_BOT}/.env" ]] && run_cmd cp -af "${SRC_BEDOLAGA_BOT}/.env" "${BEDOLAGA_BOT_DIR}/.env"
  [[ -f "${SRC_BEDOLAGA_BOT}/docker-compose.yml" ]] && run_cmd cp -af "${SRC_BEDOLAGA_BOT}/docker-compose.yml" "${BEDOLAGA_BOT_DIR}/docker-compose.yml"
  [[ -f "${SRC_BEDOLAGA_BOT}/docker-compose.override.yml" ]] && run_cmd cp -af "${SRC_BEDOLAGA_BOT}/docker-compose.override.yml" "${BEDOLAGA_BOT_DIR}/docker-compose.override.yml"
  [[ -f "${SRC_BEDOLAGA_BOT}/vpn_logo.png" ]] && run_cmd cp -af "${SRC_BEDOLAGA_BOT}/vpn_logo.png" "${BEDOLAGA_BOT_DIR}/vpn_logo.png"

  if [[ -d "${SRC_BEDOLAGA_BOT}/data" ]]; then
    run_cmd mkdir -p "${BEDOLAGA_BOT_DIR}/data"
    run_cmd cp -a "${SRC_BEDOLAGA_BOT}/data/." "${BEDOLAGA_BOT_DIR}/data/"
  fi
  [[ -d "${SRC_BEDOLAGA_BOT}/logs" ]] && replace_dir "${SRC_BEDOLAGA_BOT}/logs" "${BEDOLAGA_BOT_DIR}/logs"
  [[ -d "${SRC_BEDOLAGA_BOT}/locales" ]] && replace_dir "${SRC_BEDOLAGA_BOT}/locales" "${BEDOLAGA_BOT_DIR}/locales"
  run_cmd mkdir -p "${BEDOLAGA_BOT_DIR}/logs" "${BEDOLAGA_BOT_DIR}/data" "${BEDOLAGA_BOT_DIR}/data/backups" "${BEDOLAGA_BOT_DIR}/data/referral_qr"
  run_cmd touch "${BEDOLAGA_BOT_DIR}/logs/bot.log"
  run_quiet_allow_fail chown -R 1000:1000 "${BEDOLAGA_BOT_DIR}/logs" "${BEDOLAGA_BOT_DIR}/data"
  run_quiet_allow_fail chmod -R 755 "${BEDOLAGA_BOT_DIR}/logs" "${BEDOLAGA_BOT_DIR}/data"
fi

if component_selected bedolaga-cabinet; then
  [[ -d "$SRC_BEDOLAGA_CABINET" ]] || { echo "Missing bedolaga/cabinet in archive" >&2; exit 1; }
  log "Restore Bedolaga cabinet files -> ${BEDOLAGA_CABINET_DIR}"
  run_cmd mkdir -p "${BEDOLAGA_CABINET_DIR}"

  [[ -f "${SRC_BEDOLAGA_CABINET}/.env" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/.env" "${BEDOLAGA_CABINET_DIR}/.env"
  [[ -f "${SRC_BEDOLAGA_CABINET}/docker-compose.yml" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/docker-compose.yml" "${BEDOLAGA_CABINET_DIR}/docker-compose.yml"
  [[ -f "${SRC_BEDOLAGA_CABINET}/docker-compose.override.yml" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/docker-compose.override.yml" "${BEDOLAGA_CABINET_DIR}/docker-compose.override.yml"
  [[ -f "${SRC_BEDOLAGA_CABINET}/package.json" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/package.json" "${BEDOLAGA_CABINET_DIR}/package.json"
  [[ -f "${SRC_BEDOLAGA_CABINET}/package-lock.json" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/package-lock.json" "${BEDOLAGA_CABINET_DIR}/package-lock.json"
  [[ -f "${SRC_BEDOLAGA_CABINET}/yarn.lock" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/yarn.lock" "${BEDOLAGA_CABINET_DIR}/yarn.lock"
  [[ -f "${SRC_BEDOLAGA_CABINET}/pnpm-lock.yaml" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/pnpm-lock.yaml" "${BEDOLAGA_CABINET_DIR}/pnpm-lock.yaml"
  [[ -f "${SRC_BEDOLAGA_CABINET}/npm-shrinkwrap.json" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/npm-shrinkwrap.json" "${BEDOLAGA_CABINET_DIR}/npm-shrinkwrap.json"
  [[ -f "${SRC_BEDOLAGA_CABINET}/ecosystem.config.js" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/ecosystem.config.js" "${BEDOLAGA_CABINET_DIR}/ecosystem.config.js"
  [[ -f "${SRC_BEDOLAGA_CABINET}/ecosystem.config.cjs" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/ecosystem.config.cjs" "${BEDOLAGA_CABINET_DIR}/ecosystem.config.cjs"
  [[ -f "${SRC_BEDOLAGA_CABINET}/nginx.conf" ]] && run_cmd cp -af "${SRC_BEDOLAGA_CABINET}/nginx.conf" "${BEDOLAGA_CABINET_DIR}/nginx.conf"
  [[ -d "${SRC_BEDOLAGA_CABINET}/dist" ]] && replace_dir "${SRC_BEDOLAGA_CABINET}/dist" "${BEDOLAGA_CABINET_DIR}/dist"
  [[ -d "${SRC_BEDOLAGA_CABINET}/public" ]] && replace_dir "${SRC_BEDOLAGA_CABINET}/public" "${BEDOLAGA_CABINET_DIR}/public"
fi

if component_selected bedolaga-db; then
  [[ -f "$BEDOLAGA_DB_DUMP" ]] || { echo "Missing bedolaga-bot-db.dump in archive" >&2; exit 1; }
  [[ -n "$BEDOLAGA_POSTGRES_USER" && -n "$BEDOLAGA_POSTGRES_DB" ]] || { echo "Cannot detect Bedolaga POSTGRES_USER/POSTGRES_DB" >&2; exit 1; }
  log "Restore Bedolaga PostgreSQL (${BACKUP_BEDOLAGA_DB_DUMP_PROFILE:-unknown}) -> container=${BEDOLAGA_DB_CONTAINER}, db=${BEDOLAGA_POSTGRES_DB}, user=${BEDOLAGA_POSTGRES_USER}"
  docker exec -i "$BEDOLAGA_DB_CONTAINER" pg_restore -U "$BEDOLAGA_POSTGRES_USER" -d "$BEDOLAGA_POSTGRES_DB" --clean --if-exists --no-owner --no-privileges < "$BEDOLAGA_DB_DUMP"
fi

if component_selected bedolaga-redis; then
  if [[ -f "$BEDOLAGA_REDIS_DUMP" ]]; then
    log "Restore Bedolaga Redis dump (${BACKUP_BEDOLAGA_DB_DUMP_PROFILE:-unknown}) -> container=${BEDOLAGA_REDIS_CONTAINER}"
    restore_redis_dump "$BEDOLAGA_REDIS_DUMP" "$BEDOLAGA_REDIS_CONTAINER" "$BEDOLAGA_REDIS_CONTAINER" "${BEDOLAGA_BOT_DIR}/.env"
  elif [[ -f "$BEDOLAGA_REDIS_EMPTY_MARKER" ]]; then
    log "Bedolaga Redis archive marker says source Redis was empty, skipping Redis restore"
  else
    echo "Missing bedolaga-bot-redis.rdb in archive" >&2
    exit 1
  fi
fi

if (( NO_RESTART == 0 )); then
  if component_selected db || component_selected env || component_selected compose; then
    log "Apply compose and restart remnawave stack"
    run_compose_up "$REMNAWAVE_DIR"
  fi

  if component_selected caddy; then
    log "Restart remnawave-caddy"
    docker restart remnawave-caddy >/dev/null
  fi

  if component_selected subscription; then
    if docker ps -a --format '{{.Names}}' | grep -qx 'remnawave-subscription-page'; then
      log "Restart remnawave-subscription-page"
      docker restart remnawave-subscription-page >/dev/null
    fi
  fi

  if component_selected bedolaga-db || component_selected bedolaga-bot; then
    log "Apply compose and restart Bedolaga bot stack"
    run_compose_up "$BEDOLAGA_BOT_DIR"
  fi

  if component_selected bedolaga-cabinet; then
    if [[ -f "${BEDOLAGA_CABINET_DIR}/docker-compose.yml" || -f "${BEDOLAGA_CABINET_DIR}/docker-compose.caddy.yml" || -f "${BEDOLAGA_CABINET_DIR}/compose.yaml" || -f "${BEDOLAGA_CABINET_DIR}/compose.yml" ]]; then
      log "Apply compose and restart Bedolaga cabinet stack"
      run_compose_up "$BEDOLAGA_CABINET_DIR"
    elif systemctl list-unit-files 2>/dev/null | grep -Eq '^(cabinet-frontend|bedolaga-cabinet)\.service'; then
      log "Restart Bedolaga cabinet systemd service"
      if systemctl list-unit-files 2>/dev/null | grep -Eq '^cabinet-frontend\.service'; then
        run_cmd systemctl restart cabinet-frontend
      else
        run_cmd systemctl restart bedolaga-cabinet
      fi
    elif command -v pm2 >/dev/null 2>&1; then
      log "Restart Bedolaga cabinet via PM2 (if configured)"
      pm2 restart cabinet-frontend >/dev/null 2>&1 || pm2 restart bedolaga-cabinet >/dev/null 2>&1 || true
    else
      log "WARNING: Bedolaga cabinet restart skipped (no compose/systemd/pm2 target found)"
    fi
  fi
fi

log "Restore completed"
if [[ -f "$PRE_ARCHIVE_PANEL" ]]; then
  echo "Pre-restore snapshot (panel): $PRE_ARCHIVE_PANEL"
fi
if [[ -f "$PRE_ARCHIVE_BEDOLAGA_BOT" ]]; then
  echo "Pre-restore snapshot (bedolaga bot): $PRE_ARCHIVE_BEDOLAGA_BOT"
fi
if [[ -f "$PRE_ARCHIVE_BEDOLAGA_CABINET" ]]; then
  echo "Pre-restore snapshot (bedolaga cabinet): $PRE_ARCHIVE_BEDOLAGA_CABINET"
fi
