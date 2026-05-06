# claude-skill-senler

> Claude Code skill для аналитики и сегментации в [Senler](https://senler.ru) — сервисе чат-ботов для VK.

Превращает Senler-канал в управляемый AI-агентом источник данных: воронки, рассылки, подписчики, UTM-источники. AI читает аналитику и помогает сегментировать молчунов / отвалившихся / не дошедших до продажи через теги.

## Что умеет скилл

### Аналитика (read)
- Карта всех воронок канала со статусами
- Структура шагов любой воронки + lead_inc на каждом шаге
- Сводная статистика рассылок (read rate, ошибки)
- UTM-атрибуция подписок (если UTM настроены)
- Источники подписок и отписок
- Сегменты подписчиков по тегам / ботам / периодам

### Сегментация (write)
- Создавать новые теги/группы
- Присваивать тег конкретному подписчику
- Запускать подписчика по конкретной воронке
- Выкидывать подписчика из воронки

### Что НЕ умеет (и не будет — нет в Senler API)
- Создавать новых ботов / шаги воронки
- Редактировать текст сообщений в шагах
- Создавать рассылки (broadcasts)

То есть: **AI-аналитик и AI-сегментатор.** Создание контента и запуск кампаний остаётся за командой в UI Senler.

## Установка

```bash
cd ~/.claude/skills
git clone https://github.com/atomachinskiy/claude-skill-senler.git senler
chmod +x senler/scripts/*.sh
bash senler/scripts/senler-oauth-setup.sh
```

Мастер интерактивно проведёт через все 5 шагов OAuth-flow:
1. Создание OAuth-приложения в кабинете Senler
2. Сохранение `client_id` / `client_secret` в `~/.claude/secrets/senler-app.json`
3. Авторизация через браузер (открывается автоматически)
4. Обмен `code` на `access_token`
5. Sanity-check подключения (проверяет работу API)

Подробная инструкция: [`config/setup-guide.md`](config/setup-guide.md)

## Как использовать

После установки можно просто разговаривать с Claude:

- «Покажи мои воронки в Senler»
- «Сделай аналитику моего канала»
- «Где люди отваливаются в воронке X?»
- «Найди молчунов на шаге N и поставь им тег "Re-engage"»
- «Какие источники приводят больше всего подписчиков?»

Или вызывать скрипты напрямую:

```bash
bash ~/.claude/skills/senler/scripts/senler-bots-list.sh
bash ~/.claude/skills/senler/scripts/senler-bot-steps.sh <bot_id>
bash ~/.claude/skills/senler/scripts/senler-deliveries-stat.sh
bash ~/.claude/skills/senler/scripts/senler-utms-stats.sh
```

## Требования

- macOS / Linux (bash)
- `jq` (`brew install jq`)
- `curl`, `python3`
- Аккаунт администратора в нужном Senler-канале
- 5-7 минут на OAuth-настройку

## Структура

```
senler/
├── SKILL.md                              ← главный документ для Claude
├── config/
│   ├── .env.example
│   └── setup-guide.md                    ← пошаговая инструкция OAuth
└── scripts/
    ├── _common.sh                        ← обёртка POST → senler.ru/api/
    ├── senler-oauth-setup.sh             ← интерактивный мастер настройки
    ├── senler-subscribers-count.sh
    ├── senler-bots-list.sh
    ├── senler-bot-steps.sh
    ├── senler-subscribers-list.sh
    ├── senler-utms-stats.sh
    ├── senler-deliveries-stat.sh
    └── senler-call.sh                    ← raw-вызов любого метода API
```

## Безопасность

- `~/.claude/secrets/senler-app.json` (`client_secret`) — `chmod 600`, не коммитится
- `~/.claude/skills/senler/config/.env` (`access_token`) — `chmod 600`, в `.gitignore`
- Токен OAuth от Senler бессрочный, можно отозвать в кабинете в любой момент

## Лицензия

MIT
