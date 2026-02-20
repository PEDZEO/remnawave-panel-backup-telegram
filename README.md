# Remnawave Panel Backup Manager

[English](README.en.md) | [Русский](README.md)

Интерактивный менеджер для Remnawave: резервное копирование и восстановление, расписание, шифрование, мониторинг состояния и установка/обновление компонентов в одном интерфейсе.

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PEDZEO/remnawave-panel-backup-telegram/main/install.sh)
```

## Возможности

- Понятное интерактивное меню на русском и английском.
- Создание резервной копии вручную в один шаг.
- Автоматические резервные копии по расписанию через systemd timer.
- Восстановление из локального файла или по прямой ссылке (URL).
- `dry-run` режим восстановления, чтобы сначала проверить сценарий без изменений в системе.
- Шифрование архивов резервной копии (GPG symmetric), чтобы хранить и передавать их безопаснее.
- Отображение статуса: таймер, сервис, последняя резервная копия, состояние контейнеров и базовые диагностические данные.
- Анализ использования диска и безопасная очистка мусора без удаления рабочих контейнеров и томов.
- Отдельные действия по установке и обновлению Remnawave panel.
- Отдельные действия по установке и обновлению RemnaNode.
- Сетевые инструменты для RemnaNode: Caddy self-steal, BBR, WARP Native (wgcf), переключение IPv6.
- Отдельные действия по установке и обновлению страницы подписок Remnawave.
- Автоустановка и обновление Bedolaga-стека на одном VPS: бот `remnawave-bedolaga-telegram-bot`, кабинет `bedolaga-cabinet` и интеграция в Caddy.
  Пути установки: `/root/remnawave-bedolaga-telegram-bot`, `/root/bedolaga-cabinet`, Caddy-конфиг в `/root/caddy` (если используется контейнерный Caddy).
- Составные сценарии: полная установка/обновление Remnawave и полная настройка RemnaNode.

## Bedolaga компоненты

- Бот: https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot
- Кабинет: https://github.com/BEDOLAGA-DEV/bedolaga-cabinet

## Связь

- Telegram: https://t.me/pedzeo (@pedzeo)

## Требования

- Linux с systemd.
- Bash, curl, tar, docker/docker compose.
- root или sudo.

## Лицензия

MIT. См. `LICENSE`.
