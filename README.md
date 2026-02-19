# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

Этот скрипт нужен, чтобы вы могли спокойно обслуживать Remnawave без ручной рутины: сделать backup, проверить состояние, безопасно запустить restore и при необходимости обновить панель, ноду или страницу подписок через одно понятное меню.

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Возможности

- Понятное интерактивное меню на русском и английском.
- Создание backup вручную в один шаг.
- Автоматические backup по расписанию через systemd timer.
- Восстановление из локального файла или по прямой ссылке (URL).
- `dry-run` режим restore, чтобы сначала проверить сценарий без изменений в системе.
- Шифрование архивов backup (GPG symmetric), чтобы хранить и передавать их безопаснее.
- Отображение статуса: таймер, сервис, последний backup, состояние контейнеров и базовые диагностические данные.
- Отдельные действия по установке и обновлению Remnawave panel.
- Отдельные действия по установке и обновлению RemnaNode.
- Отдельные действия по установке и обновлению Remnawave subscription page.

## Режимы запуска

- `MODE=install` — установка/обновление менеджера, env и timer.
- `MODE=backup` — запустить backup сейчас.
- `MODE=restore` — запустить restore.
- `MODE=status` — показать статус.

Пример restore:

```bash
MODE=restore BACKUP_FILE='/var/backups/panel/pb-xxxx.tar.gz' \
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Требования

- Linux с systemd.
- Bash, curl, tar, docker/docker compose.
- root или sudo.

## Лицензия

MIT. См. `LICENSE`.
