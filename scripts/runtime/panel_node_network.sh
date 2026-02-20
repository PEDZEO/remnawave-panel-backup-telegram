#!/usr/bin/env bash
# RemnaNode network-related flows (Caddy/BBR/IPv6/WARP).

ensure_remnanode_caddy_installed() {
  if command -v caddy >/dev/null 2>&1; then
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "Caddy не найден." "Caddy is not installed.")"
  if ! ask_yes_no "$(tr_text "Установить Caddy сейчас?" "Install Caddy now?")" "y"; then
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    paint "$CLR_ACCENT" "$(tr_text "Устанавливаю Caddy через официальный репозиторий..." "Installing Caddy from official repository...")"
    if ! $SUDO apt-get update -y >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "apt update завершился с ошибкой." "apt update failed.")"
    fi
    if ! $SUDO apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Не удалось установить зависимости Caddy с первой попытки." "Failed to install Caddy prerequisites on first attempt.")"
    fi
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | $SUDO gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    if ! $SUDO apt-get update -y >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Повторный apt update завершился с ошибкой." "Second apt update failed.")"
    fi
    if ! $SUDO apt-get install -y caddy >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Установка Caddy завершилась с ошибкой." "Caddy installation failed.")"
    fi
  else
    paint "$CLR_WARN" "$(tr_text "Автоустановка Caddy поддерживается только на apt-системах. Установите Caddy вручную и повторите." "Automatic Caddy install is supported only on apt-based systems. Install Caddy manually and retry.")"
    return 1
  fi

  if ! command -v caddy >/dev/null 2>&1; then
    paint "$CLR_DANGER" "$(tr_text "Не удалось установить Caddy." "Failed to install Caddy.")"
    return 1
  fi
  return 0
}

run_node_caddy_selfsteal_flow() {
  local domain=""
  local monitor_port=""

  draw_header "$(tr_text "RemnaNode: Caddy self-steal" "RemnaNode: Caddy self-steal")"
  while true; do
    domain="$(ask_value "$(tr_text "Домен для self-steal (пример: node.example.com)" "Domain for self-steal (example: node.example.com)")" "")"
    [[ "$domain" == "__PBM_BACK__" ]] && return 1
    [[ -n "$domain" ]] && break
    paint "$CLR_WARN" "$(tr_text "Домен не может быть пустым." "Domain cannot be empty.")"
  done

  while true; do
    monitor_port="$(ask_value "$(tr_text "Порт self-steal" "Self-steal port")" "8443")"
    [[ "$monitor_port" == "__PBM_BACK__" ]] && return 1
    if [[ "$monitor_port" =~ ^[0-9]+$ ]]; then
      break
    fi
    paint "$CLR_WARN" "$(tr_text "Порт должен быть числом." "Port must be numeric.")"
  done

  if ! ensure_remnanode_caddy_installed; then
    return 1
  fi

  $SUDO install -d -m 755 /var/www/site
  $SUDO bash -c "cat > /var/www/site/index.html <<HTML
<!doctype html>
<html lang=\"en\">
<head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>OK</title></head>
<body><h1>OK</h1></body>
</html>
HTML"

  $SUDO bash -c "cat > /etc/caddy/Caddyfile <<CADDY
${domain}:${monitor_port} {
    @local {
        remote_ip 127.0.0.1 ::1
    }

    handle @local {
        root * /var/www/site
        try_files {path} /index.html
        file_server
    }

    handle {
        abort
    }
}
CADDY"

  if ! $SUDO systemctl enable --now caddy >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "Не удалось включить caddy в автозапуск." "Failed to enable caddy autostart.")"
  fi
  if $SUDO systemctl restart caddy >/dev/null 2>&1; then
    paint "$CLR_OK" "$(tr_text "Caddy self-steal настроен." "Caddy self-steal configured.")"
    return 0
  fi

  paint "$CLR_DANGER" "$(tr_text "Не удалось перезапустить Caddy." "Failed to restart Caddy.")"
  return 1
}

run_node_bbr_flow() {
  draw_header "$(tr_text "RemnaNode: BBR" "RemnaNode: BBR")"
  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    paint "$CLR_OK" "$(tr_text "BBR уже включен." "BBR is already enabled.")"
    return 0
  fi

  if ! ask_yes_no "$(tr_text "Включить BBR сейчас?" "Enable BBR now?")" "y"; then
    return 1
  fi

  if ! $SUDO grep -q '^net.core.default_qdisc=fq$' /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc=fq" | $SUDO tee -a /etc/sysctl.conf >/dev/null
  fi
  if ! $SUDO grep -q '^net.ipv4.tcp_congestion_control=bbr$' /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.tcp_congestion_control=bbr" | $SUDO tee -a /etc/sysctl.conf >/dev/null
  fi

  if ! $SUDO sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "Не удалось применить net.core.default_qdisc=fq." "Failed to apply net.core.default_qdisc=fq.")"
  fi
  if ! $SUDO sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "Не удалось применить net.ipv4.tcp_congestion_control=bbr." "Failed to apply net.ipv4.tcp_congestion_control=bbr.")"
  fi
  if ! $SUDO sysctl -p >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "sysctl -p завершился с ошибкой." "sysctl -p failed.")"
  fi

  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    paint "$CLR_OK" "$(tr_text "BBR включен." "BBR enabled.")"
    return 0
  fi
  paint "$CLR_WARN" "$(tr_text "BBR не подтвержден. Проверьте sysctl вручную." "BBR not confirmed. Check sysctl manually.")"
  return 1
}

run_node_ipv6_toggle_flow() {
  local state=""
  local conf_file="/etc/sysctl.d/99-remnanode-ipv6.conf"

  draw_header "$(tr_text "RemnaNode: IPv6" "RemnaNode: IPv6")"
  state="$(sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk -F'= ' '{print $2}' || echo "0")"
  if [[ "$state" == "1" ]]; then
    paint "$CLR_WARN" "$(tr_text "Текущее состояние: IPv6 выключен." "Current state: IPv6 is disabled.")"
    if ! ask_yes_no "$(tr_text "Включить IPv6?" "Enable IPv6?")" "y"; then
      return 1
    fi
    $SUDO bash -c "cat > ${conf_file} <<CONF
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0
CONF"
  else
    paint "$CLR_OK" "$(tr_text "Текущее состояние: IPv6 включен." "Current state: IPv6 is enabled.")"
    if ! ask_yes_no "$(tr_text "Выключить IPv6?" "Disable IPv6?")" "n"; then
      return 1
    fi
    $SUDO bash -c "cat > ${conf_file} <<CONF
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
CONF"
  fi

  if ! $SUDO sysctl --system >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "Применение sysctl --system завершилось с ошибкой." "Applying sysctl --system failed.")"
  fi
  paint "$CLR_OK" "$(tr_text "Настройка IPv6 применена." "IPv6 setting applied.")"
  paint "$CLR_MUTED" "  $(tr_text "Файл:" "File:") ${conf_file}"
  return 0
}

install_wgcf_binary() {
  local release_url="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
  local version=""
  local arch=""
  local wgcf_arch=""
  local bin_name=""
  local download_url=""

  version="$(curl -fsSL "$release_url" 2>/dev/null | awk -F'"' '/tag_name/ {print $4; exit}')"
  [[ -n "$version" ]] || return 1

  arch="$(uname -m)"
  case "$arch" in
    x86_64) wgcf_arch="amd64" ;;
    aarch64|arm64) wgcf_arch="arm64" ;;
    armv7l) wgcf_arch="armv7" ;;
    *) wgcf_arch="amd64" ;;
  esac

  bin_name="wgcf_${version#v}_linux_${wgcf_arch}"
  download_url="https://github.com/ViRb3/wgcf/releases/download/${version}/${bin_name}"
  curl -fsSL "$download_url" -o "$TMP_DIR/$bin_name" || return 1
  chmod +x "$TMP_DIR/$bin_name"
  $SUDO mv "$TMP_DIR/$bin_name" /usr/local/bin/wgcf
  return 0
}

run_node_warp_native_flow() {
  local wgcf_dir="$TMP_DIR/wgcf"
  local reconfigure=0

  draw_header "$(tr_text "RemnaNode: WARP Native (wgcf)" "RemnaNode: WARP Native (wgcf)")"
  paint "$CLR_WARN" "$(tr_text "Режим: best-effort. Скрипт попробует настроить wgcf и интерфейс warp." "Mode: best-effort. Script will try to configure wgcf and warp interface.")"

  if command -v wgcf >/dev/null 2>&1 && [[ -f /etc/wireguard/warp.conf ]]; then
    if ask_yes_no "$(tr_text "WARP уже настроен. Переустановить/переконфигурировать?" "WARP is already configured. Reconfigure?")" "n"; then
      reconfigure=1
    else
      return 1
    fi
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    paint "$CLR_DANGER" "$(tr_text "Автонастройка WARP поддерживается только на apt-системах." "Automatic WARP setup is supported only on apt-based systems.")"
    return 1
  fi

  paint "$CLR_ACCENT" "$(tr_text "Устанавливаю зависимости (wireguard, curl)..." "Installing dependencies (wireguard, curl)...")"
  if ! $SUDO apt-get update -y >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "apt update завершился с ошибкой." "apt update failed.")"
  fi
  if ! $SUDO apt-get install -y wireguard curl >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "Установка wireguard/curl завершилась с ошибкой." "wireguard/curl installation failed.")"
  fi

  if [[ "$reconfigure" == "1" ]]; then
    if ! $SUDO systemctl disable --now wg-quick@warp >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Не удалось отключить старый wg-quick@warp." "Failed to disable old wg-quick@warp.")"
    fi
    if ! $SUDO rm -f /etc/wireguard/warp.conf >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "Не удалось удалить старый /etc/wireguard/warp.conf." "Failed to remove old /etc/wireguard/warp.conf.")"
    fi
  fi

  if ! command -v wgcf >/dev/null 2>&1; then
    paint "$CLR_ACCENT" "$(tr_text "Скачиваю wgcf..." "Downloading wgcf...")"
    if ! install_wgcf_binary; then
      paint "$CLR_DANGER" "$(tr_text "Не удалось скачать wgcf." "Failed to download wgcf.")"
      return 1
    fi
  fi

  mkdir -p "$wgcf_dir"
  (
    cd "$wgcf_dir"
    if [[ ! -f wgcf-account.toml ]]; then
      if ! yes | wgcf register >/dev/null 2>&1; then
        paint "$CLR_WARN" "$(tr_text "wgcf register завершился с ошибкой." "wgcf register failed.")"
      fi
    fi
    if ! wgcf generate >/dev/null 2>&1; then
      paint "$CLR_WARN" "$(tr_text "wgcf generate завершился с ошибкой." "wgcf generate failed.")"
    fi
  )

  if [[ ! -f "$wgcf_dir/wgcf-profile.conf" ]]; then
    paint "$CLR_DANGER" "$(tr_text "wgcf не сгенерировал профиль. Проверьте доступ к Cloudflare API." "wgcf did not generate profile. Check Cloudflare API access.")"
    return 1
  fi

  $SUDO install -d -m 700 /etc/wireguard
  $SUDO cp "$wgcf_dir/wgcf-profile.conf" /etc/wireguard/warp.conf
  if ! $SUDO sed -i '/^DNS =/d' /etc/wireguard/warp.conf; then
    paint "$CLR_WARN" "$(tr_text "Не удалось удалить строку DNS из warp.conf." "Failed to remove DNS line from warp.conf.")"
  fi
  if ! $SUDO grep -q '^Table = off$' /etc/wireguard/warp.conf 2>/dev/null; then
    if ! $SUDO sed -i '/^MTU =/aTable = off' /etc/wireguard/warp.conf; then
      paint "$CLR_WARN" "$(tr_text "Не удалось добавить Table = off в warp.conf." "Failed to add Table = off to warp.conf.")"
    fi
  fi
  if ! $SUDO grep -q '^PersistentKeepalive = 25$' /etc/wireguard/warp.conf 2>/dev/null; then
    if ! $SUDO sed -i '/^Endpoint =/aPersistentKeepalive = 25' /etc/wireguard/warp.conf; then
      paint "$CLR_WARN" "$(tr_text "Не удалось добавить PersistentKeepalive в warp.conf." "Failed to add PersistentKeepalive to warp.conf.")"
    fi
  fi

  if ! $SUDO systemctl enable --now wg-quick@warp >/dev/null 2>&1; then
    paint "$CLR_WARN" "$(tr_text "Не удалось включить wg-quick@warp в автозапуск." "Failed to enable wg-quick@warp autostart.")"
  fi
  if $SUDO systemctl restart wg-quick@warp >/dev/null 2>&1; then
    paint "$CLR_OK" "$(tr_text "WARP Native настроен." "WARP Native configured.")"
    return 0
  fi

  paint "$CLR_WARN" "$(tr_text "WARP применен частично. Проверьте: systemctl status wg-quick@warp и wg show warp" "WARP was applied partially. Check: systemctl status wg-quick@warp and wg show warp")"
  return 1
}

run_remnanode_full_setup_flow() {
  draw_header "$(tr_text "RemnaNode: полная настройка" "RemnaNode: full setup")"
  paint "$CLR_MUTED" "$(tr_text "Последовательно: нода -> Caddy self-steal -> BBR -> WARP Native." "Sequence: node -> Caddy self-steal -> BBR -> WARP Native.")"

  if ! run_node_install_flow; then
    paint "$CLR_WARN" "$(tr_text "Полная настройка остановлена на установке ноды." "Full setup stopped at node installation.")"
    return 1
  fi

  if ! run_node_caddy_selfsteal_flow; then
    paint "$CLR_WARN" "$(tr_text "Нода установлена, но Caddy self-steal не настроен." "Node installed, but Caddy self-steal was not configured.")"
    return 1
  fi

  if ! run_node_bbr_flow; then
    paint "$CLR_WARN" "$(tr_text "BBR не был подтвержден." "BBR was not confirmed.")"
  fi

  if ! run_node_warp_native_flow; then
    paint "$CLR_WARN" "$(tr_text "WARP Native настроен частично или с ошибкой." "WARP Native finished partially or with errors.")"
  fi

  paint "$CLR_OK" "$(tr_text "Полная настройка RemnaNode завершена." "RemnaNode full setup completed.")"
  return 0
}
