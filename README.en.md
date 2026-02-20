# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

This script helps you operate Remnawave without manual routine work: create backups, check health, run safer restore flows, and update panel/node/subscription components from one clear menu.

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
- Composite flows: full install/update for Remnawave and full setup for RemnaNode.

## Run Modes

- `MODE=install` - install/update manager, env, and timer.
- `MODE=backup` - run backup now.
- `MODE=restore` - run restore.
- `MODE=status` - show status.

Restore example:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/pb-xxxx.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Requirements

- Linux with systemd.
- Bash, curl, tar, docker/docker compose.
- root or sudo.

## License

MIT. See `LICENSE`.
