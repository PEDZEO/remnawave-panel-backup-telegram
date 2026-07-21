#!/usr/bin/env bash
# update: runtime backup flow builds archive and sends to Telegram when configured.
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/panel}"
KEEP_DAYS="${KEEP_DAYS:-14}"
MAX_TG_PART_SIZE="${MAX_TG_PART_SIZE:-45M}"
TG_SINGLE_LIMIT_BYTES="${TG_SINGLE_LIMIT_BYTES:-50331648}"
REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-}"
BEDOLAGA_CABINET_DIR="${BEDOLAGA_CABINET_DIR:-}"
BEDOLAGA_STACK_PROFILE="${BEDOLAGA_STACK_PROFILE:-auto}"
BEDOLAGA_DB_CONTAINER="${BEDOLAGA_DB_CONTAINER:-}"
BEDOLAGA_REDIS_CONTAINER="${BEDOLAGA_REDIS_CONTAINER:-}"
BACKUP_ENV_PATH="${BACKUP_ENV_PATH:-/etc/panel-backup.env}"
PBM_DEEP_AUTODETECT="${PBM_DEEP_AUTODETECT:-0}"
BACKUP_LANG="${BACKUP_LANG:-ru}"
BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-0}"
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"
BACKUP_INCLUDE="${BACKUP_INCLUDE:-all}"
BACKUP_INCLUDE_OVERRIDE="${BACKUP_INCLUDE_OVERRIDE:-}"
TELEGRAM_THREAD_ID_PANEL="${TELEGRAM_THREAD_ID_PANEL:-}"
TELEGRAM_THREAD_ID_BEDOLAGA="${TELEGRAM_THREAD_ID_BEDOLAGA:-}"
BEDOLAGA_LOGS_STRATEGY="${BEDOLAGA_LOGS_STRATEGY:-recent}"
BEDOLAGA_LOGS_MAX_FILES="${BEDOLAGA_LOGS_MAX_FILES:-20}"
BEDOLAGA_LOGS_MAX_FILE_BYTES="${BEDOLAGA_LOGS_MAX_FILE_BYTES:-1048576}"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TIMESTAMP_SHORT="$(date -u +%m%d-%H%M%S)"
TIMESTAMP_LOCAL="$(date '+%Y-%m-%d %H:%M:%S %Z')"
TIMESTAMP_UTC_HUMAN="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
WORKDIR="$(mktemp -d /tmp/panel-backup.XXXXXX)"
ARCHIVE_BASE="pb-${TIMESTAMP_SHORT}"
ARCHIVE_PATH="${BACKUP_ROOT}/${ARCHIVE_BASE}.tar.gz"
ARCHIVE_TMP_PATH="${ARCHIVE_PATH}.tmp"
CHECKSUM_PATH=""
LOG_TAG="panel-backup"
LOCK_FILE="${LOCK_FILE:-/var/lock/panel-backup.lock}"
TELEGRAM_ADMIN_ID_RESOLVED=""
TELEGRAM_SEND_ERROR_DESC=""
TELEGRAM_SEND_ERROR_HINT=""
TELEGRAM_UPLOAD_ENABLED=0
declare -a BACKUP_ITEMS=()
WANT_DB=0
WANT_REDIS=0
WANT_ENV=0
WANT_COMPOSE=0
WANT_CADDY=0
WANT_SUBSCRIPTION=0
WANT_BEDOLAGA_DB=0
WANT_BEDOLAGA_REDIS=0
WANT_BEDOLAGA_BOT=0
WANT_BEDOLAGA_CABINET=0
BEDOLAGA_REQUIRED_PROFILE=""

cleanup() {
  rm -rf "$WORKDIR"
  rm -f "$ARCHIVE_TMP_PATH" "${ARCHIVE_TMP_PATH}.gpg"
}
trap cleanup EXIT

log() {
  echo "$*"
  if command -v logger >/dev/null 2>&1; then
    logger -t "$LOG_TAG" "$*" || true
  fi
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

normalize_backup_include() {
  local raw=""
  local item=""
  local has_any=0
  local unknown_items=""

  BACKUP_INCLUDE="${BACKUP_INCLUDE:-all}"
  raw="$(printf '%s' "${BACKUP_INCLUDE,,}" | tr -d '[:space:]')"
  [[ -z "$raw" ]] && raw="all"

  WANT_DB=0
  WANT_REDIS=0
  WANT_ENV=0
  WANT_COMPOSE=0
  WANT_CADDY=0
  WANT_SUBSCRIPTION=0
  WANT_BEDOLAGA_DB=0
  WANT_BEDOLAGA_REDIS=0
  WANT_BEDOLAGA_BOT=0
  WANT_BEDOLAGA_CABINET=0
  BEDOLAGA_REQUIRED_PROFILE=""

  IFS=',' read -r -a __items <<< "$raw"
  for item in "${__items[@]}"; do
    case "$item" in
      all)
        WANT_DB=1
        WANT_REDIS=1
        WANT_ENV=1
        WANT_COMPOSE=1
        WANT_CADDY=1
        WANT_SUBSCRIPTION=1
        ;;
      configs)
        WANT_ENV=1
        WANT_COMPOSE=1
        WANT_CADDY=1
        WANT_SUBSCRIPTION=1
        ;;
      db) WANT_DB=1 ;;
      redis) WANT_REDIS=1 ;;
      env) WANT_ENV=1 ;;
      compose) WANT_COMPOSE=1 ;;
      caddy) WANT_CADDY=1 ;;
      subscription) WANT_SUBSCRIPTION=1 ;;
      bedolaga)
        WANT_BEDOLAGA_DB=1
        WANT_BEDOLAGA_REDIS=1
        WANT_BEDOLAGA_BOT=1
        WANT_BEDOLAGA_CABINET=1
        ;;
      bedolaga-official)
        WANT_BEDOLAGA_DB=1
        WANT_BEDOLAGA_REDIS=1
        WANT_BEDOLAGA_BOT=1
        WANT_BEDOLAGA_CABINET=1
        BEDOLAGA_REQUIRED_PROFILE="official"
        ;;
      bedolaga-fork)
        WANT_BEDOLAGA_DB=1
        WANT_BEDOLAGA_REDIS=1
        WANT_BEDOLAGA_BOT=1
        WANT_BEDOLAGA_CABINET=1
        BEDOLAGA_REQUIRED_PROFILE="fork"
        ;;
      bedolaga-configs)
        WANT_BEDOLAGA_BOT=1
        WANT_BEDOLAGA_CABINET=1
        ;;
      bedolaga-db) WANT_BEDOLAGA_DB=1 ;;
      bedolaga-redis) WANT_BEDOLAGA_REDIS=1 ;;
      bedolaga-official-db)
        WANT_BEDOLAGA_DB=1
        BEDOLAGA_REQUIRED_PROFILE="official"
        ;;
      bedolaga-fork-db)
        WANT_BEDOLAGA_DB=1
        BEDOLAGA_REQUIRED_PROFILE="fork"
        ;;
      bedolaga-official-redis)
        WANT_BEDOLAGA_REDIS=1
        BEDOLAGA_REQUIRED_PROFILE="official"
        ;;
      bedolaga-fork-redis)
        WANT_BEDOLAGA_REDIS=1
        BEDOLAGA_REQUIRED_PROFILE="fork"
        ;;
      bedolaga-bot) WANT_BEDOLAGA_BOT=1 ;;
      bedolaga-cabinet) WANT_BEDOLAGA_CABINET=1 ;;
      "") ;;
      *)
        if [[ -n "$unknown_items" ]]; then
          unknown_items="${unknown_items},${item}"
        else
          unknown_items="$item"
        fi
        ;;
    esac
  done

  if [[ -n "$unknown_items" ]]; then
    fail "$(t "неизвестные компоненты BACKUP_INCLUDE" "unknown BACKUP_INCLUDE components"): ${unknown_items}"
  fi

  (( WANT_DB == 1 )) && has_any=1
  (( WANT_REDIS == 1 )) && has_any=1
  (( WANT_ENV == 1 )) && has_any=1
  (( WANT_COMPOSE == 1 )) && has_any=1
  (( WANT_CADDY == 1 )) && has_any=1
  (( WANT_SUBSCRIPTION == 1 )) && has_any=1
  (( WANT_BEDOLAGA_DB == 1 )) && has_any=1
  (( WANT_BEDOLAGA_REDIS == 1 )) && has_any=1
  (( WANT_BEDOLAGA_BOT == 1 )) && has_any=1
  (( WANT_BEDOLAGA_CABINET == 1 )) && has_any=1

  if (( has_any == 0 )); then
    fail "$(t "не выбран ни один компонент backup (BACKUP_INCLUDE)" "no backup components selected (BACKUP_INCLUDE)")"
  fi

  BACKUP_INCLUDE="$raw"
}

backup_scope_text() {
  local out=""
  local bedolaga_prefix="bedolaga"

  if [[ "$BEDOLAGA_REQUIRED_PROFILE" == "official" || "$BEDOLAGA_REQUIRED_PROFILE" == "fork" ]]; then
    bedolaga_prefix="bedolaga-${BEDOLAGA_REQUIRED_PROFILE}"
  fi

  (( WANT_DB == 1 )) && out="${out}db,"
  (( WANT_REDIS == 1 )) && out="${out}redis,"
  (( WANT_ENV == 1 )) && out="${out}env,"
  (( WANT_COMPOSE == 1 )) && out="${out}compose,"
  (( WANT_CADDY == 1 )) && out="${out}caddy,"
  (( WANT_SUBSCRIPTION == 1 )) && out="${out}subscription,"
  (( WANT_BEDOLAGA_DB == 1 )) && out="${out}${bedolaga_prefix}-db,"
  (( WANT_BEDOLAGA_REDIS == 1 )) && out="${out}${bedolaga_prefix}-redis,"
  (( WANT_BEDOLAGA_BOT == 1 )) && out="${out}bedolaga-bot,"
  (( WANT_BEDOLAGA_CABINET == 1 )) && out="${out}bedolaga-cabinet,"
  out="${out%,}"
  printf '%s' "$out"
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

  guessed="$(find /home /opt /srv /root -maxdepth 7 -type f -name 'docker-compose.yml' 2>/dev/null | while read -r compose_file; do d="$(dirname "$compose_file")"; grep -Eq 'container_name:[[:space:]]*(remnawave_bot|remnawave-bot|remnawave_bot_db|remnawave_bot_redis)([[:space:]]|$)' "$compose_file" || continue; [[ -f "$d/.env" ]] || continue; echo "$d"; break; done)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return 0
  fi

  if [[ "${PBM_DEEP_AUTODETECT:-0}" == "1" ]]; then
    guessed="$(find / -xdev -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do [[ -f "$d/.env" && -f "$d/docker-compose.yml" ]] || continue; echo "$d"; break; done)"
    [[ -n "$guessed" ]] && echo "$guessed"
  fi
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

container_image_ref() {
  local name="$1"
  docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null || true
}

container_version_label() {
  local name="$1"
  local tail=""
  local image_ref=""
  local image_id=""
  local image_info=""
  local image_label_info=""
  local version=""
  local version_from_tag=""
  local revision=""
  local env_version=""
  local compose_workdir=""
  local package_json=""
  local package_version=""
  local runtime_package_version=""

  image_info="$(docker inspect -f '{{.Config.Image}}{{"\n"}}{{.Image}}{{"\n"}}{{ index .Config.Labels "com.docker.compose.project.working_dir" }}{{"\n"}}{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null || true)"
  image_ref="$(printf '%s\n' "$image_info" | sed -n '1p')"
  image_id="$(printf '%s\n' "$image_info" | sed -n '2p')"
  compose_workdir="$(printf '%s\n' "$image_info" | sed -n '3p')"
  [[ "$compose_workdir" == "<no value>" ]] && compose_workdir=""

  if [[ -n "$image_id" ]]; then
    image_label_info="$(docker image inspect -f '{{ index .Config.Labels "org.opencontainers.image.version" }}{{"\n"}}{{ index .Config.Labels "org.label-schema.version" }}{{"\n"}}{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image_id" 2>/dev/null || true)"
    version="$(printf '%s\n' "$image_label_info" | sed -n '1p')"
    [[ "$version" == "<no value>" ]] && version=""
    if [[ -z "$version" ]]; then
      version="$(printf '%s\n' "$image_label_info" | sed -n '2p')"
      [[ "$version" == "<no value>" ]] && version=""
    fi
    revision="$(printf '%s\n' "$image_label_info" | sed -n '3p')"
    [[ "$revision" == "<no value>" ]] && revision=""
  fi

  env_version="$(printf '%s\n' "$image_info" | awk -F= '
    NR>3 && $1=="__RW_METADATA_VERSION" {sub(/^[^=]*=/, ""); print; exit}
    NR>3 && $1=="REMNAWAVE_VERSION" {sub(/^[^=]*=/, ""); print; exit}
    NR>3 && $1=="SUBSCRIPTION_VERSION" {sub(/^[^=]*=/, ""); print; exit}
    NR>3 && $1=="APP_VERSION" {sub(/^[^=]*=/, ""); print; exit}
  ' || true)"

  if [[ -n "$env_version" ]]; then
    if [[ -z "$version" ]]; then
      version="$env_version"
    elif [[ "$version" =~ ^[0-9]+$ ]] && [[ "$env_version" =~ [.-] ]]; then
      version="$env_version"
    fi
  fi

  if [[ -n "$version" ]]; then
    printf '%s' "$version"
    return 0
  fi

  if [[ -n "$compose_workdir" ]]; then
    package_json="${compose_workdir}/package.json"
    if [[ -f "$package_json" ]]; then
      package_version="$(awk -F'"' '/"version"[[:space:]]*:[[:space:]]*"/ { print $4; exit }' "$package_json" 2>/dev/null || true)"
      if [[ -n "$package_version" ]]; then
        printf '%s' "$package_version"
        return 0
      fi
    fi
  fi

  runtime_package_version="$(docker exec "$name" sh -c 'for f in /opt/app/package.json /app/package.json /usr/src/app/package.json; do [ -f "$f" ] || continue; awk -F\" "/\"version\"[[:space:]]*:/ {print \$4; exit}" "$f"; exit 0; done' 2>/dev/null | head -n1 || true)"
  runtime_package_version="${runtime_package_version//$'\r'/}"
  if [[ -n "$runtime_package_version" ]]; then
    printf '%s' "$runtime_package_version"
    return 0
  fi

  if [[ -z "$version" && -n "$image_ref" ]]; then
    tail="${image_ref##*/}"
    if [[ "$tail" == *:* ]]; then
      version_from_tag="${tail##*:}"
      if [[ "$version_from_tag" != "latest" && "$version_from_tag" != sha-* && ! "$version_from_tag" =~ ^[[:xdigit:]]{7,64}$ ]]; then
        version="$version_from_tag"
      fi
    fi
  fi

  if [[ -n "$version" ]]; then
    printf '%s' "$version"
    return 0
  fi

  if [[ -n "$compose_workdir" && -d "${compose_workdir}/.git" ]]; then
    revision="$(git -C "$compose_workdir" rev-parse --short=12 HEAD 2>/dev/null || true)"
    if [[ -n "$revision" ]]; then
      printf '%s' "sha-${revision}"
      return 0
    fi
  fi

  if [[ -n "$image_id" ]]; then
    if [[ -n "$revision" ]]; then
      if [[ ${#revision} -gt 12 ]]; then
        revision="${revision:0:12}"
      fi
      printf '%s' "sha-${revision}"
      return 0
    fi
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
  local detected=""

  if [[ -n "${BEDOLAGA_DB_CONTAINER:-}" ]]; then
    printf '%s' "$BEDOLAGA_DB_CONTAINER"
    return 0
  fi
  detected="$(compose_container_name_for_service "${bot_dir}/docker-compose.yml" "postgres")"
  printf '%s' "${detected:-remnawave_bot_db}"
}

detect_bedolaga_redis_container() {
  local bot_dir="$1"
  local detected=""

  if [[ -n "${BEDOLAGA_REDIS_CONTAINER:-}" ]]; then
    printf '%s' "$BEDOLAGA_REDIS_CONTAINER"
    return 0
  fi
  detected="$(compose_container_name_for_service "${bot_dir}/docker-compose.yml" "redis")"
  printf '%s' "${detected:-remnawave_bot_redis}"
}

assert_bedolaga_required_profile() {
  local actual_profile="$1"
  local required_profile="${BEDOLAGA_REQUIRED_PROFILE:-}"

  [[ -n "$required_profile" ]] || return 0
  if [[ "$actual_profile" == "$required_profile" ]]; then
    return 0
  fi

  fail "$(t "выбран профиль backup" "selected backup profile") ${required_profile}, $(t "но найден Bedolaga профиль" "but detected Bedolaga profile") ${actual_profile}. $(t "Для другой БД используйте правильный компонент или BEDOLAGA_STACK_PROFILE." "Use the correct DB component or BEDOLAGA_STACK_PROFILE for another database.")"
}

has_panel_scope() {
  if (( WANT_DB == 1 || WANT_REDIS == 1 || WANT_ENV == 1 || WANT_COMPOSE == 1 || WANT_CADDY == 1 || WANT_SUBSCRIPTION == 1 )); then
    return 0
  fi
  return 1
}

has_bedolaga_scope() {
  if (( WANT_BEDOLAGA_DB == 1 || WANT_BEDOLAGA_REDIS == 1 || WANT_BEDOLAGA_BOT == 1 || WANT_BEDOLAGA_CABINET == 1 )); then
    return 0
  fi
  return 1
}

backup_scope_profile() {
  local panel=0
  local bedolaga=0
  has_panel_scope && panel=1
  has_bedolaga_scope && bedolaga=1
  if (( panel == 1 && bedolaga == 1 )); then
    printf '%s' "mixed"
    return 0
  fi
  if (( bedolaga == 1 )); then
    printf '%s' "bedolaga"
    return 0
  fi
  printf '%s' "panel"
}

resolve_telegram_chat_id() {
  local raw="${TELEGRAM_ADMIN_ID:-}"
  local has_any_thread=0

  if [[ -n "${TELEGRAM_ADMIN_ID_RESOLVED:-}" ]]; then
    printf '%s' "$TELEGRAM_ADMIN_ID_RESOLVED"
    return 0
  fi

  [[ -n "$raw" ]] || return 0
  if [[ -n "${TELEGRAM_THREAD_ID:-}" || -n "${TELEGRAM_THREAD_ID_PANEL:-}" || -n "${TELEGRAM_THREAD_ID_BEDOLAGA:-}" ]]; then
    has_any_thread=1
  fi

  if [[ "$raw" =~ ^-100[0-9]+$ ]]; then
    TELEGRAM_ADMIN_ID_RESOLVED="$raw"
  elif [[ "$raw" =~ ^[0-9]+$ ]] && (( has_any_thread == 1 )); then
    TELEGRAM_ADMIN_ID_RESOLVED="-100${raw}"
    echo "$(t "Подсказка: TELEGRAM_ADMIN_ID автоматически преобразован в формат супергруппы: " "Hint: TELEGRAM_ADMIN_ID was auto-converted to supergroup format: ")${TELEGRAM_ADMIN_ID_RESOLVED}" >&2
  else
    TELEGRAM_ADMIN_ID_RESOLVED="$raw"
  fi

  printf '%s' "$TELEGRAM_ADMIN_ID_RESOLVED"
}

send_telegram_text() {
  local text="$1"
  local profile="${2:-$(backup_scope_profile)}"
  local chat_id=""
  local thread_id=""
  local thread_args=()
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_ADMIN_ID:-}" ]]; then
    return 0
  fi

  chat_id="$(resolve_telegram_chat_id)"
  thread_id="$(resolve_telegram_thread_id "$profile")"
  if [[ -n "$thread_id" ]]; then
    thread_args+=(-d "message_thread_id=${thread_id}")
  fi
  if ! curl -sS --max-time 20 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${chat_id}" \
    "${thread_args[@]}" \
    --data-urlencode "text=${text}" \
    >/dev/null; then
    log "$(t "Предупреждение: не удалось отправить текстовое сообщение в Telegram" "Warning: failed to send Telegram text message")"
  fi
}

copy_backup_entry() {
  local source_path="$1"
  local target_path="$2"
  local label="$3"
  if ! cp -a "$source_path" "$target_path" 2>/dev/null; then
    fail "$(t "не удалось добавить в backup" "failed to include in backup"): ${label}"
  fi
}

copy_optional_backup_entry() {
  local source_path="$1"
  local target_path="$2"
  local label="$3"
  if [[ ! -e "$source_path" ]]; then
    BACKUP_ITEMS+=("- ${label}: $(t "пропущено, не найдено" "skipped, not found")")
    log "$(t "Предупреждение: компонент не найден и будет пропущен" "Warning: component not found and will be skipped"): ${label}"
    return 0
  fi
  copy_backup_entry "$source_path" "$target_path" "$label"
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

  if [[ -n "$password" ]]; then
    exec_args=(-e "REDISCLI_AUTH=${password}" -e "VALKEYCLI_AUTH=${password}")
  fi
  docker exec "${exec_args[@]}" "$container_name" "$cli" "$@"
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

redis_wait_for_bgsave() {
  local container_name="$1"
  local cli="$2"
  local password="$3"
  local state=""
  local i=0

  for ((i = 0; i < 30; i++)); do
    state="$(redis_exec_cli "$container_name" "$cli" "$password" --raw INFO Persistence 2>/dev/null \
      | awk -F: '/^rdb_bgsave_in_progress:/ {gsub(/\r/, "", $2); print $2; exit}' || true)"
    [[ "$state" != "1" ]] && return 0
    sleep 1
  done
}

copy_redis_dump_from_container() {
  local container_name="$1"
  local target_path="$2"
  shift 2
  local source_path=""

  for source_path in "$@"; do
    [[ -n "$source_path" ]] || continue
    if docker cp "${container_name}:${source_path}" "$target_path" 2>/dev/null && [[ -s "$target_path" ]]; then
      return 0
    fi
    rm -f "$target_path"
  done
  return 1
}

backup_redis_dump() {
  local container_name="$1"
  local target_path="$2"
  local label="$3"
  local env_file="${4:-}"
  local cli=""
  local password=""
  local redis_dir=""
  local redis_dbfilename=""
  local remote_tmp=""
  local tried_paths=()

  mkdir -p "$(dirname "$target_path")"
  cli="$(redis_container_cli "$container_name")"
  password="$(redis_container_password "$container_name" "$env_file")"
  remote_tmp="/tmp/panel-backup-${TIMESTAMP_SHORT}-$$.rdb"

  if [[ -n "$cli" ]]; then
    if redis_exec_cli "$container_name" "$cli" "$password" --rdb "$remote_tmp" >/dev/null 2>&1; then
      if copy_redis_dump_from_container "$container_name" "$target_path" "$remote_tmp"; then
        docker exec "$container_name" rm -f "$remote_tmp" >/dev/null 2>&1 || true
        return 0
      fi
    fi
    docker exec "$container_name" rm -f "$remote_tmp" >/dev/null 2>&1 || true

    if ! redis_exec_cli "$container_name" "$cli" "$password" save >/dev/null 2>&1; then
      if redis_exec_cli "$container_name" "$cli" "$password" bgsave >/dev/null 2>&1; then
        redis_wait_for_bgsave "$container_name" "$cli" "$password"
      fi
    fi

    redis_dir="$(redis_config_value "$container_name" "$cli" "$password" "dir")"
    redis_dbfilename="$(redis_config_value "$container_name" "$cli" "$password" "dbfilename")"
  fi

  [[ -n "$redis_dir" ]] || redis_dir="/data"
  [[ -n "$redis_dbfilename" ]] || redis_dbfilename="dump.rdb"
  tried_paths+=("${redis_dir%/}/${redis_dbfilename}")
  tried_paths+=("/data/dump.rdb" "/data/redis/dump.rdb" "/var/lib/redis/dump.rdb")

  if copy_redis_dump_from_container "$container_name" "$target_path" "${tried_paths[@]}"; then
    return 0
  fi

  log "$(t "Диагностика Redis dump" "Redis dump diagnostics") (${label}):"
  docker exec "$container_name" sh -lc 'ls -lah /data /data/redis /var/lib/redis /tmp 2>/dev/null || true' 2>/dev/null | tail -n 40 || true
  fail "$(t "не удалось получить Redis dump" "failed to get Redis dump"): ${label} (${container_name}). $(t "Пробовал live export и пути" "Tried live export and paths"): ${tried_paths[*]}"
}

backup_bedolaga_logs() {
  local source_dir="$1"
  local target_dir="$2"
  local strategy="${BEDOLAGA_LOGS_STRATEGY,,}"
  local max_files="${BEDOLAGA_LOGS_MAX_FILES}"
  local max_file_bytes="${BEDOLAGA_LOGS_MAX_FILE_BYTES}"
  local selected_files=()
  local entry=""
  local src=""
  local rel=""
  local dst=""

  [[ -d "$source_dir" ]] || return 0
  mkdir -p "$target_dir"

  if [[ "$strategy" == "none" ]]; then
    BACKUP_ITEMS+=("- Bedolaga bot logs: skipped (strategy=none)")
    return 0
  fi

  if [[ "$strategy" == "full" ]]; then
    copy_backup_entry "$source_dir" "$target_dir" "bedolaga bot logs"
    BACKUP_ITEMS+=("- Bedolaga bot logs: full copy ($(du -sh "$target_dir/logs" | awk '{print $1}'))")
    return 0
  fi

  [[ "$max_files" =~ ^[0-9]+$ ]] || max_files=20
  [[ "$max_file_bytes" =~ ^[0-9]+$ ]] || max_file_bytes=1048576
  (( max_files > 0 )) || max_files=20
  (( max_file_bytes > 0 )) || max_file_bytes=1048576

  while IFS= read -r entry; do
    src="${entry#* }"
    selected_files+=("$src")
  done < <(find "$source_dir" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n "$max_files")

  for src in "${selected_files[@]}"; do
    rel="${src#"$source_dir"/}"
    dst="${target_dir}/logs/${rel}"
    mkdir -p "$(dirname "$dst")"
    if [[ ! -f "$src" ]]; then
      continue
    fi
    if [[ ! -s "$src" ]]; then
      : > "$dst"
      continue
    fi
    if [[ $(stat -c '%s' "$src" 2>/dev/null || echo 0) -le "$max_file_bytes" ]]; then
      cp -a "$src" "$dst"
    else
      tail -c "$max_file_bytes" "$src" > "$dst"
    fi
  done

  BACKUP_ITEMS+=("- Bedolaga bot logs: recent (${#selected_files[@]} files, <=${max_file_bytes} bytes each)")
}

send_telegram_file() {
  local file_path="$1"
  local caption="$2"
  local profile="${3:-$(backup_scope_profile)}"
  local caption_html=""
  local fallback_caption=""
  local chat_id=""
  local response
  local thread_id=""
  local thread_args=()
  local response_desc=""

  TELEGRAM_SEND_ERROR_DESC=""
  TELEGRAM_SEND_ERROR_HINT=""
  chat_id="$(resolve_telegram_chat_id)"
  thread_id="$(resolve_telegram_thread_id "$profile")"
  if [[ -n "$thread_id" ]]; then
    thread_args+=(-F "message_thread_id=${thread_id}")
  fi
  caption_html="$caption"
  if (( ${#caption_html} > 900 )); then
    caption_html="${caption_html:0:897}..."
  fi

  response="$(curl -sS --max-time 300 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${chat_id}" \
    "${thread_args[@]}" \
    -F "parse_mode=HTML" \
    -F "caption=${caption_html}" \
    -F "document=@${file_path}")" || return 1

  if echo "$response" | grep -q '"ok":true'; then
    return 0
  fi

  response_desc="$(echo "$response" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')"
  [[ -n "$response_desc" ]] && log "$(t "Telegram ошибка (HTML-caption):" "Telegram error (HTML caption):") ${response_desc}"
  TELEGRAM_SEND_ERROR_DESC="$response_desc"
  case "${response_desc,,}" in
    *"chat not found"*|*"forbidden"*|*"not enough rights"*|*"have no rights"*)
      TELEGRAM_SEND_ERROR_HINT="$(t "нет прав на отправку в чат/топик или бот не добавлен в чат" "no permission to send to chat/topic or bot is not added to chat")"
      ;;
  esac
  log "$(t "Предупреждение: Telegram отклонил HTML-caption, пробую безопасный текстовый caption" "Warning: Telegram rejected HTML caption, trying safe plain-text caption")"
  fallback_caption="$(build_caption_plain "$(basename "$file_path")")"
  if (( ${#fallback_caption} > 900 )); then
    fallback_caption="${fallback_caption:0:897}..."
  fi
  response="$(curl -sS --max-time 300 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${chat_id}" \
    "${thread_args[@]}" \
    -F "caption=${fallback_caption}" \
    -F "document=@${file_path}")" || return 1

  if echo "$response" | grep -q '"ok":true'; then
    return 0
  fi
  response_desc="$(echo "$response" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')"
  [[ -n "$response_desc" ]] && log "$(t "Telegram ошибка (plain-caption):" "Telegram error (plain caption):") ${response_desc}"
  TELEGRAM_SEND_ERROR_DESC="$response_desc"
  case "${response_desc,,}" in
    *"chat not found"*|*"forbidden"*|*"not enough rights"*|*"have no rights"*)
      TELEGRAM_SEND_ERROR_HINT="$(t "нет прав на отправку в чат/топик или бот не добавлен в чат" "no permission to send to chat/topic or bot is not added to chat")"
      ;;
  esac
  return 1
}

resolve_telegram_thread_id() {
  local profile="${1:-panel}"

  case "$profile" in
    panel)
      if [[ -n "${TELEGRAM_THREAD_ID_PANEL:-}" ]]; then
        printf '%s' "${TELEGRAM_THREAD_ID_PANEL}"
        return 0
      fi
      ;;
    bedolaga)
      if [[ -n "${TELEGRAM_THREAD_ID_BEDOLAGA:-}" ]]; then
        printf '%s' "${TELEGRAM_THREAD_ID_BEDOLAGA}"
        return 0
      fi
      ;;
    mixed)
      if [[ -n "${TELEGRAM_THREAD_ID:-}" ]]; then
        printf '%s' "${TELEGRAM_THREAD_ID}"
        return 0
      fi
      if [[ -n "${TELEGRAM_THREAD_ID_PANEL:-}" ]]; then
        printf '%s' "${TELEGRAM_THREAD_ID_PANEL}"
        return 0
      fi
      if [[ -n "${TELEGRAM_THREAD_ID_BEDOLAGA:-}" ]]; then
        printf '%s' "${TELEGRAM_THREAD_ID_BEDOLAGA}"
        return 0
      fi
      ;;
  esac

  if [[ -n "${TELEGRAM_THREAD_ID:-}" ]]; then
    printf '%s' "${TELEGRAM_THREAD_ID}"
  fi
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
  local error_label=""
  local profile=""
  log "ERROR: ${msg}"
  profile="$(backup_scope_profile)"
  case "$profile" in
    bedolaga) error_label="$(t "Ошибка backup бота/кабинета" "Bot/cabinet backup error")" ;;
    mixed) error_label="$(t "Ошибка backup панели + бота/кабинета" "Panel + bot/cabinet backup error")" ;;
    *) error_label="$(t "Ошибка backup панели" "Panel backup error")" ;;
  esac
  send_telegram_text "ERROR: ${error_label}: ${HOSTNAME_FQDN}
${msg}
$(t "Время (локальное):" "Time (local):") ${TIMESTAMP_LOCAL}
$(t "Время (UTC):" "Time (UTC):") ${TIMESTAMP_UTC_HUMAN}" \
    "$profile"
  exit 1
}

ensure_dependencies() {
  local cmd=""
  for cmd in docker tar curl split du stat find awk grep sed flock tail; do
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
  local bot_size=0
  local cabinet_size=0
  local safety_bytes=$((200 * 1024 * 1024))
  if (( WANT_ENV == 1 || WANT_COMPOSE == 1 || WANT_CADDY == 1 || WANT_SUBSCRIPTION == 1 )); then
    rem_size="$(du -sb "$REMNAWAVE_DIR" 2>/dev/null | awk '{print $1}' || echo 0)"
  fi
  if (( WANT_BEDOLAGA_BOT == 1 )); then
    bot_size="$(du -sb "$BEDOLAGA_BOT_DIR" 2>/dev/null | awk '{print $1}' || echo 0)"
  fi
  if (( WANT_BEDOLAGA_CABINET == 1 )); then
    cabinet_size="$(du -sb "$BEDOLAGA_CABINET_DIR" 2>/dev/null | awk '{print $1}' || echo 0)"
  fi
  if [[ ! "$rem_size" =~ ^[0-9]+$ ]]; then
    rem_size=0
  fi
  if [[ ! "$bot_size" =~ ^[0-9]+$ ]]; then
    bot_size=0
  fi
  if [[ ! "$cabinet_size" =~ ^[0-9]+$ ]]; then
    cabinet_size=0
  fi
  echo $((rem_size + bot_size + cabinet_size + safety_bytes))
}

available_backup_root_bytes() {
  df -Pk "$BACKUP_ROOT" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' || echo 0
}

create_checksum_file() {
  local archive_path="$1"
  local checksum_path="${archive_path}.sha256"
  local archive_dir=""
  local archive_name=""
  local checksum_name=""

  if ! command -v sha256sum >/dev/null 2>&1; then
    log "$(t "Предупреждение: sha256sum не найден, checksum не создан" "Warning: sha256sum not found, checksum was not created")"
    CHECKSUM_PATH=""
    return 0
  fi

  archive_dir="$(dirname "$archive_path")"
  archive_name="$(basename "$archive_path")"
  checksum_name="$(basename "$checksum_path")"
  (
    cd "$archive_dir"
    sha256sum "$archive_name" > "$checksum_name"
  )
  CHECKSUM_PATH="$checksum_path"
  log "$(t "Checksum создан:" "Checksum created:") ${CHECKSUM_PATH}"
}

preflight_checks() {
  local need_bytes=0
  local free_bytes=0

  ensure_dependencies
  (( WANT_DB == 1 )) && check_container_present remnawave-db
  (( WANT_REDIS == 1 )) && check_container_present remnawave-redis
  (( WANT_BEDOLAGA_DB == 1 )) && check_container_present "$BEDOLAGA_DB_CONTAINER"
  (( WANT_BEDOLAGA_REDIS == 1 )) && check_container_present "$BEDOLAGA_REDIS_CONTAINER"

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
  local profile=""
  local title=""
  local scope_label=""
  local file_label_e=""
  local host_e=""
  local time_e=""
  local size_e=""
  local panel_e=""
  local sub_e=""
  local bot_e=""
  local cabinet_e=""
  local enc_label=""
  local versions_block=""
  file_label_e="$(escape_html "$file_label")"
  host_e="$(escape_html "$HOSTNAME_FQDN")"
  time_e="$(escape_html "$TIMESTAMP_LOCAL")"
  size_e="$(escape_html "$ARCHIVE_SIZE_HUMAN")"
  panel_e="$(escape_html "$PANEL_VERSION")"
  sub_e="$(escape_html "$SUBSCRIPTION_VERSION")"
  bot_e="$(escape_html "$BEDOLAGA_BOT_VERSION")"
  cabinet_e="$(escape_html "$BEDOLAGA_CABINET_VERSION")"

  if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
    enc_label="$(t "включено (GPG)" "enabled (GPG)")"
  else
    enc_label="$(t "выключено" "disabled")"
  fi

  profile="$(backup_scope_profile)"
  case "$profile" in
    bedolaga)
      title="$(t "Backup Bedolaga (бот + кабинет)" "Backup Bedolaga (bot + cabinet)")"
      scope_label="bedolaga-only"
      versions_block="🤖 <b>$(t "Версия Bedolaga бота" "Bedolaga bot version"):</b> <code>${bot_e}</code>
🗂 <b>$(t "Версия Bedolaga кабинета" "Bedolaga cabinet version"):</b> <code>${cabinet_e}</code>"
      ;;
    mixed)
      title="$(t "Backup Remnawave + Bedolaga" "Backup Remnawave + Bedolaga")"
      scope_label="mixed"
      versions_block="🧩 <b>$(t "Версия панели" "Panel version"):</b> <code>${panel_e}</code>
🧷 <b>$(t "Версия подписки" "Subscription version"):</b> <code>${sub_e}</code>
🤖 <b>$(t "Версия Bedolaga бота" "Bedolaga bot version"):</b> <code>${bot_e}</code>
🗂 <b>$(t "Версия Bedolaga кабинета" "Bedolaga cabinet version"):</b> <code>${cabinet_e}</code>"
      ;;
    *)
      title="Backup Remnawave"
      scope_label="panel-only"
      versions_block="🧩 <b>$(t "Версия панели" "Panel version"):</b> <code>${panel_e}</code>
🧷 <b>$(t "Версия подписки" "Subscription version"):</b> <code>${sub_e}</code>"
      ;;
  esac

  printf '%s' "📦 <b>${title}</b>
📁 <b>$(t "Файл" "File"):</b> <code>${file_label_e}</code>
🖥 <b>$(t "Хост" "Host"):</b> <code>${host_e}</code>
🕒 <b>$(t "Время" "Time"):</b> <code>${time_e}</code>
📏 <b>$(t "Размер" "Size"):</b> <code>${size_e}</code>
🎯 <b>Scope:</b> <code>${scope_label}</code>
${versions_block}
🔐 <b>$(t "Шифрование" "Encryption"):</b> <code>${enc_label}</code>
📋 <b>$(t "Состав" "Contents"):</b> <code>$(backup_scope_text)</code>"
}

build_caption_plain() {
  local file_label="$1"
  local profile=""
  local title=""
  local scope_label=""
  local enc_label=""
  local versions_block=""

  if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
    enc_label="$(t "включено (GPG)" "enabled (GPG)")"
  else
    enc_label="$(t "выключено" "disabled")"
  fi

  profile="$(backup_scope_profile)"
  case "$profile" in
    bedolaga)
      title="$(t "Backup Bedolaga (бот + кабинет)" "Backup Bedolaga (bot + cabinet)")"
      scope_label="bedolaga-only"
      versions_block="$(t "Версия Bedolaga бота" "Bedolaga bot version"): ${BEDOLAGA_BOT_VERSION}
$(t "Версия Bedolaga кабинета" "Bedolaga cabinet version"): ${BEDOLAGA_CABINET_VERSION}"
      ;;
    mixed)
      title="$(t "Backup Remnawave + Bedolaga" "Backup Remnawave + Bedolaga")"
      scope_label="mixed"
      versions_block="$(t "Версия панели" "Panel version"): ${PANEL_VERSION}
$(t "Версия подписки" "Subscription version"): ${SUBSCRIPTION_VERSION}
$(t "Версия Bedolaga бота" "Bedolaga bot version"): ${BEDOLAGA_BOT_VERSION}
$(t "Версия Bedolaga кабинета" "Bedolaga cabinet version"): ${BEDOLAGA_CABINET_VERSION}"
      ;;
    *)
      title="Backup Remnawave"
      scope_label="panel-only"
      versions_block="$(t "Версия панели" "Panel version"): ${PANEL_VERSION}
$(t "Версия подписки" "Subscription version"): ${SUBSCRIPTION_VERSION}"
      ;;
  esac

  printf '%s' "${title}
$(t "Файл" "File"): ${file_label}
$(t "Хост" "Host"): ${HOSTNAME_FQDN}
$(t "Время" "Time"): ${TIMESTAMP_LOCAL}
$(t "Размер" "Size"): ${ARCHIVE_SIZE_HUMAN}
Scope: ${scope_label}
${versions_block}
$(t "Шифрование" "Encryption"): ${enc_label}
$(t "Состав" "Contents"): $(backup_scope_text)"
}

build_checksum_caption() {
  local file_label="$1"
  local file_label_e=""
  local host_e=""
  local time_e=""

  file_label_e="$(escape_html "$file_label")"
  host_e="$(escape_html "$HOSTNAME_FQDN")"
  time_e="$(escape_html "$TIMESTAMP_UTC_HUMAN")"

  printf '%s' "<b>SHA256 checksum</b>
$(t "Файл" "File"): <code>${file_label_e}</code>
$(t "Хост" "Host"): <code>${host_e}</code>
$(t "Время UTC" "UTC time"): <code>${time_e}</code>"
}

normalize_env_file_format
if [[ -f "$BACKUP_ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$BACKUP_ENV_PATH"
fi
if [[ -n "${BACKUP_INCLUDE_OVERRIDE:-}" ]]; then
  BACKUP_INCLUDE="$BACKUP_INCLUDE_OVERRIDE"
fi
normalize_backup_lang
normalize_backup_encrypt
normalize_backup_include

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  fail "$(t "backup уже выполняется (блокировка активна)" "backup is already running (lock is active)")"
fi

REMNAWAVE_DIR="${REMNAWAVE_DIR:-$(detect_remnawave_dir || true)}"
BEDOLAGA_BOT_DIR="${BEDOLAGA_BOT_DIR:-$(detect_bedolaga_bot_dir || true)}"
BEDOLAGA_CABINET_DIR="${BEDOLAGA_CABINET_DIR:-$(detect_bedolaga_cabinet_dir || true)}"
PANEL_VERSION="$(container_version_label remnawave)"
SUBSCRIPTION_VERSION="$(container_version_label remnawave-subscription-page)"
BEDOLAGA_BOT_VERSION="$(container_version_label remnawave_bot)"
BEDOLAGA_CABINET_VERSION="$(container_version_label cabinet_frontend)"
POSTGRES_USER=""
POSTGRES_DB=""
BEDOLAGA_POSTGRES_USER=""
BEDOLAGA_POSTGRES_DB=""
BEDOLAGA_BOT_REPO_ORIGIN=""
BEDOLAGA_CABINET_REPO_ORIGIN=""
BEDOLAGA_STACK_PROFILE_RESOLVED="unknown"
BEDOLAGA_DB_DUMP_PROFILE="unknown"

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_ADMIN_ID:-}" ]]; then
  TELEGRAM_UPLOAD_ENABLED=1
elif [[ -n "${TELEGRAM_BOT_TOKEN:-}" || -n "${TELEGRAM_ADMIN_ID:-}" ]]; then
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || fail "не найден TELEGRAM_BOT_TOKEN в ${BACKUP_ENV_PATH}"
  [[ -n "${TELEGRAM_ADMIN_ID:-}" ]] || fail "не найден TELEGRAM_ADMIN_ID в ${BACKUP_ENV_PATH}"
fi

# If user provided stale paths in env, auto-fallback to detected valid dirs.
if [[ -n "${REMNAWAVE_DIR:-}" ]] && [[ ! -d "${REMNAWAVE_DIR}" ]]; then
  _detected_remnawave_dir="$(detect_remnawave_dir || true)"
  if [[ -n "$_detected_remnawave_dir" ]]; then
    log "$(t "Предупреждение: REMNAWAVE_DIR недоступен, использую автонайденный путь" "Warning: REMNAWAVE_DIR is unavailable, using detected path"): ${_detected_remnawave_dir}"
    REMNAWAVE_DIR="$_detected_remnawave_dir"
  fi
fi
if [[ -n "${BEDOLAGA_BOT_DIR:-}" ]] && [[ ! -d "${BEDOLAGA_BOT_DIR}" ]]; then
  _detected_bedolaga_bot_dir="$(detect_bedolaga_bot_dir || true)"
  if [[ -n "$_detected_bedolaga_bot_dir" ]]; then
    log "$(t "Предупреждение: BEDOLAGA_BOT_DIR недоступен, использую автонайденный путь" "Warning: BEDOLAGA_BOT_DIR is unavailable, using detected path"): ${_detected_bedolaga_bot_dir}"
    BEDOLAGA_BOT_DIR="$_detected_bedolaga_bot_dir"
  fi
fi
if [[ -n "${BEDOLAGA_CABINET_DIR:-}" ]] && [[ ! -d "${BEDOLAGA_CABINET_DIR}" ]]; then
  _detected_bedolaga_cabinet_dir="$(detect_bedolaga_cabinet_dir || true)"
  if [[ -n "$_detected_bedolaga_cabinet_dir" ]]; then
    log "$(t "Предупреждение: BEDOLAGA_CABINET_DIR недоступен, использую автонайденный путь" "Warning: BEDOLAGA_CABINET_DIR is unavailable, using detected path"): ${_detected_bedolaga_cabinet_dir}"
    BEDOLAGA_CABINET_DIR="$_detected_bedolaga_cabinet_dir"
  fi
fi

if (( WANT_BEDOLAGA_DB == 1 || WANT_BEDOLAGA_REDIS == 1 || WANT_BEDOLAGA_BOT == 1 || WANT_BEDOLAGA_CABINET == 1 )); then
  BEDOLAGA_BOT_REPO_ORIGIN="$(bedolaga_repo_origin_url "${BEDOLAGA_BOT_DIR:-}")"
  BEDOLAGA_CABINET_REPO_ORIGIN="$(bedolaga_repo_origin_url "${BEDOLAGA_CABINET_DIR:-}")"
  BEDOLAGA_STACK_PROFILE_RESOLVED="$(detect_bedolaga_stack_profile "${BEDOLAGA_BOT_DIR:-}")"
  BEDOLAGA_DB_DUMP_PROFILE="$BEDOLAGA_STACK_PROFILE_RESOLVED"
  BEDOLAGA_DB_CONTAINER="$(detect_bedolaga_db_container "${BEDOLAGA_BOT_DIR:-}")"
  BEDOLAGA_REDIS_CONTAINER="$(detect_bedolaga_redis_container "${BEDOLAGA_BOT_DIR:-}")"
  assert_bedolaga_required_profile "$BEDOLAGA_STACK_PROFILE_RESOLVED"
  log "$(t "Профиль Bedolaga:" "Bedolaga profile:") ${BEDOLAGA_STACK_PROFILE_RESOLVED} ($(t "DB контейнер" "DB container"): ${BEDOLAGA_DB_CONTAINER}, Redis: ${BEDOLAGA_REDIS_CONTAINER})"
fi

if (( WANT_DB == 1 || WANT_ENV == 1 || WANT_COMPOSE == 1 || WANT_CADDY == 1 || WANT_SUBSCRIPTION == 1 )); then
  if [[ -z "${REMNAWAVE_DIR:-}" ]]; then
    fail "$(t "не найден путь панели Remnawave (REMNAWAVE_DIR)" "Remnawave panel path not found (REMNAWAVE_DIR)")"
  fi
  [[ -d "$REMNAWAVE_DIR" ]] || fail "$(t "не найдена директория панели" "panel directory not found"): ${REMNAWAVE_DIR}"
fi
if (( WANT_DB == 1 || WANT_ENV == 1 )); then
  [[ -f "${REMNAWAVE_DIR}/.env" ]] || fail "не найден ${REMNAWAVE_DIR}/.env"
fi
if (( WANT_BEDOLAGA_BOT == 1 || WANT_BEDOLAGA_DB == 1 )); then
  if [[ -z "${BEDOLAGA_BOT_DIR:-}" ]]; then
    fail "$(t "не найден путь бота Bedolaga (BEDOLAGA_BOT_DIR)" "Bedolaga bot path not found (BEDOLAGA_BOT_DIR)")"
  fi
  [[ -d "$BEDOLAGA_BOT_DIR" ]] || fail "$(t "не найдена директория бота Bedolaga" "Bedolaga bot directory not found"): ${BEDOLAGA_BOT_DIR}"
  [[ -f "${BEDOLAGA_BOT_DIR}/.env" ]] || fail "не найден ${BEDOLAGA_BOT_DIR}/.env"
fi
if (( WANT_BEDOLAGA_CABINET == 1 )); then
  if [[ -z "${BEDOLAGA_CABINET_DIR:-}" ]]; then
    fail "$(t "не найден путь кабинета Bedolaga (BEDOLAGA_CABINET_DIR)" "Bedolaga cabinet path not found (BEDOLAGA_CABINET_DIR)")"
  fi
  [[ -d "$BEDOLAGA_CABINET_DIR" ]] || fail "$(t "не найдена директория кабинета Bedolaga" "Bedolaga cabinet directory not found"): ${BEDOLAGA_CABINET_DIR}"
  [[ -f "${BEDOLAGA_CABINET_DIR}/.env" ]] || fail "не найден ${BEDOLAGA_CABINET_DIR}/.env"
fi
preflight_checks

if (( WANT_DB == 1 )); then
  POSTGRES_USER="$(grep -E '^POSTGRES_USER=' "${REMNAWAVE_DIR}/.env" | head -n1 | cut -d= -f2-)"
  POSTGRES_DB="$(grep -E '^POSTGRES_DB=' "${REMNAWAVE_DIR}/.env" | head -n1 | cut -d= -f2-)"
  [[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]] || fail "не удалось прочитать POSTGRES_USER/POSTGRES_DB"
fi
if (( WANT_BEDOLAGA_DB == 1 )); then
  BEDOLAGA_POSTGRES_USER="$(grep -E '^POSTGRES_USER=' "${BEDOLAGA_BOT_DIR}/.env" | head -n1 | cut -d= -f2-)"
  BEDOLAGA_POSTGRES_DB="$(grep -E '^POSTGRES_DB=' "${BEDOLAGA_BOT_DIR}/.env" | head -n1 | cut -d= -f2-)"
  [[ -n "$BEDOLAGA_POSTGRES_USER" && -n "$BEDOLAGA_POSTGRES_DB" ]] || fail "не удалось прочитать POSTGRES_USER/POSTGRES_DB для bedolaga"
fi

mkdir -p "$BACKUP_ROOT"
mkdir -p "$WORKDIR/payload"
if (( WANT_ENV == 1 || WANT_COMPOSE == 1 || WANT_CADDY == 1 || WANT_SUBSCRIPTION == 1 )); then
  mkdir -p "$WORKDIR/payload/remnawave"
fi
if (( WANT_BEDOLAGA_BOT == 1 )); then
  mkdir -p "$WORKDIR/payload/bedolaga/bot"
fi
if (( WANT_BEDOLAGA_CABINET == 1 )); then
  mkdir -p "$WORKDIR/payload/bedolaga/cabinet"
fi

if (( WANT_DB == 1 )); then
  log "Создаю дамп PostgreSQL (${POSTGRES_DB})"
  docker exec remnawave-db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -Z9 > "$WORKDIR/payload/remnawave-db.dump" \
    || fail "ошибка pg_dump remnawave-db"
  BACKUP_ITEMS+=("- PostgreSQL dump: включено ($(du -h "$WORKDIR/payload/remnawave-db.dump" | awk '{print $1}'))")
fi

if (( WANT_REDIS == 1 )); then
  log "Сохраняю Redis dump"
  backup_redis_dump "remnawave-redis" "$WORKDIR/payload/remnawave-redis.rdb" "Remnawave Redis" "${REMNAWAVE_DIR}/.env"
  [[ -f "$WORKDIR/payload/remnawave-redis.rdb" ]] \
    || fail "$(t "Redis dump не найден после копирования" "Redis dump not found after copy")"
  BACKUP_ITEMS+=("- Redis dump: включено ($(du -h "$WORKDIR/payload/remnawave-redis.rdb" | awk '{print $1}'))")
fi

if (( WANT_COMPOSE == 1 || WANT_ENV == 1 || WANT_CADDY == 1 || WANT_SUBSCRIPTION == 1 )); then
  log "Копирую конфиги Remnawave"
  (( WANT_COMPOSE == 1 )) && copy_backup_entry "${REMNAWAVE_DIR}/docker-compose.yml" "$WORKDIR/payload/remnawave/" "docker-compose.yml"
  (( WANT_ENV == 1 )) && copy_backup_entry "${REMNAWAVE_DIR}/.env" "$WORKDIR/payload/remnawave/" ".env"
  (( WANT_CADDY == 1 )) && copy_optional_backup_entry "${REMNAWAVE_DIR}/caddy" "$WORKDIR/payload/remnawave/" "caddy"
  (( WANT_SUBSCRIPTION == 1 )) && copy_optional_backup_entry "${REMNAWAVE_DIR}/subscription" "$WORKDIR/payload/remnawave/" "subscription"
  (( WANT_COMPOSE == 1 )) && add_backup_item "Docker Compose (remnawave/docker-compose.yml)" "$WORKDIR/payload/remnawave/docker-compose.yml"
  (( WANT_ENV == 1 )) && add_backup_item "ENV (remnawave/.env)" "$WORKDIR/payload/remnawave/.env"
  (( WANT_CADDY == 1 )) && [[ -e "$WORKDIR/payload/remnawave/caddy" ]] && add_backup_item "Caddy config (remnawave/caddy)" "$WORKDIR/payload/remnawave/caddy"
  (( WANT_SUBSCRIPTION == 1 )) && [[ -e "$WORKDIR/payload/remnawave/subscription" ]] && add_backup_item "Subscription page (remnawave/subscription)" "$WORKDIR/payload/remnawave/subscription"
fi

if (( WANT_BEDOLAGA_DB == 1 )); then
  log "Создаю дамп PostgreSQL Bedolaga (${BEDOLAGA_POSTGRES_DB})"
  mkdir -p "$WORKDIR/payload/bedolaga/db/${BEDOLAGA_DB_DUMP_PROFILE}"
  docker exec "$BEDOLAGA_DB_CONTAINER" pg_dump -U "$BEDOLAGA_POSTGRES_USER" -d "$BEDOLAGA_POSTGRES_DB" -Fc -Z9 > "$WORKDIR/payload/bedolaga/db/${BEDOLAGA_DB_DUMP_PROFILE}/postgres.dump" \
    || fail "ошибка pg_dump ${BEDOLAGA_DB_CONTAINER}"
  ln -sf "bedolaga/db/${BEDOLAGA_DB_DUMP_PROFILE}/postgres.dump" "$WORKDIR/payload/bedolaga-bot-db.dump"
  BACKUP_ITEMS+=("- Bedolaga PostgreSQL dump (${BEDOLAGA_DB_DUMP_PROFILE}): включено ($(du -h "$WORKDIR/payload/bedolaga/db/${BEDOLAGA_DB_DUMP_PROFILE}/postgres.dump" | awk '{print $1}'))")
fi

if (( WANT_BEDOLAGA_REDIS == 1 )); then
  log "Сохраняю Redis dump Bedolaga"
  mkdir -p "$WORKDIR/payload/bedolaga/redis/${BEDOLAGA_DB_DUMP_PROFILE}"
  backup_redis_dump "$BEDOLAGA_REDIS_CONTAINER" "$WORKDIR/payload/bedolaga/redis/${BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb" "Bedolaga Redis" "${BEDOLAGA_BOT_DIR}/.env"
  [[ -f "$WORKDIR/payload/bedolaga/redis/${BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb" ]] \
    || fail "$(t "Redis dump Bedolaga не найден после копирования" "Bedolaga Redis dump not found after copy")"
  ln -sf "bedolaga/redis/${BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb" "$WORKDIR/payload/bedolaga-bot-redis.rdb"
  BACKUP_ITEMS+=("- Bedolaga Redis dump (${BEDOLAGA_DB_DUMP_PROFILE}): включено ($(du -h "$WORKDIR/payload/bedolaga/redis/${BEDOLAGA_DB_DUMP_PROFILE}/dump.rdb" | awk '{print $1}'))")
fi

if (( WANT_BEDOLAGA_BOT == 1 )); then
  log "Копирую данные Bedolaga бота"
  copy_backup_entry "${BEDOLAGA_BOT_DIR}/docker-compose.yml" "$WORKDIR/payload/bedolaga/bot/" "bedolaga bot docker-compose.yml"
  copy_backup_entry "${BEDOLAGA_BOT_DIR}/.env" "$WORKDIR/payload/bedolaga/bot/" "bedolaga bot .env"
  [[ -f "${BEDOLAGA_BOT_DIR}/docker-compose.override.yml" ]] && copy_backup_entry "${BEDOLAGA_BOT_DIR}/docker-compose.override.yml" "$WORKDIR/payload/bedolaga/bot/" "bedolaga bot docker-compose.override.yml"
  if [[ -d "${BEDOLAGA_BOT_DIR}/data" ]]; then
    copy_backup_entry "${BEDOLAGA_BOT_DIR}/data" "$WORKDIR/payload/bedolaga/bot/" "bedolaga bot data"
    rm -rf "$WORKDIR/payload/bedolaga/bot/data/backups"
  fi
  backup_bedolaga_logs "${BEDOLAGA_BOT_DIR}/logs" "$WORKDIR/payload/bedolaga/bot"
  [[ -d "${BEDOLAGA_BOT_DIR}/locales" ]] && copy_backup_entry "${BEDOLAGA_BOT_DIR}/locales" "$WORKDIR/payload/bedolaga/bot/" "bedolaga bot locales"
  [[ -f "${BEDOLAGA_BOT_DIR}/vpn_logo.png" ]] && copy_backup_entry "${BEDOLAGA_BOT_DIR}/vpn_logo.png" "$WORKDIR/payload/bedolaga/bot/" "bedolaga bot vpn_logo.png"
  add_backup_item "Bedolaga bot ENV (.env)" "$WORKDIR/payload/bedolaga/bot/.env"
  add_backup_item "Bedolaga bot compose (docker-compose.yml)" "$WORKDIR/payload/bedolaga/bot/docker-compose.yml"
  add_backup_item "Bedolaga bot data (data, without backups)" "$WORKDIR/payload/bedolaga/bot/data"
  add_backup_item "Bedolaga bot logs (logs subset)" "$WORKDIR/payload/bedolaga/bot/logs"
fi

if (( WANT_BEDOLAGA_CABINET == 1 )); then
  log "Копирую данные Bedolaga кабинета"
  copy_backup_entry "${BEDOLAGA_CABINET_DIR}/.env" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet .env"
  [[ -f "${BEDOLAGA_CABINET_DIR}/docker-compose.yml" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/docker-compose.yml" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet docker-compose.yml"
  [[ -f "${BEDOLAGA_CABINET_DIR}/docker-compose.override.yml" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/docker-compose.override.yml" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet docker-compose.override.yml"
  [[ -f "${BEDOLAGA_CABINET_DIR}/package.json" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/package.json" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet package.json"
  [[ -f "${BEDOLAGA_CABINET_DIR}/package-lock.json" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/package-lock.json" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet package-lock.json"
  [[ -f "${BEDOLAGA_CABINET_DIR}/yarn.lock" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/yarn.lock" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet yarn.lock"
  [[ -f "${BEDOLAGA_CABINET_DIR}/pnpm-lock.yaml" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/pnpm-lock.yaml" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet pnpm-lock.yaml"
  [[ -f "${BEDOLAGA_CABINET_DIR}/npm-shrinkwrap.json" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/npm-shrinkwrap.json" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet npm-shrinkwrap.json"
  [[ -f "${BEDOLAGA_CABINET_DIR}/ecosystem.config.js" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/ecosystem.config.js" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet ecosystem.config.js"
  [[ -f "${BEDOLAGA_CABINET_DIR}/ecosystem.config.cjs" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/ecosystem.config.cjs" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet ecosystem.config.cjs"
  [[ -f "${BEDOLAGA_CABINET_DIR}/nginx.conf" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/nginx.conf" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet nginx.conf"
  [[ -d "${BEDOLAGA_CABINET_DIR}/dist" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/dist" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet dist"
  [[ -d "${BEDOLAGA_CABINET_DIR}/public" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/public" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet public"
  add_backup_item "Bedolaga cabinet ENV (.env)" "$WORKDIR/payload/bedolaga/cabinet/.env"
  add_backup_item "Bedolaga cabinet compose (docker-compose.yml)" "$WORKDIR/payload/bedolaga/cabinet/docker-compose.yml"
  add_backup_item "Bedolaga cabinet npm metadata (package.json)" "$WORKDIR/payload/bedolaga/cabinet/package.json"
  add_backup_item "Bedolaga cabinet dist (dist)" "$WORKDIR/payload/bedolaga/cabinet/dist"
fi

cat > "$WORKDIR/payload/backup-info.txt" <<INFO
timestamp_utc=${TIMESTAMP}
host=${HOSTNAME_FQDN}
postgres_db=${POSTGRES_DB}
postgres_user=${POSTGRES_USER}
bedolaga_postgres_db=${BEDOLAGA_POSTGRES_DB}
bedolaga_postgres_user=${BEDOLAGA_POSTGRES_USER}
bedolaga_stack_profile=${BEDOLAGA_STACK_PROFILE_RESOLVED}
bedolaga_db_dump_profile=${BEDOLAGA_DB_DUMP_PROFILE}
bedolaga_bot_repo_origin=${BEDOLAGA_BOT_REPO_ORIGIN}
bedolaga_cabinet_repo_origin=${BEDOLAGA_CABINET_REPO_ORIGIN}
bedolaga_db_container=${BEDOLAGA_DB_CONTAINER}
bedolaga_redis_container=${BEDOLAGA_REDIS_CONTAINER}
remnawave_dir=${REMNAWAVE_DIR}
bedolaga_bot_dir=${BEDOLAGA_BOT_DIR}
bedolaga_cabinet_dir=${BEDOLAGA_CABINET_DIR}
remnawave_image=$(docker inspect remnawave --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
remnawave_caddy_image=$(docker inspect remnawave-caddy --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
bedolaga_bot_image=$(docker inspect remnawave_bot --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
bedolaga_db_image=$(docker inspect "$BEDOLAGA_DB_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
bedolaga_redis_image=$(docker inspect "$BEDOLAGA_REDIS_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
bedolaga_cabinet_image=$(docker inspect cabinet_frontend --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
panel_version=${PANEL_VERSION}
subscription_version=${SUBSCRIPTION_VERSION}
bedolaga_bot_version=${BEDOLAGA_BOT_VERSION}
bedolaga_cabinet_version=${BEDOLAGA_CABINET_VERSION}
bedolaga_logs_strategy=${BEDOLAGA_LOGS_STRATEGY}
bedolaga_logs_max_files=${BEDOLAGA_LOGS_MAX_FILES}
bedolaga_logs_max_file_bytes=${BEDOLAGA_LOGS_MAX_FILE_BYTES}
backup_include=${BACKUP_INCLUDE}
INFO

{
  echo "backup_contents:"
  printf '%s\n' "${BACKUP_ITEMS[@]}"
} > "$WORKDIR/payload/backup-manifest.txt"

log "Упаковываю архив"
rm -f "$ARCHIVE_TMP_PATH" "${ARCHIVE_TMP_PATH}.gpg"
tar -C "$WORKDIR/payload" -czf "$ARCHIVE_TMP_PATH" . || fail "ошибка упаковки архива"

if [[ "$BACKUP_ENCRYPT" == "1" ]]; then
  [[ -n "${BACKUP_PASSWORD:-}" ]] || fail "$(t "включено шифрование, но не задан BACKUP_PASSWORD" "encryption is enabled but BACKUP_PASSWORD is not set")"
  log "$(t "Шифрую архив (GPG symmetric)" "Encrypting archive (GPG symmetric)")"
  gpg --batch --yes --pinentry-mode loopback --passphrase "$BACKUP_PASSWORD" \
    --cipher-algo AES256 --symmetric --output "${ARCHIVE_TMP_PATH}.gpg" "$ARCHIVE_TMP_PATH" \
    || fail "$(t "ошибка шифрования архива" "archive encryption failed")"
  rm -f "$ARCHIVE_TMP_PATH"
  mv -f "${ARCHIVE_TMP_PATH}.gpg" "${ARCHIVE_PATH}.gpg"
  ARCHIVE_PATH="${ARCHIVE_PATH}.gpg"
else
  mv -f "$ARCHIVE_TMP_PATH" "$ARCHIVE_PATH"
fi

create_checksum_file "$ARCHIVE_PATH"

ARCHIVE_SIZE_BYTES="$(stat -c '%s' "$ARCHIVE_PATH")"
ARCHIVE_SIZE_HUMAN="$(du -h "$ARCHIVE_PATH" | awk '{print $1}')"

log "Удаляю старые бэкапы (>${KEEP_DAYS} дней)"
if ! find "$BACKUP_ROOT" -type f \( -name 'pb-*.tar.gz' -o -name 'pb-*.tar.gz.gpg' -o -name 'pb-*.tar.gz.sha256' -o -name 'pb-*.tar.gz.gpg.sha256' -o -name 'pb-*.tar.gz.part.*' -o -name 'pb-*.tar.gz.gpg.part.*' -o -name 'panel-backup-*.tar.gz' -o -name 'panel-backup-*.tar.gz.gpg' -o -name 'panel-backup-*.tar.gz.sha256' -o -name 'panel-backup-*.tar.gz.gpg.sha256' -o -name 'panel-backup-*.tar.gz.part.*' -o -name 'panel-backup-*.tar.gz.gpg.part.*' \) -mtime +"$KEEP_DAYS" -delete; then
  log "$(t "Предупреждение: не удалось удалить часть старых backup-файлов" "Warning: failed to remove some old backup files")"
fi

if (( TELEGRAM_UPLOAD_ENABLED == 0 )); then
  log "$(t "Telegram не настроен, пропускаю отправку архива. Локальный backup создан:" "Telegram is not configured, skipping archive upload. Local backup created:") ${ARCHIVE_PATH}"
elif (( ARCHIVE_SIZE_BYTES <= TG_SINGLE_LIMIT_BYTES )); then
  log "Отправляю архив одним файлом в Telegram"
  if ! send_telegram_file "$ARCHIVE_PATH" "$(build_caption "$(basename "$ARCHIVE_PATH")")" "$(backup_scope_profile)"; then
    if [[ -n "${TELEGRAM_SEND_ERROR_HINT:-}" ]]; then
      fail "$(t "не удалось отправить архив в Telegram" "failed to send archive to Telegram"): ${TELEGRAM_SEND_ERROR_HINT}${TELEGRAM_SEND_ERROR_DESC:+ (${TELEGRAM_SEND_ERROR_DESC})}"
    fi
    fail "не удалось отправить архив в Telegram"
  fi
else
  log "Архив большой, режу на части по ${MAX_TG_PART_SIZE}"
  split -b "$MAX_TG_PART_SIZE" -d -a 3 "$ARCHIVE_PATH" "${ARCHIVE_PATH}.part."
  for part in "${ARCHIVE_PATH}.part."*; do
    if ! send_telegram_file "$part" "$(build_caption "$(basename "$part")")" "$(backup_scope_profile)"; then
      if [[ -n "${TELEGRAM_SEND_ERROR_HINT:-}" ]]; then
        fail "$(t "не удалось отправить часть" "failed to send part") $(basename "$part"): ${TELEGRAM_SEND_ERROR_HINT}${TELEGRAM_SEND_ERROR_DESC:+ (${TELEGRAM_SEND_ERROR_DESC})}"
      fi
      fail "не удалось отправить часть $(basename "$part")"
    fi
  done
fi

if (( TELEGRAM_UPLOAD_ENABLED == 1 )) && [[ -n "${CHECKSUM_PATH:-}" && -f "$CHECKSUM_PATH" ]]; then
  log "$(t "Отправляю SHA256 checksum в Telegram" "Sending SHA256 checksum to Telegram")"
  if ! send_telegram_file "$CHECKSUM_PATH" "$(build_checksum_caption "$(basename "$CHECKSUM_PATH")")" "$(backup_scope_profile)"; then
    log "$(t "Предупреждение: архив отправлен, но checksum не удалось отправить в Telegram" "Warning: archive was sent, but checksum upload to Telegram failed")"
  fi
fi

log "Бэкап и отправка завершены: ${ARCHIVE_PATH} (${ARCHIVE_SIZE_HUMAN})"
