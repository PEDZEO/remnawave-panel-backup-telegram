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
BACKUP_ENV_PATH="${BACKUP_ENV_PATH:-/etc/panel-backup.env}"
BACKUP_LANG="${BACKUP_LANG:-ru}"
BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-0}"
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"
BACKUP_INCLUDE="${BACKUP_INCLUDE:-all}"
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
LOG_TAG="panel-backup"
LOCK_FILE="${LOCK_FILE:-/var/lock/panel-backup.lock}"
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
      bedolaga-configs)
        WANT_BEDOLAGA_BOT=1
        WANT_BEDOLAGA_CABINET=1
        ;;
      bedolaga-db) WANT_BEDOLAGA_DB=1 ;;
      bedolaga-redis) WANT_BEDOLAGA_REDIS=1 ;;
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
  (( WANT_DB == 1 )) && out="${out}db,"
  (( WANT_REDIS == 1 )) && out="${out}redis,"
  (( WANT_ENV == 1 )) && out="${out}env,"
  (( WANT_COMPOSE == 1 )) && out="${out}compose,"
  (( WANT_CADDY == 1 )) && out="${out}caddy,"
  (( WANT_SUBSCRIPTION == 1 )) && out="${out}subscription,"
  (( WANT_BEDOLAGA_DB == 1 )) && out="${out}bedolaga-db,"
  (( WANT_BEDOLAGA_REDIS == 1 )) && out="${out}bedolaga-redis,"
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

  for guessed in "${REMNAWAVE_DIR}" "/opt/remnawave" "/srv/remnawave" "/root/remnawave" "/home/remnawave"; do
    [[ -n "$guessed" ]] || continue
    if is_remnawave_panel_dir "$guessed"; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(docker inspect remnawave --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
  if [[ -n "$guessed" ]] && is_remnawave_panel_dir "$guessed"; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /opt /srv /root /home -maxdepth 4 -type f -name '.env' 2>/dev/null | while read -r f; do d="$(dirname "$f")"; is_remnawave_panel_dir "$d" || continue; echo "$d"; break; done)"
  [[ -n "$guessed" ]] && echo "$guessed"
}

detect_bedolaga_bot_dir() {
  local guessed=""
  for guessed in "${BEDOLAGA_BOT_DIR}" "/root/remnawave-bedolaga-telegram-bot" "/opt/remnawave-bedolaga-telegram-bot"; do
    [[ -n "$guessed" ]] || continue
    if [[ -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(docker inspect remnawave_bot --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
  if [[ -n "$guessed" && -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home -maxdepth 5 -type d -name 'remnawave-bedolaga-telegram-bot' 2>/dev/null | while read -r d; do [[ -f "$d/.env" && -f "$d/docker-compose.yml" ]] || continue; echo "$d"; break; done)"
  [[ -n "$guessed" ]] && echo "$guessed"
}

detect_bedolaga_cabinet_dir() {
  local guessed=""
  for guessed in "${BEDOLAGA_CABINET_DIR}" "/root/bedolaga-cabinet" "/root/cabinet-frontend" "/opt/bedolaga-cabinet"; do
    [[ -n "$guessed" ]] || continue
    if [[ -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
      echo "$guessed"
      return 0
    fi
  done

  guessed="$(docker inspect cabinet_frontend --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null || true)"
  if [[ -n "$guessed" && -f "$guessed/.env" && -f "$guessed/docker-compose.yml" ]]; then
    echo "$guessed"
    return 0
  fi

  guessed="$(find /home -maxdepth 5 -type d \( -name 'cabinet-frontend' -o -name 'bedolaga-cabinet' \) 2>/dev/null | while read -r d; do [[ -f "$d/.env" && -f "$d/docker-compose.yml" ]] || continue; echo "$d"; break; done)"
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
  local version_from_tag=""
  local revision=""
  local env_version=""
  local compose_workdir=""
  local package_json=""
  local package_version=""

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
      version_from_tag="${tail##*:}"
      if [[ "$version_from_tag" != "latest" ]]; then
        version="$version_from_tag"
      fi
    fi
  fi

  env_version="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null | awk -F= '
    $1=="__RW_METADATA_VERSION" {print $2; exit}
    $1=="REMNAWAVE_VERSION" {print $2; exit}
    $1=="SUBSCRIPTION_VERSION" {print $2; exit}
    $1=="APP_VERSION" {print $2; exit}
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

  compose_workdir="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$name" 2>/dev/null || true)"
  if [[ -n "$compose_workdir" ]]; then
    package_json="${compose_workdir}/package.json"
    if [[ -f "$package_json" ]]; then
      package_version="$(awk -F'"' '/"version"[[:space:]]*:[[:space:]]*"/ { print $4; exit }' "$package_json" 2>/dev/null || true)"
      if [[ -n "$package_version" ]]; then
        printf '%s' "$package_version"
        return 0
      fi
    fi
    if [[ -d "${compose_workdir}/.git" ]]; then
      revision="$(git -C "$compose_workdir" rev-parse --short=12 HEAD 2>/dev/null || true)"
      if [[ -n "$revision" ]]; then
        printf '%s' "sha-${revision}"
        return 0
      fi
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

send_telegram_text() {
  local text="$1"
  local profile="${2:-$(backup_scope_profile)}"
  local thread_id=""
  local thread_args=()
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_ADMIN_ID:-}" ]]; then
    return 0
  fi

  thread_id="$(resolve_telegram_thread_id "$profile")"
  if [[ -n "$thread_id" ]]; then
    thread_args+=(-d "message_thread_id=${thread_id}")
  fi
  if ! curl -sS --max-time 20 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_ADMIN_ID}" \
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
  local fallback_caption=""
  local response
  local thread_id=""
  local thread_args=()

  thread_id="$(resolve_telegram_thread_id "$profile")"
  if [[ -n "$thread_id" ]]; then
    thread_args+=(-F "message_thread_id=${thread_id}")
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

preflight_checks() {
  local need_bytes=0
  local free_bytes=0

  ensure_dependencies
  (( WANT_DB == 1 )) && check_container_present remnawave-db
  (( WANT_REDIS == 1 )) && check_container_present remnawave-redis
  (( WANT_BEDOLAGA_DB == 1 )) && check_container_present remnawave_bot_db
  (( WANT_BEDOLAGA_REDIS == 1 )) && check_container_present remnawave_bot_redis

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

normalize_env_file_format
if [[ -f "$BACKUP_ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$BACKUP_ENV_PATH"
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

[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || fail "не найден TELEGRAM_BOT_TOKEN в ${BACKUP_ENV_PATH}"
[[ -n "${TELEGRAM_ADMIN_ID:-}" ]] || fail "не найден TELEGRAM_ADMIN_ID в ${BACKUP_ENV_PATH}"

if (( WANT_DB == 1 || WANT_ENV == 1 || WANT_COMPOSE == 1 || WANT_CADDY == 1 || WANT_SUBSCRIPTION == 1 )); then
  [[ -d "$REMNAWAVE_DIR" ]] || fail "не найдена директория ${REMNAWAVE_DIR}"
fi
if (( WANT_DB == 1 || WANT_ENV == 1 )); then
  [[ -f "${REMNAWAVE_DIR}/.env" ]] || fail "не найден ${REMNAWAVE_DIR}/.env"
fi
if (( WANT_BEDOLAGA_BOT == 1 || WANT_BEDOLAGA_DB == 1 )); then
  [[ -d "$BEDOLAGA_BOT_DIR" ]] || fail "не найдена директория ${BEDOLAGA_BOT_DIR}"
  [[ -f "${BEDOLAGA_BOT_DIR}/.env" ]] || fail "не найден ${BEDOLAGA_BOT_DIR}/.env"
fi
if (( WANT_BEDOLAGA_CABINET == 1 )); then
  [[ -d "$BEDOLAGA_CABINET_DIR" ]] || fail "не найдена директория ${BEDOLAGA_CABINET_DIR}"
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
  if ! docker exec remnawave-redis sh -lc 'valkey-cli save >/dev/null 2>&1 || redis-cli save >/dev/null 2>&1'; then
    log "$(t "Предупреждение: команда сохранения Redis вернула ошибку, пробую забрать существующий dump.rdb" "Warning: Redis save command failed, trying to copy existing dump.rdb")"
  fi
  docker cp remnawave-redis:/data/dump.rdb "$WORKDIR/payload/remnawave-redis.rdb" 2>/dev/null \
    || fail "$(t "не удалось получить Redis dump" "failed to get Redis dump")"
  [[ -f "$WORKDIR/payload/remnawave-redis.rdb" ]] \
    || fail "$(t "Redis dump не найден после копирования" "Redis dump not found after copy")"
  BACKUP_ITEMS+=("- Redis dump: включено ($(du -h "$WORKDIR/payload/remnawave-redis.rdb" | awk '{print $1}'))")
fi

if (( WANT_COMPOSE == 1 || WANT_ENV == 1 || WANT_CADDY == 1 || WANT_SUBSCRIPTION == 1 )); then
  log "Копирую конфиги Remnawave"
  (( WANT_COMPOSE == 1 )) && copy_backup_entry "${REMNAWAVE_DIR}/docker-compose.yml" "$WORKDIR/payload/remnawave/" "docker-compose.yml"
  (( WANT_ENV == 1 )) && copy_backup_entry "${REMNAWAVE_DIR}/.env" "$WORKDIR/payload/remnawave/" ".env"
  (( WANT_CADDY == 1 )) && copy_backup_entry "${REMNAWAVE_DIR}/caddy" "$WORKDIR/payload/remnawave/" "caddy"
  (( WANT_SUBSCRIPTION == 1 )) && copy_backup_entry "${REMNAWAVE_DIR}/subscription" "$WORKDIR/payload/remnawave/" "subscription"
  (( WANT_COMPOSE == 1 )) && add_backup_item "Docker Compose (remnawave/docker-compose.yml)" "$WORKDIR/payload/remnawave/docker-compose.yml"
  (( WANT_ENV == 1 )) && add_backup_item "ENV (remnawave/.env)" "$WORKDIR/payload/remnawave/.env"
  (( WANT_CADDY == 1 )) && add_backup_item "Caddy config (remnawave/caddy)" "$WORKDIR/payload/remnawave/caddy"
  (( WANT_SUBSCRIPTION == 1 )) && add_backup_item "Subscription page (remnawave/subscription)" "$WORKDIR/payload/remnawave/subscription"
fi

if (( WANT_BEDOLAGA_DB == 1 )); then
  log "Создаю дамп PostgreSQL Bedolaga (${BEDOLAGA_POSTGRES_DB})"
  docker exec remnawave_bot_db pg_dump -U "$BEDOLAGA_POSTGRES_USER" -d "$BEDOLAGA_POSTGRES_DB" -Fc -Z9 > "$WORKDIR/payload/bedolaga-bot-db.dump" \
    || fail "ошибка pg_dump remnawave_bot_db"
  BACKUP_ITEMS+=("- Bedolaga PostgreSQL dump: включено ($(du -h "$WORKDIR/payload/bedolaga-bot-db.dump" | awk '{print $1}'))")
fi

if (( WANT_BEDOLAGA_REDIS == 1 )); then
  log "Сохраняю Redis dump Bedolaga"
  if ! docker exec remnawave_bot_redis sh -lc 'redis-cli save >/dev/null 2>&1'; then
    log "$(t "Предупреждение: команда сохранения Redis Bedolaga вернула ошибку, пробую забрать существующий dump.rdb" "Warning: Bedolaga Redis save command failed, trying to copy existing dump.rdb")"
  fi
  docker cp remnawave_bot_redis:/data/dump.rdb "$WORKDIR/payload/bedolaga-bot-redis.rdb" 2>/dev/null \
    || fail "$(t "не удалось получить Redis dump Bedolaga" "failed to get Bedolaga Redis dump")"
  [[ -f "$WORKDIR/payload/bedolaga-bot-redis.rdb" ]] \
    || fail "$(t "Redis dump Bedolaga не найден после копирования" "Bedolaga Redis dump not found after copy")"
  BACKUP_ITEMS+=("- Bedolaga Redis dump: включено ($(du -h "$WORKDIR/payload/bedolaga-bot-redis.rdb" | awk '{print $1}'))")
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
  copy_backup_entry "${BEDOLAGA_CABINET_DIR}/docker-compose.yml" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet docker-compose.yml"
  copy_backup_entry "${BEDOLAGA_CABINET_DIR}/.env" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet .env"
  [[ -f "${BEDOLAGA_CABINET_DIR}/docker-compose.override.yml" ]] && copy_backup_entry "${BEDOLAGA_CABINET_DIR}/docker-compose.override.yml" "$WORKDIR/payload/bedolaga/cabinet/" "bedolaga cabinet docker-compose.override.yml"
  add_backup_item "Bedolaga cabinet ENV (.env)" "$WORKDIR/payload/bedolaga/cabinet/.env"
  add_backup_item "Bedolaga cabinet compose (docker-compose.yml)" "$WORKDIR/payload/bedolaga/cabinet/docker-compose.yml"
fi

cat > "$WORKDIR/payload/backup-info.txt" <<INFO
timestamp_utc=${TIMESTAMP}
host=${HOSTNAME_FQDN}
postgres_db=${POSTGRES_DB}
postgres_user=${POSTGRES_USER}
bedolaga_postgres_db=${BEDOLAGA_POSTGRES_DB}
bedolaga_postgres_user=${BEDOLAGA_POSTGRES_USER}
remnawave_dir=${REMNAWAVE_DIR}
bedolaga_bot_dir=${BEDOLAGA_BOT_DIR}
bedolaga_cabinet_dir=${BEDOLAGA_CABINET_DIR}
remnawave_image=$(docker inspect remnawave --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
remnawave_caddy_image=$(docker inspect remnawave-caddy --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
bedolaga_bot_image=$(docker inspect remnawave_bot --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
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
if ! find "$BACKUP_ROOT" -type f \( -name 'pb-*.tar.gz' -o -name 'pb-*.tar.gz.gpg' -o -name 'pb-*.tar.gz.part.*' -o -name 'pb-*.tar.gz.gpg.part.*' -o -name 'panel-backup-*.tar.gz' -o -name 'panel-backup-*.tar.gz.gpg' -o -name 'panel-backup-*.tar.gz.part.*' -o -name 'panel-backup-*.tar.gz.gpg.part.*' \) -mtime +"$KEEP_DAYS" -delete; then
  log "$(t "Предупреждение: не удалось удалить часть старых backup-файлов" "Warning: failed to remove some old backup files")"
fi

if (( ARCHIVE_SIZE_BYTES <= TG_SINGLE_LIMIT_BYTES )); then
  log "Отправляю архив одним файлом в Telegram"
  send_telegram_file "$ARCHIVE_PATH" "$(build_caption "$(basename "$ARCHIVE_PATH")")" "$(backup_scope_profile)" \
    || fail "не удалось отправить архив в Telegram"
else
  log "Архив большой, режу на части по ${MAX_TG_PART_SIZE}"
  split -b "$MAX_TG_PART_SIZE" -d -a 3 "$ARCHIVE_PATH" "${ARCHIVE_PATH}.part."
  for part in "${ARCHIVE_PATH}.part."*; do
    send_telegram_file "$part" "$(build_caption "$(basename "$part")")" "$(backup_scope_profile)" \
      || fail "не удалось отправить часть $(basename "$part")"
  done
fi

log "Бэкап и отправка завершены: ${ARCHIVE_PATH} (${ARCHIVE_SIZE_HUMAN})"
