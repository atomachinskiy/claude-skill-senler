# Senler API — пошаговая инструкция подключения

> Эта инструкция превращает «у меня есть Senler-канал» в «AI читает мою аналитику».
> Занимает 5-7 минут.

## 🚀 Быстрый путь — мастер настройки

В терминале:

```bash
bash ~/.claude/skills/senler/scripts/senler-oauth-setup.sh
```

Мастер интерактивно проведёт через все шаги: подскажет где создать OAuth-приложение в Senler, спросит client_id/secret, откроет страницу авторизации в браузере, обменяет code на access_token и сохранит конфиг.

Если что-то пошло не так или хочется сделать всё руками — пошаговая инструкция ниже.

---

## Ручной способ (если мастер недоступен)

## Шаг 1 — Войти в кабинет Senler

Открой `https://senler.ru` и авторизуйся под админ-аккаунтом канала.

## Шаг 2 — Создать OAuth-приложение

В правом верхнем углу клик по аватарке → **«Разработчикам»**.

Откроется раздел «Приложения». Кликни **«+ Добавить приложение»**.

Заполни форму:
- **Название:** `Claude AI Analyst` (или любое запоминаемое)
- **Описание:** `AI-аналитик и сегментатор подписчиков` (не критично)
- **Интеграция:** ✅ поставить галку **«Авторизация на стороннем сайте (OAuth)»**
- **redirect_uri:** `https://oauth.senler.ru/blank.html`
- **Категория:** `Аналитика`

Нажми **«Сохранить»**.

После сохранения Senler покажет два значения:
- `client_id` — длинная hex-строка
- `client_secret` — ещё одна длинная hex-строка

⚠️ **`client_secret` показывается один раз** — скопируй его сразу.

## Шаг 3 — Сохранить credentials в файл

В терминале (любая ОС с bash):

```bash
bash -c '
mkdir -p ~/.claude/secrets
read -p "client_id: " CID
read -s -p "client_secret: " CS; echo
read -p "redirect_uri (то что указали в форме Senler): " RU
printf "{\"client_id\":\"%s\",\"client_secret\":\"%s\",\"redirect_uri\":\"%s\"}\n" "$CID" "$CS" "$RU" > ~/.claude/secrets/senler-app.json
chmod 600 ~/.claude/secrets/senler-app.json
echo "✅ saved"
'
```

Команда спросит три значения по очереди. `client_secret` вводится скрыто (не отображается на экране).

После выполнения файл `~/.claude/secrets/senler-app.json` будет содержать твои креденшелы (права 600 — только владелец может читать).

## Шаг 4 — Открыть authorize-страницу

Скопируй URL ниже и подставь свой `client_id` (тот что видел на форме):

```
https://senler.ru/cabinet/OAuth2authorize?client_id=ТВОЙ_CLIENT_ID&redirect_uri=https%3A%2F%2Foauth.senler.ru%2Fblank.html&state=any-random-string
```

Открой в браузере где ты залогинен в Senler. Там покажет:
- Название твоего приложения
- Запрос разрешений
- Дропдаун для выбора **канала** к которому даёшь доступ

Выбери нужный канал (тот, аналитику которого хочешь смотреть) → нажми **«Разрешить»**.

После разрешения тебя перебросит на `oauth.senler.ru/blank.html?code=XXXX&state=...&group_id=NNNN`.

Из адресной строки нужны два значения:
- `code` — длинная строка между `code=` и `&state`
- `group_id` — число в конце URL

## Шаг 5 — Обменять code на access_token

В терминале:

```bash
bash -c '
read -p "code (из URL): " CODE
read -p "group_id (из URL, цифра): " GID
APP=$(cat ~/.claude/secrets/senler-app.json)
CID=$(echo "$APP" | python3 -c "import json,sys;print(json.load(sys.stdin)[\"client_id\"])")
CS=$(echo "$APP" | python3 -c "import json,sys;print(json.load(sys.stdin)[\"client_secret\"])")
RU=$(echo "$APP" | python3 -c "import json,sys;print(json.load(sys.stdin)[\"redirect_uri\"])")
RESP=$(curl -s -G \
    --data-urlencode "client_id=$CID" \
    --data-urlencode "client_secret=$CS" \
    --data-urlencode "redirect_uri=$RU" \
    --data-urlencode "code=$CODE" \
    --data-urlencode "group_id=$GID" \
    "https://senler.ru/ajax/cabinet/OAuth2token")
TOKEN=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin)[\"access_token\"])")
mkdir -p ~/.claude/skills/senler/config
cat > ~/.claude/skills/senler/config/.env <<EOF
SENLER_ACCESS_TOKEN=$TOKEN
SENLER_GROUP_ID=$GID
SENLER_V=2
EOF
chmod 600 ~/.claude/skills/senler/config/.env
echo "✅ access_token saved to senler/config/.env"
'
```

Команда автоматически:
1. Прочитает credentials из `~/.claude/secrets/senler-app.json`
2. Обменяет `code` на `access_token` через Senler API
3. Сохранит токен и `group_id` в `~/.claude/skills/senler/config/.env`

## Шаг 6 — Проверка

```bash
bash ~/.claude/skills/senler/scripts/senler-subscribers-count.sh
```

Должно вернуть число подписчиков канала. Если вернулось — всё работает.

## После настройки

Дальше можно использовать любой скрипт из скилла:

```bash
bash ~/.claude/skills/senler/scripts/senler-bots-list.sh        # карта воронок
bash ~/.claude/skills/senler/scripts/senler-bot-steps.sh 123    # шаги воронки
bash ~/.claude/skills/senler/scripts/senler-deliveries-stat.sh  # рассылки
bash ~/.claude/skills/senler/scripts/senler-utms-stats.sh       # UTM-источники
```

Или попросить Claude:
- «Проанализируй мой Senler канал»
- «Покажи где люди отваливаются в воронке X»
- «Найди молчунов на шаге N и поставь им тег»

## Восстановление при проблемах

| Симптом | Причина | Решение |
|---|---|---|
| `Miss group_id` | В config/.env нет `SENLER_GROUP_ID` | Перепроверить .env |
| `Invalid code` | Code просрочен (живёт 2.5 часа) | Заново сделать шаг 4-5 |
| `Token has been expired` | Токен отозван пользователем | Сделать шаг 4-5 заново |
| `Permission denied` | Скрипт не executable | `chmod +x ~/.claude/skills/senler/scripts/*.sh` |

## Безопасность

- `~/.claude/secrets/senler-app.json` (`client_secret`) — НЕ передавать никому, не коммитить, не публиковать
- `~/.claude/skills/senler/config/.env` (`access_token`) — то же самое
- Оба файла должны быть `chmod 600` (только владелец читает)
- Если токен утёк — отозвать его в кабинете Senler (Разработчикам → Приложения → выбрать → Отозвать доступ), и заново пройти шаги 4-5

## Связанные ссылки

- Senler API docs: https://help.senler.ru/senler/help/razrabotchikam/api
- OAuth flow docs: https://help.senler.ru/senler/help/razrabotchikam/prilozheniya/varianty-integracii/oauth
- Methods reference: https://help.senler.ru/senler/help/razrabotchikam/api/methods/boty
