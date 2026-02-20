# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

Interactive Remnawave manager: backup/restore, scheduling, encryption, status diagnostics, and install/update flows for related components in one interface.

## Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Features

- Clear interactive menu in Russian and English.
- One-step manual backup.
- Scheduled automatic backups via systemd timer.
- Restore from local archive file or direct URL.
- `dry-run` restore mode to validate flow before real changes.
- Encrypted backup archives (GPG symmetric) for safer storage and transfer.
- Status and diagnostics: timer, service, latest backup, container state, and key runtime signals.
- Disk usage analysis and safe cleanup without removing active containers or volumes.
- Dedicated install/update actions for Remnawave panel.
- Dedicated install/update actions for RemnaNode.
- RemnaNode network tools: Caddy self-steal, BBR, WARP Native (wgcf), and IPv6 toggle.
- Dedicated install/update actions for Remnawave subscription page.
- One-VPS Bedolaga stack install/update: `remnawave-bedolaga-telegram-bot`, `bedolaga-cabinet`, and Caddy integration.
  Install paths: `/root/remnawave-bedolaga-telegram-bot`, `/root/bedolaga-cabinet`, and `/root/caddy` for containerized Caddy setups.
- Composite flows: full install/update for Remnawave and full setup for RemnaNode.

## Bedolaga components

- Bot: https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot
- Cabinet: https://github.com/BEDOLAGA-DEV/bedolaga-cabinet

## Requirements

- Linux with systemd.
- Bash, curl, tar, docker/docker compose.
- root or sudo.

## License

MIT. See `LICENSE`.
