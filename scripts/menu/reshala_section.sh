#!/usr/bin/env bash
# Optional integration page for the external Reshala toolbox.

RESHALA_REPO_URL="https://github.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga"
RESHALA_INSTALL_URL="https://raw.githubusercontent.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga/main/install.sh"
RESHALA_TARGET_PATH="/opt/reshala/reshala.sh"
RESHALA_WRAPPER_PATH="/usr/local/bin/reshala"

reshala_command_path() {
  if [[ -x "$RESHALA_WRAPPER_PATH" ]]; then
    printf '%s' "$RESHALA_WRAPPER_PATH"
    return 0
  fi
  if command -v reshala >/dev/null 2>&1; then
    command -v reshala
    return 0
  fi
  if [[ -x "$RESHALA_TARGET_PATH" ]]; then
    printf '%s' "$RESHALA_TARGET_PATH"
    return 0
  fi
  return 1
}

reshala_version_label() {
  local version=""

  if [[ -f "$RESHALA_TARGET_PATH" ]]; then
    version="$(grep -E '^readonly VERSION=' "$RESHALA_TARGET_PATH" 2>/dev/null | head -n1 | sed -E 's/^readonly VERSION="?([^"]+)"?/\1/' || true)"
  fi
  printf '%s' "${version:-unknown}"
}

show_reshala_feature_map() {
  draw_subheader "$(tr_text "Решала: карта функций" "Reshala: feature map")"
  paint "$CLR_MUTED" "$(tr_text "Это внешний toolbox. В этом проекте нет LICENSE, поэтому код не вшит в наш репозиторий." "This is an external toolbox. That project has no LICENSE, so its code is not vendored here.")"
  print_separator
  paint "$CLR_TITLE" "$(tr_text "Что есть внутри Reshala" "What Reshala includes")"
  paint "$CLR_MUTED" "  - Skynet: $(tr_text "управление несколькими серверами по SSH, команды на флоте, ключи" "multi-server SSH fleet management, fleet commands, keys")"
  paint "$CLR_MUTED" "  - $(tr_text "Безопасность: UFW, Fail2Ban, kernel hardening, SSH-порты, whitelist, rkhunter, backup правил" "Security: UFW, Fail2Ban, kernel hardening, SSH ports, whitelist, rkhunter, rule backups")"
  paint "$CLR_MUTED" "  - $(tr_text "Сервис: apt update/upgrade, BBR/CAKE, IPv6, speedtest, профиль dashboard" "Maintenance: apt update/upgrade, BBR/CAKE, IPv6, speedtest, dashboard profile")"
  paint "$CLR_MUTED" "  - $(tr_text "Диагностика: логи, Docker-логи, состояние компонентов" "Diagnostics: logs, Docker logs, component state")"
  paint "$CLR_MUTED" "  - $(tr_text "Очистка: Docker prune, APT cache, journal, /tmp, snap, анализатор диска, logrotate" "Cleanup: Docker prune, APT cache, journal, /tmp, snap, disk analyzer, logrotate")"
  paint "$CLR_MUTED" "  - $(tr_text "Шейпер трафика: eBPF/EDT лимиты скорости, whitelist, сервис systemd" "Traffic shaper: eBPF/EDT speed limits, whitelist, systemd service")"
  paint "$CLR_MUTED" "  - $(tr_text "VPN Gateway: маскировщик лендинга Bedolaga, nginx edge, сертификаты, тесты" "VPN Gateway: Bedolaga landing masker, nginx edge, certificates, tests")"
  paint "$CLR_MUTED" "  - $(tr_text "Автообновлятор сервисов и виджеты dashboard" "Service auto-updater and dashboard widgets")"
  print_separator
  paint "$CLR_WARN" "$(tr_text "Важно: модули Remnawave и Bedolaga в Reshala сейчас помечены как 'в разработке'. Для них лучше использовать наши текущие разделы." "Important: Reshala's Remnawave and Bedolaga modules are currently marked 'in development'. Use this manager's native sections for them.")"
  wait_for_enter
}

show_reshala_install_status() {
  local cmd_path=""
  local installed_state=""

  if cmd_path="$(reshala_command_path)"; then
    installed_state="$(tr_text "установлена" "installed")"
  else
    cmd_path="$(tr_text "не найден" "not found")"
    installed_state="$(tr_text "не установлена" "not installed")"
  fi

  draw_subheader "$(tr_text "Решала: статус" "Reshala: status")"
  paint "$CLR_MUTED" "  $(tr_text "Состояние:" "State:") ${installed_state}"
  paint "$CLR_MUTED" "  $(tr_text "Команда:" "Command:") ${cmd_path}"
  paint "$CLR_MUTED" "  $(tr_text "Основной файл:" "Main file:") ${RESHALA_TARGET_PATH}"
  paint "$CLR_MUTED" "  $(tr_text "Версия:" "Version:") $(reshala_version_label)"
  paint "$CLR_MUTED" "  $(tr_text "Репозиторий:" "Repository:") ${RESHALA_REPO_URL}"
  wait_for_enter
}

run_reshala_install_update() {
  local installer=""
  local answer_rc=0

  draw_subheader "$(tr_text "Установка/обновление Reshala" "Install/update Reshala")"
  paint "$CLR_WARN" "$(tr_text "Будет скачан и запущен внешний install.sh из репозитория DonMatteoVPN/Reshala-Remnawave-Bedolaga." "This downloads and runs an external install.sh from DonMatteoVPN/Reshala-Remnawave-Bedolaga.")"
  paint "$CLR_MUTED" "$(tr_text "Скрипт может менять /opt/reshala, /usr/local/bin/reshala и системные настройки внутри своей установки." "The script may change /opt/reshala, /usr/local/bin/reshala and its own system setup.")"
  if ! ask_yes_no "$(tr_text "Продолжить установку/обновление Reshala?" "Continue installing/updating Reshala?")" "n"; then
    answer_rc=$?
    [[ "$answer_rc" == "2" ]] && return 0
    paint "$CLR_WARN" "$(tr_text "Отменено." "Cancelled.")"
    wait_for_enter
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    paint "$CLR_DANGER" "curl $(tr_text "не установлен." "is not installed.")"
    wait_for_enter
    return 1
  fi

  installer="${TMP_DIR:-/tmp}/reshala-install.sh"
  if ! curl -fsSL "$RESHALA_INSTALL_URL" -o "$installer"; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось скачать install.sh Reshala." "Failed to download Reshala install.sh.")"
    wait_for_enter
    return 1
  fi

  chmod 700 "$installer" 2>/dev/null || true
  if [[ -n "$SUDO" ]]; then
    $SUDO bash "$installer"
  else
    bash "$installer"
  fi
  wait_for_enter
}

run_reshala_menu() {
  local cmd_path=""
  local answer_rc=0

  if ! cmd_path="$(reshala_command_path)"; then
    paint "$CLR_WARN" "$(tr_text "Reshala не найдена." "Reshala was not found.")"
    if ask_yes_no "$(tr_text "Установить Reshala сейчас?" "Install Reshala now?")" "y"; then
      run_reshala_install_update
      cmd_path="$(reshala_command_path || true)"
    else
      answer_rc=$?
      [[ "$answer_rc" == "2" ]] && return 0
      return 0
    fi
  fi

  if [[ -z "$cmd_path" || ! -x "$cmd_path" ]]; then
    paint "$CLR_DANGER" "$(tr_text "Команда Reshala недоступна после установки." "Reshala command is unavailable after install.")"
    wait_for_enter
    return 1
  fi

  paint "$CLR_MUTED" "$(tr_text "Сейчас откроется внешнее меню Reshala. После выхода вернетесь сюда." "The external Reshala menu will open now. After exiting, you return here.")"
  wait_for_enter
  if [[ -n "$SUDO" ]]; then
    $SUDO "$cmd_path"
  else
    "$cmd_path"
  fi
}

show_reshala_uninstall_help() {
  draw_subheader "$(tr_text "Удаление Reshala" "Remove Reshala")"
  paint "$CLR_WARN" "$(tr_text "Автоматически удалять внешний toolbox из нашего меню не буду: это отдельный проект и у него могут быть свои данные." "This menu will not auto-remove the external toolbox: it is a separate project and may have its own data.")"
  paint "$CLR_MUTED" "$(tr_text "Команды из README Reshala для ручного удаления:" "Commands from Reshala README for manual removal:")"
  print_separator
  paint "$CLR_MUTED" "  rm -f /usr/local/bin/reshala"
  paint "$CLR_MUTED" "  rm -rf /opt/reshala"
  paint "$CLR_MUTED" "  rm -f install.sh"
  print_separator
  paint "$CLR_MUTED" "$(tr_text "Перед удалением проверьте, что там нет нужных конфигов/ключей Skynet." "Before removing, check that it does not contain needed Skynet configs/keys.")"
  wait_for_enter
}

menu_section_reshala_integration() {
  local choice=""

  while true; do
    ui_set_breadcrumb "$(tr_text "Главная / Reshala" "Home / Reshala")"
    draw_subheader "$(tr_text "Раздел: Reshala toolbox" "Section: Reshala toolbox")"
    show_back_hint
    paint "$CLR_MUTED" "$(tr_text "Отдельная страница для внешнего проекта Reshala. Дает доступ ко всему его меню без копирования кода в наш репозиторий." "Separate page for the external Reshala project. Gives access to its full menu without copying its code into this repo.")"
    print_separator
    menu_group "$(tr_text "Информация" "Info")" "$CLR_WARN"
    menu_option "1" "$(tr_text "Карта функций Reshala" "Reshala feature map")"
    menu_group "$(tr_text "Управление" "Management")" "$CLR_OK"
    menu_option "2" "$(tr_text "Установить/обновить Reshala" "Install/update Reshala")"
    menu_option "3" "$(tr_text "Открыть меню Reshala" "Open Reshala menu")"
    menu_group "$(tr_text "Статус" "Status")" "$CLR_ACCENT"
    menu_option "4" "$(tr_text "Проверить статус установки" "Check install status")"
    menu_group "$(tr_text "Удаление" "Removal")" "$CLR_DANGER"
    menu_option "5" "$(tr_text "Показать команды удаления" "Show removal commands")"
    menu_group "$(tr_text "Навигация" "Navigation")" "$CLR_MUTED"
    menu_option "6" "$(tr_text "Назад" "Back")"
    print_separator
    read_menu_choice choice "$(tr_text "Выбор [1-6]: " "Choice [1-6]: ")"
    if is_back_command "$choice"; then
      break
    fi
    case "$choice" in
      1) show_reshala_feature_map ;;
      2) run_reshala_install_update ;;
      3) run_reshala_menu ;;
      4) show_reshala_install_status ;;
      5) show_reshala_uninstall_help ;;
      6) break ;;
      *) paint "$CLR_WARN" "$(tr_text "Некорректный выбор." "Invalid choice.")"; wait_for_enter ;;
    esac
  done
}
