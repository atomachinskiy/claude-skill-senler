#!/usr/bin/env bash
# senler-key-setup.sh — мастер подключения Senler по ключу API (основной способ с 27.10.2026).
#
# Ключ создаётся в кабинете Senler: канал → «Настройки» → «Работа с API».
# Приложение и OAuth не нужны. Мастер спрашивает ключ (скрытый ввод) и ID канала,
# проверяет их запросом groups/get и пишет config/.env.
#
# AI-ассистент НЕ запускает этот скрипт напрямую через Bash tool: ключ попал бы
# в транскрипт. Запуск только в отдельном окне через senler-launch-wizard.sh.

set -u

SKILL_DIR="$HOME/.claude/skills/senler"
ENV_FILE="$SKILL_DIR/config/.env"
API="${SENLER_API_BASE:-https://senler.ru/api}"

C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'

ok()   { echo "${C_GREEN}[✓]${C_RESET} $*"; }
warn() { echo "${C_YELLOW}[!]${C_RESET} $*"; }
die()  { echo "${C_RED}[x]${C_RESET} $*"; echo; read -r -p "Нажмите Enter, чтобы закрыть окно" _; exit 1; }

command -v curl >/dev/null 2>&1 || die "Нет curl."
command -v jq   >/dev/null 2>&1 || die "Нет jq. Mac: brew install jq. Windows: winget install --id jqlang.jq -e"
[ -d "$SKILL_DIR" ] || die "Нет папки скилла $SKILL_DIR"

echo
echo "${C_CYAN}═══════════════════════════════════════════════════${C_RESET}"
echo "${C_CYAN}  Senler: подключение по ключу API${C_RESET}"
echo "${C_CYAN}═══════════════════════════════════════════════════${C_RESET}"
echo
echo "1. Откройте senler.ru и нужный канал."
echo "2. «Настройки» → «Работа с API» → создайте ключ и скопируйте его."
echo
echo "Ключ вводится только здесь, в чат агенту его не пишите."
echo

# group_id в API можно передать по-разному: ID канала в Senler, ID сообщества ВК,
# ID бота Telegram или МАКС. Пробуем все и берём настоящий group_id из ответа.
try_group() {
  # $1 key, $2 id → печатает JSON ответа groups/get, который сработал, иначе последний
  _key="$1"; _id="$2"; _last=""
  for _param in group_id vk_group_id tg_bot_id max_bot_id; do
    _resp=$(curl -s --max-time 30 -X POST \
      --data-urlencode "access_token=$_key" \
      --data-urlencode "$_param=$_id" \
      --data "v=2" "$API/groups/get")
    _last="$_resp"
    if [ "$(echo "$_resp" | jq -r '.success // false' 2>/dev/null)" = "true" ]; then
      echo "$_resp"; return 0
    fi
    _code=$(echo "$_resp" | jq -r '.error_code // empty' 2>/dev/null)
    # 13/14 — дело в ключе, перебирать дальше смысла нет
    if [ "$_code" = "13" ] || [ "$_code" = "14" ]; then
      echo "$_resp"; return 1
    fi
    sleep 0.2
  done
  echo "$_last"; return 1
}

parse_id() {
  # ссылка vk.com/club123, public123, пост wall-123_45, ?group_id=123, число, ID бота из токена
  _s=$(printf '%s' "$1" | tr -d '[:space:]')
  case "$_s" in
    *club[0-9]*|*public[0-9]*) printf '%s' "$_s" | sed -E 's/.*(club|public)([0-9]+).*/\2/' ;;
    *wall-[0-9]*)              printf '%s' "$_s" | sed -E 's/.*wall-([0-9]+).*/\1/' ;;
    *group_id=[0-9]*)          printf '%s' "$_s" | sed -E 's/.*group_id=([0-9]+).*/\1/' ;;
    [0-9]*:*)                  printf '%s' "${_s%%:*}" ;;
    *)                         printf '%s' "$_s" | tr -cd '0-9' ;;
  esac
}

KEY=""; GROUP_JSON=""
attempt=0
while [ $attempt -lt 3 ]; do
  attempt=$((attempt + 1))
  if [ -z "$KEY" ]; then
    read -r -s -p "Ключ API (ввод скрыт, вставьте и нажмите Enter): " KEY || die "Ввод прервался."; echo
    KEY=$(printf '%s' "$KEY" | tr -d '[:space:]')
    [ -n "$KEY" ] || { warn "Пусто. Вставьте ключ ещё раз."; attempt=$((attempt - 1)); continue; }
  fi
  echo
  echo "ID канала. Подойдёт любое из:"
  echo "  • ID сообщества ВКонтакте: число из ссылки vk.com/club123456, сама ссылка или ссылка на пост;"
  echo "  • ID канала в Senler: число из адресной строки кабинета;"
  echo "  • для канала в Telegram: ID бота, первые цифры токена бота до двоеточия."
  read -r -p "ID канала: " RAW_ID || die "Ввод прервался."
  CH_ID=$(parse_id "$RAW_ID")
  [ -n "$CH_ID" ] || { warn "Не вижу в этом числа. Нужен числовой ID."; attempt=$((attempt - 1)); continue; }

  echo "Проверяю..."
  if GROUP_JSON=$(try_group "$KEY" "$CH_ID"); then
    break
  fi
  CODE=$(echo "$GROUP_JSON" | jq -r '.error_code // empty' 2>/dev/null)
  case "$CODE" in
    13|14) warn "Ключ не подошёл. Скопируйте его целиком ещё раз из «Работа с API»."; KEY="" ;;
    6|7)   warn "Для этого ключа канал с ID $CH_ID не нашёлся. Проверьте ID и что ключ скопирован целиком."
           read -r -p "Ввести ключ заново? [y/N] " AGAIN
           case "$AGAIN" in y|Y|д|Д) KEY="" ;; esac ;;
    9)     warn "Senler просит подождать: слишком много запросов. Пробую ещё раз."; sleep 2 ;;
    *)     warn "Senler ответил: $(echo "$GROUP_JSON" | jq -r '.error_message // "нет ответа, проверьте интернет и VPN"' 2>/dev/null)" ;;
  esac
  GROUP_JSON=""
done

[ -n "$GROUP_JSON" ] || die "Не получилось за 3 попытки. Пришлите агенту скрин страницы «Работа с API» (без самого ключа)."

GROUP_ID=$(echo "$GROUP_JSON" | jq -r '.item.group_id')
CH_NAME=$(echo "$GROUP_JSON" | jq -r '.item.name // ""')
CH_TYPE=$(echo "$GROUP_JSON" | jq -r '.item.type_name // ""')
ok "Канал найден: ${CH_NAME:-без названия} (${CH_TYPE:-?}), ID в Senler $GROUP_ID"

mkdir -p "$(dirname "$ENV_FILE")"
umask 077
{
  echo "SENLER_ACCESS_TOKEN=$KEY"
  echo "SENLER_GROUP_ID=$GROUP_ID"
  echo "SENLER_V=2"
  echo "SENLER_CHANNEL_NAME=\"$(printf '%s' "$CH_NAME" | tr -d '"$`\\')\""
} > "$ENV_FILE"
chmod 600 "$ENV_FILE" 2>/dev/null || true
ok "Сохранено, доступ только у вас."

COUNT=$(curl -s --max-time 30 -X POST \
  --data-urlencode "access_token=$KEY" --data "group_id=$GROUP_ID&v=2" \
  "$API/subscribers/count" | jq -r '.count // empty' 2>/dev/null)
[ -n "$COUNT" ] && ok "Подписчиков в канале: $COUNT"

echo
echo "${C_GREEN}═══════════════════════════════════════════════════${C_RESET}"
echo "${C_GREEN}  Senler настроен. Напишите агенту «готово».${C_RESET}"
echo "${C_GREEN}═══════════════════════════════════════════════════${C_RESET}"
echo
read -r -p "Нажмите Enter, чтобы закрыть окно" _
