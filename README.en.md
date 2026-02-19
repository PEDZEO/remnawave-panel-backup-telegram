# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

A practical manager for Remnawave: backup, restore, schedule, encryption, and basic panel/node/subscription operations in one interactive menu.

## Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Features

- RU/EN interactive menu
- manual backup and systemd timer backup
- restore from local file or URL
- `dry-run` mode before real restore
- encrypted archives (GPG symmetric)
- status and diagnostics for timer/service/containers
- install and update flows for:
  - Remnawave panel
  - RemnaNode
  - Remnawave subscription page

## Run Modes

- `MODE=install` - install/update manager, env, and timer
- `MODE=backup` - run backup now
- `MODE=restore` - run restore
- `MODE=status` - show status

Restore example:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/pb-xxxx.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Requirements

- Linux with systemd
- Bash, curl, tar, docker/docker compose
- root or sudo

## License

MIT. See `LICENSE`.
