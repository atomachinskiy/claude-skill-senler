#!/usr/bin/env bash
# senler-oauth-setup.sh — интерактивный мастер OAuth-настройки
# Проводит пользователя через все 5 шагов: credentials → authorize → code → token → .env
#
# Cross-platform: macOS / Linux / WSL / Git Bash на Windows.
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

die() { echo -e "${C_RED}[!] $*${C_RESET}" >&2; exit 1; }

echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_CYAN}  Senler API — мастер настройки OAuth${C_RESET}"
echo -e "${C_CYAN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo ""

# --- Step 0: deps check ---
command -v jq   >/dev/null 2>&1 || die "Не найден jq.   macOS: brew install jq | Linux: sudo apt install jq | Windows: см. https://stedolan.github.io/jq/download/"
command -v curl >/dev/null 2>&1 || die "Не найден curl. macOS: уже есть | Linux: sudo apt install curl | Windows: уже идёт с Git Bash"

# Find a working Python.
# На Windows `python3` часто это Microsoft Store stub: запускается, печатает "Python", выходит без действия.
# Поэтому проверяем не наличием бинарника, а реальным smoke-test (`-c "import sys"`).
detect_python() {
  for candidate in python3 python python3.12 python3.11 python3.10 "py -3"; do
    # shellcheck disable=SC2086
    if $candidate -c "import sys; sys.exit(0)" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}
PYTHON="$(detect_python)" || die "Не найден работающий Python.

  На Windows: 'python3' часто это пустышка от Microsoft Store, скачай настоящий с https://python.org → отметь 'Add Python to PATH' → перезапусти PowerShell.
  На macOS:   brew install python
  На Linux:   sudo apt install python3"

echo -e "${C_GREEN}[✓]${C_RESET} Python: $PYTHON"

# Helper: конвертация Git Bash пути (/c/Users/...) в нативный Windows (C:\Users\...) для Python.
# На macOS/Linux вернёт путь как есть.
to_native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    echo "$1"
  fi
}

# Безопасная запись JSON в файл — путь и значения передаём через argv, не через f-strings (избегаем кавычек/$).
py_write_json() {
  local target="$1"; shift
  local native_target
  native_target="$(to_native_path "$target")"
  $PYTHON - "$native_target" "$@" <<'PY'
import json, sys
path, *kvs = sys.argv[1:]
data = {}
for kv in kvs:
    if "=" in kv:
        k, v = kv.split("=", 1)
        data[k] = v
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
}

# --- Step 1: credentials ---
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR" 2>/dev/null || true

if [ -f "$APP_FILE" ]; then
  echo -e "${C_GREEN}[✓]${C_RESET} Найден $APP_FILE"
  read -r -p "Использовать существующий client_id? [Y/n] " USE_EXISTING
  case "$USE_EXISTING" in
    n|N|no|No) rm "$APP_FILE" ;;
  esac
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
  read -r -p "Введи client_id: " CLIENT_ID
  read -r -s -p "Введи client_secret (не отображается): " CLIENT_SECRET; echo
  REDIRECT_URI="https://oauth.senler.ru/blank.html"

  py_write_json "$APP_FILE" \
    "client_id=$CLIENT_ID" \
    "client_secret=$CLIENT_SECRET" \
    "redirect_uri=$REDIRECT_URI"
  chmod 600 "$APP_FILE" 2>/dev/null || true
  echo -e "${C_GREEN}[✓]${C_RESET} Сохранено в $APP_FILE (chmod 600)"
fi

# Read back credentials
CLIENT_ID=$(jq -r '.client_id' "$APP_FILE")
CLIENT_SECRET=$(jq -r '.client_secret' "$APP_FILE")
REDIRECT_URI=$(jq -r '.redirect_uri' "$APP_FILE")

# --- Step 2: build authorize URL ---
STATE=$($PYTHON -c "import secrets; print(secrets.token_urlsafe(16))")
ENC_REDIRECT=$($PYTHON -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$REDIRECT_URI")
AUTH_URL="https://senler.ru/cabinet/OAuth2authorize?client_id=${CLIENT_ID}&redirect_uri=${ENC_REDIRECT}&state=${STATE}"

echo ""
echo -e "${C_YELLOW}═══ Шаг 2: Получить авторизационный код ═══${C_RESET}"
echo ""
echo "Открой URL в браузере где залогинен в Senler (если в РФ — может понадобиться VPN, Senler иногда блокируется некоторыми провайдерами):"
echo ""
echo -e "${C_CYAN}${AUTH_URL}${C_RESET}"
echo ""
echo "→ выбери канал → нажми «Разрешить»"
echo "→ перебросит на страницу oauth.senler.ru/blank.html?code=XXXX&state=...&group_id=NNNN"
echo "→ сама страница может быть пустой — нужен только URL из адресной строки"
echo ""
echo -e "${C_RED}[!] code в URL ОДНОРАЗОВЫЙ и быстро устаревает.${C_RESET}"
echo "    Когда увидишь URL с code= и group_id= — скопируй их и сразу вставь сюда."
echo "    Если получишь 'Wrong authCode' — открой URL заново для нового code."
echo ""

# Try opening in browser
open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 && return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 && return 0
  fi
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process \"$url\"" >/dev/null 2>&1 && return 0
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$url" >/dev/null 2>&1 && return 0
  fi
  if command -v start >/dev/null 2>&1; then
    start "$url" >/dev/null 2>&1 && return 0
  fi
  return 1
}

read -r -p "Открыть URL автоматически в браузере? [Y/n] " OPEN_AUTO
case "$OPEN_AUTO" in
  n|N|no|No) ;;
  *)
    if ! open_url "$AUTH_URL"; then
      echo -e "${C_YELLOW}[!] Не удалось открыть автоматически — скопируй URL выше и открой руками${C_RESET}"
    fi
    ;;
esac

echo ""
echo "После «Разрешить» Senler перебросит тебя на страницу — она может выглядеть пустой."
echo "В адресной строке будет URL вида:"
echo "    https://oauth.senler.ru/blank.html?code=XXXX&state=...&group_id=NNNN"
echo ""
echo -e "${C_CYAN}Скопируй ВЕСЬ этот URL целиком (Ctrl+L → Ctrl+C на странице) и вставь сюда:${C_RESET}"
read -r -p "URL: " REDIRECT_URL

# Парсим code и group_id из URL автоматически.
# Поддерживаем и случай когда пользователь вставил только code или только параметры.
parse_url_param() {
  local url="$1" key="$2"
  echo "$url" | $PYTHON -c "
import sys, urllib.parse
url = sys.stdin.read().strip()
qs = urllib.parse.urlparse(url).query if '?' in url else url
params = urllib.parse.parse_qs(qs)
v = params.get('$key', [''])[0]
print(v)
"
}

CODE="$(parse_url_param "$REDIRECT_URL" code)"
GROUP_ID="$(parse_url_param "$REDIRECT_URL" group_id)"

# Если URL не содержал параметров — fallback на ручной ввод
if [ -z "$CODE" ]; then
  echo -e "${C_YELLOW}[!] Не нашёл code= в URL. Вставь вручную:${C_RESET}"
  read -r -p "code: " CODE
fi
if [ -z "$GROUP_ID" ]; then
  echo -e "${C_YELLOW}[!] Не нашёл group_id= в URL. Вставь вручную:${C_RESET}"
  read -r -p "group_id: " GROUP_ID
fi

echo -e "${C_GREEN}[✓]${C_RESET} code=${CODE:0:8}... group_id=${GROUP_ID}"

# --- Step 3: exchange code for token (immediately, no delay) ---
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
  ERR_MSG=$(echo "$RESP" | jq -r '.message // .error // empty')
  echo -e "${C_RED}[!] Ошибка обмена. Ответ Senler:${C_RESET}"
  echo "$RESP" | jq .
  echo ""
  case "$ERR_MSG" in
    *Wrong*authCode*|*"Wrong authCode"*)
      echo -e "${C_YELLOW}Это значит что code из URL уже использован или истёк.${C_RESET}"
      echo "Открой URL ещё раз → «Разрешить» → возьми СВЕЖИЙ code из адресной строки и перезапусти этот мастер."
      ;;
    *)
      echo -e "${C_YELLOW}Проверь:${C_RESET}"
      echo "  • client_id и client_secret скопированы без пробелов"
      echo "  • code и group_id взяты из СВЕЖЕГО URL после «Разрешить»"
      echo "  • redirect_uri в приложении Senler ровно: https://oauth.senler.ru/blank.html"
      ;;
  esac
  exit 1
fi

echo -e "${C_GREEN}[✓]${C_RESET} Получен access_token (${#TOKEN} символов)"

# --- Step 4: save .env ---
mkdir -p "$SKILL_DIR/config"
cat > "$ENV_FILE" <<EOF
SENLER_ACCESS_TOKEN=$TOKEN
SENLER_GROUP_ID=$GROUP_ID
SENLER_V=2
EOF
chmod 600 "$ENV_FILE" 2>/dev/null || true

echo -e "${C_GREEN}[✓]${C_RESET} Сохранено в $ENV_FILE (chmod 600)"

# --- Step 5: sanity-check ---
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
