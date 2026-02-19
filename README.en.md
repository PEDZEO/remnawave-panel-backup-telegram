# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

A script-based manager for backup/restore of Remnawave with a unified interactive UI (RU/EN).

## Features

- install and update backup/restore runtime scripts
- initial setup for Telegram, schedule, and backup parameters
- manual backup run and restore from file or URL
- dry-run restore mode and pre-run safety checklist
- backup archive encryption support (GPG symmetric)
- status/diagnostics for systemd, latest archive, and containers
- install/update flows for Remnawave panel and RemnaNode in menu

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Project Structure

- `install.sh` - GitHub entrypoint launcher
- `manager.sh` - main manager (modes + interactive menu)
- `panel-backup.sh` - backup creation
- `panel-restore.sh` - backup restore
- `scripts/install/pipeline.sh` - install/setup pipeline
- `scripts/runtime/operations.sh` - backup/restore/status operations
- `scripts/runtime/panel_node.sh` - panel/node install and update flows
- `scripts/menu/interactive.sh` - interactive UI logic
- `systemd/panel-backup.service` - systemd unit
- `systemd/panel-backup.timer` - backup schedule

## Run Modes

- `MODE=install` - install/update manager + env + timer
- `MODE=backup` - run backup now
- `MODE=restore` - run restore
- `MODE=status` - show status

Restore example from local file:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/pb-xxxx.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Requirements

- Linux server with systemd
- Bash, curl, tar, docker/docker compose
- root or sudo

## License

MIT. See `LICENSE`.
