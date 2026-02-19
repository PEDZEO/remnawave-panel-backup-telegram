# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

Скрипт для установки и управления backup/restore Remnawave через единый интерактивный менеджер (RU/EN).

## Что умеет

- установка и обновление runtime-скриптов backup/restore
- первичная настройка Telegram, расписания и параметров backup
- ручной запуск backup и восстановление из файла или URL
- dry-run восстановление и предзапусковый чеклист безопасности
- поддержка шифрования backup-архивов (GPG symmetric)
- status-раздел с диагностикой systemd, архива и контейнеров
- установка/обновление Remnawave панели и RemnaNode из меню

## Быстрый запуск

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Структура проекта

- `install.sh` — точка входа для запуска с GitHub
- `manager.sh` — основной менеджер (режимы + интерактивное меню)
- `panel-backup.sh` — создание backup
- `panel-restore.sh` — восстановление backup
- `scripts/install/pipeline.sh` — установка и настройка окружения
- `scripts/runtime/operations.sh` — backup/restore/status операции
- `scripts/runtime/panel_node.sh` — установка/обновление панели и ноды
- `scripts/menu/interactive.sh` — UI-логика меню
- `systemd/panel-backup.service` — systemd unit
- `systemd/panel-backup.timer` — расписание backup

## Режимы запуска

- `MODE=install` — установка/обновление manager + env + timer
- `MODE=backup` — запустить backup сейчас
- `MODE=restore` — запустить restore
- `MODE=status` — показать статус

Пример restore из файла:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/pb-xxxx.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Требования

- Linux-сервер с systemd
- Bash, curl, tar, docker/docker compose
- root или sudo

## Лицензия

MIT. См. `LICENSE`.
