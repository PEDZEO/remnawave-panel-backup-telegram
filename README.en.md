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
- Full Bedolaga stack backup/restore (bot + cabinet): PostgreSQL, Redis, `.env`, compose files, and runtime data.
- Restore from local archive file or direct URL.
- SHA256 checksum for new archives and checksum verification before restore when a `.sha256` file is present.
- Encrypted backup archives (GPG symmetric) for safer storage and transfer.
- Telegram topic split support: separate topics for panel backups and Bedolaga backups (bot + cabinet).
- Status and diagnostics: timer, service, latest backup, container state, and key runtime signals.
- Read-only Doctor check from the interactive menu.
- Disk usage analysis and safe cleanup without removing active containers or volumes.
- Dedicated install/update actions for Remnawave panel.
- Dedicated install/update actions for RemnaNode.
- RemnaNode network tools: Caddy self-steal, BBR, WARP Native (wgcf), and IPv6 toggle.
- Dedicated install/update actions for Remnawave subscription page.
- One-VPS Bedolaga stack install/update: `remnawave-bedolaga-telegram-bot`, `bedolaga-cabinet`, and Caddy integration.
  Install paths: `/root/remnawave-bedolaga-telegram-bot`, `/root/bedolaga-cabinet`, and `/root/caddy` for containerized Caddy setups.
- Composite flows: full install/update for Remnawave and full setup for RemnaNode.
- Dedicated integration page for the external [Reshala-Remnawave-Bedolaga](https://github.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga) toolbox.

## Reshala toolbox

The manager includes a separate page for [Reshala-Remnawave-Bedolaga](https://github.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga). It can show the feature map, install/update the external toolbox, and open the Reshala menu. Reshala code is not vendored into this repository; it remains an external project with its own files and settings.

## Bedolaga components

- Official organization: [BEDOLAGA-DEV](https://github.com/BEDOLAGA-DEV)
- PEDZEO fork: [PEDZEO](https://github.com/PEDZEO)
- Official bot: [BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot](https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot)
- Official cabinet: [BEDOLAGA-DEV/bedolaga-cabinet](https://github.com/BEDOLAGA-DEV/bedolaga-cabinet)
- Fork bot: [PEDZEO/remnawave-bedolaga-telegram-bot](https://github.com/PEDZEO/remnawave-bedolaga-telegram-bot)
- Fork cabinet: [PEDZEO/cabinet-frontend](https://github.com/PEDZEO/cabinet-frontend)

## Contact

- Telegram: https://t.me/pedzeo (@pedzeo)

## Requirements

- Linux with systemd.
- Bash, curl, tar, docker/docker compose.
- root or sudo.

## License

MIT. See `LICENSE`.
