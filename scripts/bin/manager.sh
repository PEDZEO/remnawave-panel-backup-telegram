#!/usr/bin/env bash
# update: main entrypoint for interactive and non-interactive manager modes.
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main}"
RAW_BASE_RESOLVED="$RAW_BASE"
REPO_API="${REPO_API:-https://api.github.com/repos/PEDZEO/remnawave-panel-backup-telegram/commits/main}"
MODE_SET="${MODE+x}"
MODE="${MODE:-install}"
INTERACTIVE="${INTERACTIVE:-auto}"
UI_LANG="${UI_LANG:-auto}"
BACKUP_LANG="${BACKUP_LANG:-}"
BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-}"
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"
BACKUP_INCLUDE="${BACKUP_INCLUDE:-}"
BACKUP_FILE="${BACKUP_FILE:-}"
BACKUP_URL="${BACKUP_URL:-}"
RESTORE_ONLY="${RESTORE_ONLY:-all}"
RESTORE_DRY_RUN="${RESTORE_DRY_RUN:-0}"
RESTORE_NO_RESTART="${RESTORE_NO_RESTART:-0}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ADMIN_ID="${TELEGRAM_ADMIN_ID:-}"
TELEGRAM_THREAD_ID="${TELEGRAM_THREAD_ID:-}"
REMNAWAVE_DIR="${REMNAWAVE_DIR:-}"
BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-0}"
TMP_DIR="$(mktemp -d /tmp/panel-backup-install.XXXXXX)"
SUDO=""
COLOR=0
UI_ACTIVE=0
APP_VERSION="1.1.1"
CLR_RESET=""
CLR_TITLE=""
CLR_ACCENT=""
CLR_MUTED=""
CLR_OK=""
CLR_WARN=""
CLR_DANGER=""

cleanup() {
  if [[ "$UI_ACTIVE" == "1" ]]; then
    tput cnorm >/dev/null 2>&1 || true
    tput rmcup >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

usage() {
  cat <<USAGE
Unified installer/manager for panel backup system.

Modes:
  MODE=install   install/update scripts, env and timer (default)
  MODE=restore   restore backup (all or selected components)
  MODE=backup    run backup now
  MODE=status    show install/timer/backup status

INTERACTIVE:
  INTERACTIVE=auto  show menu in terminal if MODE is not set explicitly (default)
  INTERACTIVE=1     force interactive menu
  INTERACTIVE=0     disable menu, run selected MODE directly

UI_LANG:
  UI_LANG=auto      prompt language in interactive menu (default)
  UI_LANG=ru        Russian
  UI_LANG=en|eu     English

Schedule:
  BACKUP_ON_CALENDAR='*-*-* 03:40:00 UTC'  systemd OnCalendar expression

Examples:
  bash <(curl -fsSL ${RAW_BASE}/install.sh)

  TELEGRAM_BOT_TOKEN='token' TELEGRAM_ADMIN_ID='123' \
  TELEGRAM_THREAD_ID='42' MODE=install \
  bash <(curl -fsSL ${RAW_BASE}/install.sh)

  MODE=restore BACKUP_FILE='/var/backups/panel/panel-backup-xxx.tar.gz' \
  bash <(curl -fsSL ${RAW_BASE}/install.sh)

  MODE=restore BACKUP_URL='https://example.com/panel-backup.tar.gz' \
  RESTORE_ONLY='db,configs' RESTORE_DRY_RUN=1 \
  bash <(curl -fsSL ${RAW_BASE}/install.sh)
USAGE
}

if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "sudo not found. Run as root or install sudo." >&2
    exit 1
  fi
fi

setup_colors() {
  if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    COLOR=1
    CLR_RESET="$(printf '\033[0m')"
    CLR_TITLE="$(printf '\033[1;36m')"
    CLR_ACCENT="$(printf '\033[1;34m')"
    CLR_MUTED="$(printf '\033[0;37m')"
    CLR_OK="$(printf '\033[1;32m')"
    CLR_WARN="$(printf '\033[1;33m')"
    CLR_DANGER="$(printf '\033[1;31m')"
  fi
}

paint() {
  local color="$1"
  shift
  if [[ "$COLOR" == "1" ]]; then
    printf "%b%s%b\n" "$color" "$*" "$CLR_RESET"
  else
    printf "%s\n" "$*"
  fi
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get"
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
    return 0
  fi
  if command -v yum >/dev/null 2>&1; then
    echo "yum"
    return 0
  fi
  if command -v apk >/dev/null 2>&1; then
    echo "apk"
    return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    echo "pacman"
    return 0
  fi
  echo ""
}

install_package() {
  local pkg="$1"
  local pm=""
  pm="$(detect_package_manager)"
  [[ -n "$pm" ]] || return 1

  case "$pm" in
    apt-get) $SUDO apt-get update -y && $SUDO apt-get install -y "$pkg" ;;
    dnf) $SUDO dnf install -y "$pkg" ;;
    yum) $SUDO yum install -y "$pkg" ;;
    apk) $SUDO apk add --no-cache "$pkg" ;;
    pacman) $SUDO pacman -Sy --noconfirm "$pkg" ;;
    *) return 1 ;;
  esac
}

command_package_name() {
  local cmd="$1"
  case "$cmd" in
    curl) echo "curl" ;;
    tar) echo "tar" ;;
    systemctl) echo "systemd" ;;
    install|mktemp|chmod|chown) echo "coreutils" ;;
    awk) echo "gawk" ;;
    sed) echo "sed" ;;
    grep) echo "grep" ;;
    *) echo "" ;;
  esac
}

preflight_install_environment() {
  local required=()
  local missing=()
  local cmd=""
  local pkg=""
  local failed=()

  required=(curl tar systemctl install mktemp chmod chown awk sed grep)
  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    paint "$CLR_OK" "[0/5] $(tr_text "Preflight: окружение готово" "Preflight: environment is ready")"
    return 0
  fi

  paint "$CLR_WARN" "[0/5] $(tr_text "Preflight: отсутствуют команды:" "Preflight: missing commands:") ${missing[*]}"
  if [[ "$AUTO_INSTALL_DEPS" != "1" ]]; then
    paint "$CLR_WARN" "$(tr_text "Установите их вручную или запустите с AUTO_INSTALL_DEPS=1." "Install them manually or run with AUTO_INSTALL_DEPS=1.")"
    return 1
  fi

  for cmd in "${missing[@]}"; do
    pkg="$(command_package_name "$cmd")"
    if [[ -z "$pkg" ]]; then
      failed+=("$cmd")
      continue
    fi
    paint "$CLR_ACCENT" "$(tr_text "Пробую установить пакет для" "Trying to install package for"): $cmd -> $pkg"
    install_package "$pkg" >/dev/null 2>&1 || true
    command -v "$cmd" >/dev/null 2>&1 || failed+=("$cmd")
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось подготовить зависимости:" "Failed to prepare dependencies:") ${failed[*]}"
    return 1
  fi

  paint "$CLR_OK" "$(tr_text "Зависимости установлены автоматически." "Dependencies were installed automatically.")"
  return 0
}

container_state() {
  local name="$1"
  local state=""
  state="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    echo "$(tr_text "не найден" "not found")"
  else
    case "$state" in
      running) echo "$(tr_text "работает" "running")" ;;
      exited) echo "$(tr_text "остановлен" "stopped")" ;;
      restarting) echo "$(tr_text "перезапуск" "restarting")" ;;
      created) echo "$(tr_text "создан" "created")" ;;
      paused) echo "$(tr_text "на паузе" "paused")" ;;
      dead) echo "$(tr_text "ошибка" "dead")" ;;
      *) echo "$state" ;;
    esac
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

  # Если tag слишком грубый (например "2"), а env содержит более точную версию
  # (например "2.5.5"), показываем более информативное значение.
  if [[ -n "$env_version" ]]; then
    if [[ -z "$version" ]]; then
      version="$env_version"
    elif [[ "$version" =~ ^[0-9]+$ ]] && [[ "$env_version" =~ [.-] ]]; then
      version="$env_version"
    fi
  fi

  if [[ -n "$version" ]]; then
    echo "$version"
    return 0
  fi

  # Fallback for compose-managed apps (e.g. cabinet_frontend):
  # read semantic version from package.json in compose working_dir.
  compose_workdir="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$name" 2>/dev/null || true)"
  if [[ -n "$compose_workdir" ]]; then
    package_json="${compose_workdir}/package.json"
    if [[ -f "$package_json" ]]; then
      package_version="$(awk -F'"' '/"version"[[:space:]]*:[[:space:]]*"/ { print $4; exit }' "$package_json" 2>/dev/null || true)"
      if [[ -n "$package_version" ]]; then
        echo "$package_version"
        return 0
      fi
    fi
    if [[ -d "${compose_workdir}/.git" ]]; then
      revision="$(git -C "$compose_workdir" rev-parse --short=12 HEAD 2>/dev/null || true)"
      if [[ -n "$revision" ]]; then
        echo "sha-${revision}"
        return 0
      fi
    fi
  fi

  if [[ -n "$image_id" ]]; then
    image_id="${image_id#sha256:}"
    echo "sha-${image_id:0:12}"
    return 0
  fi

  if [[ -z "$image_ref" ]]; then
    echo "unknown"
    return 0
  fi

  tail="${image_ref##*/}"
  if [[ "$tail" == *:* ]]; then
    echo "${tail##*:}"
    return 0
  fi
  if [[ "$tail" == *@* ]]; then
    echo "${tail##*@}"
    return 0
  fi
  echo "$tail"
}

memory_usage_label() {
  local total_kb=0
  local avail_kb=0
  local used_kb=0
  local used_mb=0
  local total_mb=0
  local percent=0

  total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$total_kb" =~ ^[0-9]+$ && "$avail_kb" =~ ^[0-9]+$ && "$total_kb" -gt 0 ]]; then
    used_kb=$((total_kb - avail_kb))
    used_mb=$((used_kb / 1024))
    total_mb=$((total_kb / 1024))
    percent=$((used_kb * 100 / total_kb))
    echo "${used_mb}MB / ${total_mb}MB (${percent}%)"
    return 0
  fi
  echo "n/a"
}

memory_usage_percent() {
  local total_kb=0
  local avail_kb=0
  local used_kb=0
  total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$total_kb" =~ ^[0-9]+$ && "$avail_kb" =~ ^[0-9]+$ && "$total_kb" -gt 0 ]]; then
    used_kb=$((total_kb - avail_kb))
    echo $((used_kb * 100 / total_kb))
    return 0
  fi
  echo "-1"
}

disk_usage_label() {
  local line=""
  local used=""
  local total=""
  local percent=""
  line="$(df -h / 2>/dev/null | awk 'NR==2 {print $3" "$2" "$5}' || true)"
  if [[ -z "$line" ]]; then
    echo "n/a"
    return 0
  fi
  used="$(echo "$line" | awk '{print $1}')"
  total="$(echo "$line" | awk '{print $2}')"
  percent="$(echo "$line" | awk '{print $3}')"
  echo "$(tr_text "${used} из ${total} (${percent})" "${used} of ${total} (${percent})")"
}

disk_usage_percent() {
  local raw=""
  raw="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}' || true)"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo "-1"
  fi
}

metric_color_ram() {
  local percent="$1"
  if [[ "$percent" =~ ^[0-9]+$ ]]; then
    if (( percent >= 90 )); then
      echo "$CLR_DANGER"
      return 0
    fi
    if (( percent >= 75 )); then
      echo "$CLR_WARN"
      return 0
    fi
    echo "$CLR_OK"
    return 0
  fi
  echo "$CLR_MUTED"
}

metric_color_disk() {
  local percent="$1"
  if [[ "$percent" =~ ^[0-9]+$ ]]; then
    if (( percent >= 85 )); then
      echo "$CLR_DANGER"
      return 0
    fi
    if (( percent >= 70 )); then
      echo "$CLR_WARN"
      return 0
    fi
    echo "$CLR_OK"
    return 0
  fi
  echo "$CLR_MUTED"
}

state_color() {
  local state="$1"
  case "$state" in
    running|active) echo "$CLR_OK" ;;
    restarting|created|paused) echo "$CLR_WARN" ;;
    *) echo "$CLR_DANGER" ;;
  esac
}

fetch() {
  local src="$1"
  local dst="$2"
  local url="${RAW_BASE_RESOLVED}/${src}"
  local sep="?"

  if [[ "$url" == *\?* ]]; then
    sep="&"
  fi

  curl -fsSL "${url}${sep}v=$(date +%s)" -o "$dst"
}

resolve_raw_base() {
  local sha=""
  local candidate=""

  sha="$(curl -fsSL "$REPO_API" 2>/dev/null | sed -n 's/.*"sha":[[:space:]]*"\([a-f0-9]\{40\}\)".*/\1/p' | head -n1 || true)"
  if [[ -z "$sha" ]]; then
    RAW_BASE_RESOLVED="$RAW_BASE"
    return 0
  fi

  candidate="https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/${sha}"
  RAW_BASE_RESOLVED="$candidate"
}

resolve_raw_base


load_manager_module() {
  local module_path="$1"
  local local_path=""
  local fetched_path=""
  local manager_dir=""
  local repo_root=""

  manager_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${manager_dir}/../.." && pwd)"
  local_path="${repo_root}/${module_path}"

  if [[ -f "$local_path" ]]; then
    # shellcheck source=/dev/null
    source "$local_path"
    return 0
  fi

  fetched_path="${TMP_DIR}/module__${module_path//\//__}"
  fetch "$module_path" "$fetched_path"
  # shellcheck source=/dev/null
  source "$fetched_path"
}

load_manager_modules() {
  load_manager_module "scripts/runtime/manager_ui_core.sh"
  load_manager_module "scripts/install/pipeline.sh"
  load_manager_module "scripts/runtime/operations.sh"
  load_manager_module "scripts/runtime/panel_node.sh"
  load_manager_module "scripts/runtime/panel_node_network.sh"
  load_manager_module "scripts/runtime/bedolaga_caddy.sh"
  load_manager_module "scripts/runtime/bedolaga_stack.sh"
  load_manager_module "scripts/runtime/ui_header.sh"
  load_manager_module "scripts/menu/restore_wizard.sh"
  load_manager_module "scripts/menu/setup_section.sh"
  load_manager_module "scripts/menu/interactive.sh"
}

load_manager_modules

if is_interactive; then
  interactive_menu
  exit 0
fi

case "$MODE" in
  install)
    run_install_pipeline
    echo
    echo "$(tr_text "Запустить backup сейчас:" "Run backup now:")"
    echo "  sudo /usr/local/bin/panel-backup.sh"
    echo "$(tr_text "Запустить restore:" "Run restore:")"
    echo "  MODE=restore BACKUP_FILE='/var/backups/panel/<archive>.tar.gz' bash <(curl -fsSL ${RAW_BASE}/install.sh)"
    ;;
  restore)
    if [[ ! -x /usr/local/bin/panel-restore.sh ]]; then
      preflight_install_environment
      install_files
      write_env
      $SUDO systemctl daemon-reload
    fi
    run_restore
    ;;
  backup)
    run_backup_now
    ;;
  status)
    show_status
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown MODE=$MODE" >&2
    usage
    exit 1
    ;;
esac
