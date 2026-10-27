# Senler API — подключение

> Обновлено 27.10.2026. Основной способ теперь ключ API из настроек канала: приложение и OAuth не нужны.
> Старый адрес возврата `https://oauth.senler.ru/blank.html` больше не работает: домена `oauth.senler.ru` нет, Senler отвечает «Неверный адрес».

## Быстрый путь: мастер по ключу API (2–3 минуты)

1. В Senler откройте нужный канал → «Настройки» → «Работа с API» → создайте ключ. На канал можно до 20 ключей.
2. Запустите мастер в отдельном окне терминала, чтобы ключ не попал в чат с ИИ:
   - macOS / Linux: `bash ~/.claude/skills/senler/scripts/senler-launch-wizard.sh`
   - Windows (PowerShell): `powershell -ExecutionPolicy Bypass -File "$HOME\.claude\skills\senler\scripts\senler-launch-wizard.ps1"`
3. В окне вставьте ключ (ввод скрыт) и ID канала. Подойдёт любое из:
   - ID сообщества ВКонтакте: число из ссылки `vk.com/club123456`, можно вставить ссылку целиком;
   - ID канала в Senler;
   - для канала в Telegram: ID бота, цифры токена бота до двоеточия.
4. Мастер сам проверит ключ запросом `groups/get`, найдёт канал, сохранит `config/.env` (права 600) и покажет число подписчиков. В конце: «Senler настроен».

API принимает канал в любом из параметров `group_id`, `vk_group_id`, `tg_bot_id`, `max_bot_id`; мастер перебирает их и записывает в `.env` настоящий `group_id` канала в Senler.

## Вручную (если мастер не запускается)

```bash
bash -c '
read -s -p "Ключ API: " KEY; echo
read -p "group_id канала в Senler: " GID
mkdir -p ~/.claude/skills/senler/config
umask 077
printf "SENLER_ACCESS_TOKEN=%s\nSENLER_GROUP_ID=%s\nSENLER_V=2\n" "$KEY" "$GID" > ~/.claude/skills/senler/config/.env
echo "saved"
'
bash ~/.claude/skills/senler/scripts/senler-subscribers-count.sh
```

Знаете только ID сообщества ВК: узнайте `group_id` так (ключ подставьте в отдельном окне):

```bash
curl -s -X POST --data-urlencode "access_token=$KEY" --data "vk_group_id=123456&v=2" https://senler.ru/api/groups/get
```

## Ошибки

| Код | Что значит | Что делать |
|---|---|---|
| 1 | Не передан канал | Нужен `group_id` (или `vk_group_id`, `tg_bot_id`, `max_bot_id`) |
| 6 | Канал не найден | Проверьте ID и что ключ от этого же канала |
| 9 | Больше 20 запросов в секунду на ключ | Повторить с задержкой |
| 13, 14 | Ключ не найден или недействителен | Создать ключ заново в «Работа с API» |

## Запасной путь: OAuth-приложение

Нужен, только если ключи API недоступны. Мастер: `senler-launch-wizard.sh --oauth` (Windows: `senler-launch-wizard.ps1 -OAuth`).

1. senler.ru → аватарка → «Разработчикам» → «Добавить приложение», отметить «Авторизация на стороннем сайте (OAuth)».
2. Адрес возврата (redirect url): любая открывающаяся страница, например адрес вашего сайта. Мастер спросит этот адрес, в приложении он должен совпадать символ в символ.
3. После «Разрешить» Senler перебросит на `ВАШ_АДРЕС?code=...&group_id=...`. Весь адрес из строки вставляется в окно мастера, он обменяет `code` на бессрочный токен (`https://senler.ru/ajax/cabinet/OAuth2token`). Код живёт 2,5 часа и одноразовый.

## После настройки

```bash
bash ~/.claude/skills/senler/scripts/senler-bots-list.sh        # боты: статус и публикация
bash ~/.claude/skills/senler/scripts/senler-bot-steps.sh 123    # шаги бота и запуски каждого шага
bash ~/.claude/skills/senler/scripts/senler-deliveries-stat.sh  # рассылки: доставлено, прочитано, переходы
bash ~/.claude/skills/senler/scripts/senler-utms-stats.sh       # метки и источники
```

Документация Senler: https://help.senler.ru/senler/help/razrabotchikam/api
