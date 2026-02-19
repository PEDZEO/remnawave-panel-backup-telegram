# Remnawave Panel Backup Telegram Manager

Автоматизированный backup/restore менеджер для панели Remnawave.

Управление идёт через один установщик `install.sh` в двух режимах:
- `MODE=install` — установка или обновление
- `MODE=restore` — восстановление бэкапа

## Что умеет

- Автоопределяет путь к панели (`REMNAWAVE_DIR`)
- Делает полный backup:
- PostgreSQL dump
- Redis dump (если доступен)
- `.env`, `docker-compose.yml`, `caddy/`, `subscription/`
- Отправляет архив в Telegram (в чат или в topic)
- Восстанавливает:
- всё сразу
- или выборочно по компонентам
- Поддерживает миграцию на новый VPS из backup URL
- Для restore делает pre-restore snapshot текущих конфигов

## Быстрый Старт

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

В интерактивном запуске появится меню:
- установить/обновить и настроить
- включить или выключить timer backup
- отдельно обновить Telegram/путь
- посмотреть статус (установлено ли, timer/service, последний backup)
- запустить restore

С Telegram:

```bash
TELEGRAM_BOT_TOKEN='YOUR_BOT_TOKEN' TELEGRAM_ADMIN_ID='YOUR_CHAT_ID' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

С Telegram topic:

```bash
TELEGRAM_BOT_TOKEN='YOUR_BOT_TOKEN' TELEGRAM_ADMIN_ID='-1001234567890' TELEGRAM_THREAD_ID='42' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Восстановление Через Ту Же Команду

Восстановить всё из локального архива:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/panel-backup-xxx.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

Восстановить всё из URL (миграция на другой VPS):

```bash
MODE=restore BACKUP_URL='https://example.com/panel-backup.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

Восстановить выборочно:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/panel-backup-xxx.tar.gz' RESTORE_ONLY='db,configs' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

Dry-run без изменений:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/panel-backup-xxx.tar.gz' RESTORE_ONLY='all' RESTORE_DRY_RUN=1 \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Компоненты Restore (`RESTORE_ONLY`)

- `all` (по умолчанию)
- `db`
- `redis`
- `configs` (env + compose + caddy + subscription)
- `env`
- `compose`
- `caddy`
- `subscription`

## Переменные Окружения

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ADMIN_ID`
- `TELEGRAM_THREAD_ID` (опционально, для topics)
- `REMNAWAVE_DIR` (опционально, если нужно задать вручную)
- `BACKUP_FILE` / `BACKUP_URL` (для `MODE=restore`)
- `RESTORE_ONLY` (пример: `db,configs`)
- `RESTORE_DRY_RUN=1` (проверка без изменений)
- `RESTORE_NO_RESTART=1` (без рестартов сервисов)

## Файлы В Репозитории

- `install.sh` (единый менеджер)
- `panel-backup.sh`
- `panel-restore.sh`
- `systemd/panel-backup.service`
- `systemd/panel-backup.timer`
- `.env.example`

## Локальные команды (после установки)

```bash
sudo /usr/local/bin/panel-backup.sh
sudo /usr/local/bin/panel-restore.sh --help
sudo systemctl status panel-backup.timer
sudo journalctl -u panel-backup.service -n 100 --no-pager
```

Если нужно принудительно отключить интерактивное меню:

```bash
INTERACTIVE=0 MODE=install bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

Показать статус без меню:

```bash
INTERACTIVE=0 MODE=status bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```
