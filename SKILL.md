---
name: senler
description: Анализ воронок, подписчиков и рассылок в Senler (чат-боты VK через senler.ru/api). Используй когда пользователь просит посмотреть аналитику Senler-канала, найти проблемные шаги в воронке, посчитать конверсию, разобрать рассылки, сегментировать подписчиков или добавить их в группы. Подключается по ключу API канала (Senler → Настройки → Работа с API), OAuth — запасной путь.
---

# Senler — AI-аналитик и AI-сегментатор для VK чат-ботов

Скилл подключается к Senler API (`senler.ru/api`) и даёт AI-агенту доступ к **аналитике** и **управлению подписчиками** в канале Senler. Подключается по ключу API из настроек канала (с 27.10.2026; приложение и OAuth не нужны).

## Когда использовать

- Drop-off / падение трафика по шагам воронки
- Карта всех сценариев в канале с маркировкой статуса (активные / копии / пустые)
- Источники подписок и отписок
- Read rate рассылок по сценариям
- Список подписчиков с фильтром по боту или тегу
- Сегментация молчунов и присвоение им тегов
- Сводная аналитика для отчёта клиенту

## Prereqs

- `jq` (`brew install jq`)
- `~/.claude/skills/senler/config/.env` — `SENLER_ACCESS_TOKEN`, `SENLER_GROUP_ID`, `SENLER_V=2`

Полная инструкция подключения — `config/setup-guide.md`.

Если `.env` нет, подключение по ключу API:
1. Скажи человеку: в Senler откройте канал → «Настройки» → «Работа с API» → создайте ключ. Ключ вводится только в отдельном окне, в чат его не присылать.
2. Открой мастер в отдельном окне (сам `senler-key-setup.*` через Bash tool не запускай, ключ попадёт в транскрипт):
   - macOS / Linux: `bash ~/.claude/skills/senler/scripts/senler-launch-wizard.sh`
   - Windows: `powershell -ExecutionPolicy Bypass -File "$(cygpath -w ~/.claude/skills/senler/scripts/senler-launch-wizard.ps1)"`
3. Мастер спросит ключ и ID канала (ID сообщества ВК, ссылку на него, ID канала в Senler или ID бота Telegram), сам найдёт канал, сохранит `.env` и напишет «Senler настроен».
4. Проверка: `senler-subscribers-count.sh`.

⚠️ Адрес `https://oauth.senler.ru/blank.html` из старых инструкций мёртв (домена нет, Senler пишет «Неверный адрес»). OAuth только как запасной путь: `senler-launch-wizard.sh --oauth`, адрес возврата человек указывает свой.

## ВАЖНО: что МОЖНО и что НЕЛЬЗЯ через Senler API

### ✅ Через API ДОСТУПНО

Список сверен с документацией 27.10.2026 (31 метод, https://help.senler.ru/senler/help/razrabotchikam/api/methods).

**Чтение (полная аналитика):**
- `groups/get` — канал: `group_id` в Senler, название, тип (vk/tg), `external_id`
- `bots/get` — боты канала: `bot_id`, `title`, `active` (1 запущен), `published` (0 — есть неопубликованные изменения), теги
- `bots/getSteps bot_id=` — шаги бота: `step_id`, `title`, `type` (start/timer/action/if/message/dispatcher), `lead_inc` (сколько раз шаг запускался)
- `subscribers/count`, `subscribers/get` — подписчики; фильтры `bot_id`, `step_id[]`, `ignore_bot_id`, `subscription_id[]`, рассылки (`read_delivery_id[]`, `ignore_read_delivery_id[]` …), даты, метки, `lead_status`, переменные; до 100 за раз, следующая страница по `offset_id` из ответа
- `subscribers/statSubscribe`, `subscribers/statCount` — журнал и агрегаты подписок/отписок
- `deliveries/get` — рассылки со статистикой: получатели, доставлено, ошибки, прочитано, переходы, отписки
- `deliveries/stat`, `deliveries/statCount` — пословный лог доставки, обязательны `date_from`, `date_to` (`d.m.Y H:i:s`)
- `subscriptions/get` — группы подписчиков
- `utms/get`, `utms/statSubscribe`, `utms/statCount`, `utms/getLink` — метки и ссылки с ними
- `vars/get`, `vars_global/get` — переменные

**Управление (write):**
- `subscriptions/add` / `edit` / `del` — группы подписчиков (это и есть «теги» для сегментов)
- `subscribers/add` — добавить подписчика в группу (`subscription_id`, можно массив id), `subscribers/del` — убрать из группы
- `bots/addSubscriber` / `bots/delSubscriber` — запустить подписчика по боту (можно с `step_id`) или убрать из бота
- `vars/set` / `vars/del`, `vars_global/set` / `vars_global/del` — переменные
- `utms/add` / `edit` / `del` — метки

Канал в любом запросе можно передать как `group_id`, `vk_group_id`, `tg_bot_id` или `max_bot_id`.

### ❌ Через API НЕДОСТУПНО (только в UI Senler)

- ❌ Создавать новых ботов / воронок (нет `bots/create`)
- ❌ Редактировать шаги в существующих ботах — нельзя изменить текст сообщения, кнопки, триггеры (нет `bots/setSteps`, `bots/updateStep`)
- ❌ Создавать / редактировать / запускать рассылки (есть только `deliveries/get`, `stat`, `statCount`)
- ❌ Создавать триггеры на события сообщества
- ❌ Читать **точный текст** сообщения внутри шага — API возвращает только название шага и его тип, не контент

### Реальный сценарий использования

AI читает данные → находит проблемное место (молчуны, отписавшиеся, не дошедшие до продажи) → создаёт для них группу подписчиков `subscriptions/add` и добавляет их `subscribers/add` → пользователь в UI Senler запускает рассылку по этой группе → AI читает результат через `deliveries/get` и сравнивает с предыдущим.

То есть скилл = **AI-аналитик + AI-сегментатор**. Создание ботов и запуск кампаний остаётся за командой в UI.

## Роутер задач

| Задача | Скрипт | Пример |
|---|---|---|
| Sanity-check конфига | `senler-subscribers-count.sh` | «Проверь работает ли Senler» |
| Карта всех ботов канала | `senler-bots-list.sh` | «Какие воронки у меня в Сенлер?» |
| Структура одной воронки | `senler-bot-steps.sh <bot_id>` | «Покажи шаги воронки 123» |
| Список подписчиков | `senler-subscribers-list.sh [--bot ID]` | «Кто подписан на воронку X?» |
| UTM-источники | `senler-utms-stats.sh [--from --to]` | «Откуда подписчики приходят?» |
| Статистика рассылок | `senler-deliveries-stat.sh` | «Как зашли последние рассылки?» |
| Любой raw-запрос API | `senler-call.sh <method> [params]` | Когда нужен метод не из списка |

## Как вызывать

```bash
bash ~/.claude/skills/senler/scripts/SCRIPT_NAME.sh ARGS
```

Общие флаги: `--json` (сырой JSON), `--full` (без обрезки 30 строк).

## Типичные сценарии

### «Сделай drop-off по моей воронке X»
1. `senler-bots-list.sh` → найти `bot_id` нужной воронки
2. `senler-bot-steps.sh <bot_id>` → посмотреть структуру + lead_inc на каждом шаге
3. Попросить Claude интерпретировать данные с маркетинговой точки зрения

### «Откуда подписчики приходят?»
```bash
bash ~/.claude/skills/senler/scripts/senler-utms-stats.sh --from 2026-04-01 --to 2026-04-30
```
Если ответ пустой — UTM-метки в подписной странице не настроены, надо настроить в UI Senler.

### «Найди молчунов на шаге N в воронке X и поставь им тег»

```bash
# 1. Найти подписчиков на шаге (step_id из senler-bot-steps.sh)
bash scripts/senler-call.sh subscribers/get bot_id=123 "step_id[]=5c35bb800b295034fa5062a6" count=100

# 2. Создать группу подписчиков (скрытую, чтобы не светилась на подписной странице)
bash scripts/senler-call.sh subscriptions/add name="Молчуны после шага N" inactive=1

# 3. Добавить найденных в группу (subscription_id из ответа шага 2)
bash scripts/senler-call.sh subscribers/add vk_user_id=123456 subscription_id=NEW_ID

# Всё это меняет живую базу: только после «да» человека.
```

### «Что-то нестандартное (метод не из списка)»
```bash
bash ~/.claude/skills/senler/scripts/senler-call.sh <ANY_METHOD> param=value
```

`senler-call.sh` — универсальный raw-вызов любого Senler API метода с уже подставленным auth.

## Ограничения

- **Лимит count:** максимум 100 на запрос. Следующая страница `subscribers/get` и `deliveries/stat` — по `offset_id` из ответа, у `bots/get`, `deliveries/get`, `subscriptions/get` — `offset`.
- **Один ключ = один канал.** Несколько каналов — ключ на каждый. В `.env` за раз один.
- **Ключ бессрочный**, удаляется в «Работа с API». OAuth-токен тоже бессрочный.
- **Rate limit:** 20 запросов в секунду на ключ, при превышении ошибка 9. Скилл ставит задержку ~0,35 с.
- **Ошибки:** 6 — канал не найден, 13/14 — ключ не найден или недействителен.
- **Текст сообщений в шагах НЕ доступен** — только название и тип шага.

## Файлы скилла

```
~/.claude/skills/senler/
├── SKILL.md                              # этот файл
├── config/
│   ├── .env.example                      # шаблон конфига
│   ├── .env                              # реальный конфиг (gitignored)
│   └── setup-guide.md                    # подключение по ключу, запасной OAuth
├── scripts/
│   ├── _common.sh                        # обёртка POST → senler.ru/api/
│   ├── senler-launch-wizard.sh / .ps1    # открывает мастер в отдельном окне
│   ├── senler-key-setup.sh / .ps1        # мастер по ключу API
│   ├── senler-oauth-setup.sh / .ps1      # мастер OAuth (запасной)
│   ├── senler-subscribers-count.sh       # sanity-check + total subs
│   ├── senler-bots-list.sh               # все воронки канала
│   ├── senler-bot-steps.sh               # шаги одной воронки
│   ├── senler-subscribers-list.sh        # пагинация подписчиков
│   ├── senler-utms-stats.sh              # UTM-источники
│   ├── senler-deliveries-stat.sh         # рассылки: доставлено, прочитано, переходы
│   └── senler-call.sh                    # raw-вызов любого метода
└── cache/                                # кеш (если используется)
```

## Связанная документация

- API Senler: https://help.senler.ru/senler/help/razrabotchikam/api
- Methods reference: https://help.senler.ru/senler/help/razrabotchikam/api/methods/boty
- Ключи доступа: https://help.senler.ru/senler/help/razrabotchikam/api/klyuchi-dostupa
- OAuth flow (запасной): https://help.senler.ru/senler/help/razrabotchikam/prilozheniya/varianty-integracii/oauth
