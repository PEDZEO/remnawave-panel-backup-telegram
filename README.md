# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

Удобный менеджер для Remnawave: backup, restore, расписание, шифрование и базовые операции по панели/ноде/странице подписок в одном интерактивном меню.

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Возможности

- интерактивное меню RU/EN
- создание backup вручную и по таймеру systemd
- восстановление из файла или по URL
- `dry-run` режим перед боевым restore
- шифрование архивов (GPG symmetric)
- статус и диагностика таймера/сервиса/контейнеров
- установка и обновление:
  - Remnawave panel
  - RemnaNode
  - Remnawave subscription page

## Режимы запуска

- `MODE=install` — установка/обновление менеджера, env и timer
- `MODE=backup` — запустить backup сейчас
- `MODE=restore` — запустить restore
- `MODE=status` — показать статус

Пример restore:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/pb-xxxx.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Требования

- Linux с systemd
- Bash, curl, tar, docker/docker compose
- root или sudo

## Лицензия

MIT. См. `LICENSE`.
