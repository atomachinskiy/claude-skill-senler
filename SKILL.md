---
name: senler
description: Анализ воронок, подписчиков и рассылок в Senler (чат-боты VK через senler.ru/api). Используй когда пользователь просит посмотреть аналитику Senler-канала, найти проблемные шаги в воронке, посчитать конверсию, разобрать рассылки, сегментировать подписчиков или присвоить им теги. Работает через OAuth access_token, выдаваемый собственным приложением Senler.
---

# Senler — AI-аналитик и AI-сегментатор для VK чат-ботов

Скилл подключается к Senler API (`senler.ru/api`) и даёт AI-агенту доступ к **аналитике** и **управлению подписчиками** в канале Senler. Использует OAuth-flow через приложение, созданное в кабинете Senler пользователем.

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
- `~/.claude/secrets/senler-app.json` — OAuth-приложение Senler (`client_id`, `client_secret`, `redirect_uri`)
- `~/.claude/skills/senler/config/.env` — `SENLER_ACCESS_TOKEN`, `SENLER_GROUP_ID`, `SENLER_V=2`

Полная инструкция подключения для нового пользователя — `config/setup-guide.md`.

Если у пользователя нет access_token — запусти мастер:

```bash
bash ~/.claude/skills/senler/scripts/senler-oauth-setup.sh
```

Он интерактивно проведёт через все 5 шагов OAuth-flow, обменяет code на токен, сохранит .env. Запасной ручной путь описан в `config/setup-guide.md`.

## ВАЖНО: что МОЖНО и что НЕЛЬЗЯ через Senler API

### ✅ Через API ДОСТУПНО

**Чтение (полная аналитика):**
- `bots/get` — список всех воронок канала (ID, название, статус, дата создания, теги)
- `bots/getSteps <bot_id>` — структура шагов одной воронки (ID, название, тип, lead_inc)
- `subscribers/count` — общее число подписчиков
- `subscribers/get` — список подписчиков (с фильтром по боту/группе/периоду), пагинация по 100
- `subscribers/statSubscribe` — события подписок/отписок с источником
- `subscribers/statCount` — агрегаты подписок/отписок за период
- `deliveries/stat` — лог отправленных сообщений (вплоть до 2000 за один paginated запрос) с `is_read`, `error`
- `deliveries/statCount` — агрегаты по рассылкам
- `utms/statSubscribe` / `utms/statCount` — UTM-атрибуция (если UTM настроены в подписной странице)
- `groups/get` — информация о канале (имя, VK external_id, workspace_id)
- `subscribers/groups/get` — список тегов/групп подписчиков

**Управление подписчиками (write):**
- `subscribers/add` — добавить нового подписчика
- `subscribers/setData` — обновить данные подписчика
- `subscribers/setGroup` — присвоить тег / группу подписчику
- `subscribers/groups/create` — создать новую группу/тег для сегментации
- `bots/addSubscriber <bot_id>` — запустить подписчика по конкретной воронке
- `bots/delSubscriber <bot_id>` — выкинуть подписчика из конкретной воронки

### ❌ Через API НЕДОСТУПНО (только в UI Senler)

- ❌ Создавать новых ботов / воронок (нет `bots/create`)
- ❌ Редактировать шаги в существующих ботах — нельзя изменить текст сообщения, кнопки, триггеры (нет `bots/setSteps`, `bots/updateStep`)
- ❌ Создавать / редактировать рассылки (нет `broadcasts/create`, `deliveries/create`)
- ❌ Создавать триггеры на события сообщества
- ❌ Читать **точный текст** сообщения внутри шага — API возвращает только название шага и его тип, не контент

### Реальный сценарий использования

AI читает данные → находит проблемное место (молчуны, отписавшиеся, не дошедшие до продажи) → создаёт им тег через `subscribers/groups/create` + `subscribers/setGroup` → пользователь в UI Senler запускает re-engagement рассылку по этому тегу → AI читает результат и сравнивает с предыдущим.

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
# 1. Найти подписчиков
bash scripts/senler-call.sh subscribers/get bot_id=123 step_id=abc count=100

# 2. Создать тег
bash scripts/senler-call.sh subscribers/groups/create name="Молчуны после шага N"

# 3. Присвоить найденным
bash scripts/senler-call.sh subscribers/setGroup vk_user_id=123456 group_id=NEW_TAG_ID
```

### «Что-то нестандартное (метод не из списка)»
```bash
bash ~/.claude/skills/senler/scripts/senler-call.sh <ANY_METHOD> param=value
```

`senler-call.sh` — универсальный raw-вызов любого Senler API метода с уже подставленным auth.

## Ограничения

- **Лимит count:** максимум 100 на запрос. Для больших выгрузок (1000+ подписчиков) пагинируем через `offset`.
- **Один токен = один канал.** Если у пользователя несколько каналов в Senler — токен на каждый отдельно. В `.env` за раз один.
- **Токен бессрочный** (живёт до отзыва пользователем), `client_secret` нужен только при первичном обмене кода на токен.
- **Rate limit** — Senler не публикует, скилл ставит задержку ~0.35с между запросами. Для больших выгрузок (10К+ подписчиков) использует пагинацию.
- **Текст сообщений в шагах НЕ доступен** — только название и тип шага.

## Файлы скилла

```
~/.claude/skills/senler/
├── SKILL.md                              # этот файл
├── config/
│   ├── .env.example                      # шаблон конфига
│   ├── .env                              # реальный конфиг (gitignored)
│   └── setup-guide.md                    # пошаговая инструкция подключения
├── scripts/
│   ├── _common.sh                        # обёртка POST → senler.ru/api/
│   ├── senler-subscribers-count.sh       # sanity-check + total subs
│   ├── senler-bots-list.sh               # все воронки канала
│   ├── senler-bot-steps.sh               # шаги одной воронки
│   ├── senler-subscribers-list.sh        # пагинация подписчиков
│   ├── senler-utms-stats.sh              # UTM-источники
│   ├── senler-deliveries-stat.sh         # статистика рассылок
│   └── senler-call.sh                    # raw-вызов любого метода
└── cache/                                # кеш (если используется)
```

## Связанная документация

- API Senler: https://help.senler.ru/senler/help/razrabotchikam/api
- Methods reference: https://help.senler.ru/senler/help/razrabotchikam/api/methods/boty
- OAuth flow: https://help.senler.ru/senler/help/razrabotchikam/prilozheniya/varianty-integracii/oauth
