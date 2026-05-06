#!/usr/bin/env bash
# senler-oauth-setup.sh — интерактивный мастер OAuth-настройки
# Проводит пользователя через все 5 шагов: credentials → authorize → code → token → .env
#
# Usage: bash senler-oauth-setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$HOME/.claude/secrets"
APP_FILE="$SECRETS_DIR/senler-app.json"
ENV_FILE="$SKILL_DIR/config/.env"

C_RESET="\033[0m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"

echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_CYAN}  Senler API — мастер настройки OAuth${C_RESET}"
echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo ""

# --- Step 1: deps check ---
if ! command -v jq >/dev/null 2>&1; then
  echo -e "${C_RED}[!] Не найден jq. Поставь: brew install jq${C_RESET}"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo -e "${C_RED}[!] Не найден curl${C_RESET}"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${C_RED}[!] Не найден python3${C_RESET}"
  exit 1
fi

# --- Step 2: credentials ---
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [ -f "$APP_FILE" ]; then
  echo -e "${C_GREEN}[✓]${C_RESET} Найден $APP_FILE"
  read -p "Использовать существующий client_id? [Y/n] " USE_EXISTING
  if [ "$USE_EXISTING" = "n" ] || [ "$USE_EXISTING" = "N" ]; then
    rm "$APP_FILE"
  fi
fi

if [ ! -f "$APP_FILE" ]; then
  echo ""
  echo -e "${C_YELLOW}═══ Шаг 1: Создание OAuth-приложения в Senler ═══${C_RESET}"
  echo ""
  echo "1. Открой https://senler.ru → авторизуйся"
  echo "2. Аватарка справа сверху → «Разработчикам»"
  echo "3. «+ Добавить приложение»"
  echo "4. Заполни:"
  echo "   • Название: Claude AI Analyst"
  echo "   • Интеграция: ✅ «Авторизация на стороннем сайте (OAuth)»"
  echo "   • redirect_uri: https://oauth.senler.ru/blank.html"
  echo "5. «Сохранить» — увидишь client_id и client_secret"
  echo ""
  echo -e "${C_RED}[!] client_secret показывается ОДИН РАЗ — копируй сразу${C_RESET}"
  echo ""
  read -p "Введи client_id: " CLIENT_ID
  read -s -p "Введи client_secret (не отображается): " CLIENT_SECRET; echo
  REDIRECT_URI="https://oauth.senler.ru/blank.html"

  python3 -c "
import json, sys
data = {
    'client_id': '$CLIENT_ID',
    'client_secret': '$CLIENT_SECRET',
    'redirect_uri': '$REDIRECT_URI'
}
with open('$APP_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  chmod 600 "$APP_FILE"
  echo -e "${C_GREEN}[✓]${C_RESET} Сохранено в $APP_FILE (chmod 600)"
fi

# Read back credentials
CLIENT_ID=$(jq -r '.client_id' "$APP_FILE")
CLIENT_SECRET=$(jq -r '.client_secret' "$APP_FILE")
REDIRECT_URI=$(jq -r '.redirect_uri' "$APP_FILE")

# --- Step 3: authorize ---
STATE=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
ENC_REDIRECT=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$REDIRECT_URI', safe=''))")
AUTH_URL="https://senler.ru/cabinet/OAuth2authorize?client_id=${CLIENT_ID}&redirect_uri=${ENC_REDIRECT}&state=${STATE}"

echo ""
echo -e "${C_YELLOW}═══ Шаг 2: Получить авторизационный код ═══${C_RESET}"
echo ""
echo "Открой URL в браузере где залогинен в Senler:"
echo ""
echo -e "${C_CYAN}${AUTH_URL}${C_RESET}"
echo ""
echo "→ выбери канал → нажми «Разрешить»"
echo "→ перебросит на oauth.senler.ru/blank.html?code=XXXX&state=...&group_id=NNNN"
echo ""

# Try opening in browser (cross-platform: macOS/Linux/Windows-bash)
open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" 2>/dev/null && return 0      # macOS
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" 2>/dev/null && return 0  # Linux
  fi
  if command -v start >/dev/null 2>&1; then
    start "$url" 2>/dev/null && return 0     # Windows cmd
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "$url" 2>/dev/null && return 0  # WSL/Git Bash
  fi
  return 1
}

read -p "Открыть URL автоматически в браузере? [Y/n] " OPEN_AUTO
if [ "$OPEN_AUTO" != "n" ] && [ "$OPEN_AUTO" != "N" ]; then
  if ! open_url "$AUTH_URL"; then
    echo -e "${C_YELLOW}[!] Не удалось открыть автоматически — скопируй URL выше вручную${C_RESET}"
  fi
fi

echo ""
read -p "Вставь code из URL: " CODE
read -p "Вставь group_id из URL: " GROUP_ID

# --- Step 4: exchange code for token ---
echo ""
echo -e "${C_YELLOW}═══ Шаг 3: Обмен code на access_token ═══${C_RESET}"
echo ""
RESP=$(curl -s -G \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode "redirect_uri=$REDIRECT_URI" \
  --data-urlencode "code=$CODE" \
  --data-urlencode "group_id=$GROUP_ID" \
  "https://senler.ru/ajax/cabinet/OAuth2token")

TOKEN=$(echo "$RESP" | jq -r '.access_token // empty')

if [ -z "$TOKEN" ]; then
  echo -e "${C_RED}[!] Ошибка обмена. Ответ Senler:${C_RESET}"
  echo "$RESP" | jq .
  exit 1
fi

echo -e "${C_GREEN}[✓]${C_RESET} Получен access_token (${#TOKEN} символов)"

# --- Step 5: save .env ---
mkdir -p "$SKILL_DIR/config"
cat > "$ENV_FILE" <<EOF
SENLER_ACCESS_TOKEN=$TOKEN
SENLER_GROUP_ID=$GROUP_ID
SENLER_V=2
EOF
chmod 600 "$ENV_FILE"

echo -e "${C_GREEN}[✓]${C_RESET} Сохранено в $ENV_FILE (chmod 600)"

# --- Step 6: sanity-check ---
echo ""
echo -e "${C_YELLOW}═══ Шаг 4: Проверка подключения ═══${C_RESET}"
echo ""

CHECK=$(curl -s -X POST "https://senler.ru/api/subscribers/count" \
  -d "group_id=$GROUP_ID&access_token=$TOKEN&v=2")

SUBS=$(echo "$CHECK" | jq -r '.count // .items.count // empty')

if [ -n "$SUBS" ] && [ "$SUBS" != "null" ]; then
  echo -e "${C_GREEN}[✓] Работает! Подписчиков в канале: ${SUBS}${C_RESET}"
else
  echo -e "${C_RED}[!] Что-то не так. Ответ API:${C_RESET}"
  echo "$CHECK" | jq .
  exit 1
fi

# --- Done ---
echo ""
echo -e "${C_GREEN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_GREEN}  ✅ Senler настроен. Можно работать.${C_RESET}"
echo -e "${C_GREEN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo ""
echo "Дальше попроси Claude:"
echo "  • «Покажи мои воронки в Senler»"
echo "  • «Сделай аналитику моего канала Senler»"
echo "  • «Найди где люди отваливаются»"
echo ""
echo "Или вызывай скрипты напрямую:"
echo "  bash $SCRIPT_DIR/senler-bots-list.sh"
echo "  bash $SCRIPT_DIR/senler-deliveries-stat.sh"
echo "  bash $SCRIPT_DIR/senler-utms-stats.sh"
echo ""
