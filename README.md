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
- Создавать, менять и удалять группы подписчиков (`subscriptions/*`)
- Добавлять подписчика в группу и убирать из неё (`subscribers/add`, `subscribers/del`)
- Ставить переменные подписчику и глобальные переменные (`vars/*`, `vars_global/*`)
- Запускать подписчика по боту, в том числе с нужного шага, и убирать из бота
- Создавать метки (UTM) и ссылки на подписную страницу с меткой

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
bash senler/scripts/senler-launch-wizard.sh      # Windows: senler-launch-wizard.ps1
```

С 27.10.2026 подключение по **ключу API**: в Senler канал → «Настройки» → «Работа с API» → создать ключ. Мастер откроется в отдельном окне, спросит ключ (скрыто) и ID канала (подойдёт ID сообщества ВК или ссылка на него), проверит и сохранит `config/.env`. OAuth-приложение не нужно.

OAuth остался запасным путём: `senler-launch-wizard.sh --oauth`. Старый адрес возврата `https://oauth.senler.ru/blank.html` больше не работает, мастер спросит свой.

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
- `curl` (для OAuth ещё `python3`)
- Доступ к настройкам нужного канала в Senler
- 2–3 минуты на подключение по ключу; Windows: PowerShell, Git Bash для мастера не нужен

## Структура

```
senler/
├── SKILL.md                              ← главный документ для Claude
├── config/
│   ├── .env.example
│   └── setup-guide.md                    ← подключение по ключу и запасной OAuth
└── scripts/
    ├── _common.sh                        ← обёртка POST → senler.ru/api/
    ├── senler-launch-wizard.sh / .ps1    ← открывает мастер в отдельном окне
    ├── senler-key-setup.sh / .ps1        ← мастер по ключу API (основной)
    ├── senler-oauth-setup.sh / .ps1      ← мастер OAuth (запасной)
    ├── senler-subscribers-count.sh
    ├── senler-bots-list.sh
    ├── senler-bot-steps.sh
    ├── senler-subscribers-list.sh
    ├── senler-utms-stats.sh
    ├── senler-deliveries-stat.sh
    └── senler-call.sh                    ← raw-вызов любого метода API
```

## Безопасность

- Ключ вводится только в отдельном окне мастера, в чат с ИИ он не попадает
- `~/.claude/skills/senler/config/.env` (ключ или токен) — `chmod 600`, в `.gitignore`
- Для OAuth: `~/.claude/secrets/senler-app.json` (`client_secret`) — `chmod 600`, не коммитится
- Ключ можно удалить в «Работа с API» в любой момент; лимит 20 запросов в секунду на ключ

## Лицензия

MIT
