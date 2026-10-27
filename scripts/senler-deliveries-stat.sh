#!/bin/sh
# senler-deliveries-stat.sh — рассылки канала со статистикой (deliveries/get)
# Usage: senler-deliveries-stat.sh [--count N] [--json] [--full]
# Поля по документации Senler API v2: count_recipients, count_send, count_error,
# count_read, count_transits, count_unsubscribers.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config

COUNT=50
ARGS=""
prev=""
for a in "$@"; do
  case "$prev" in
    --count) COUNT="$a"; prev=""; continue ;;
  esac
  case "$a" in
    --count) prev="$a" ;;
    *) ARGS="$ARGS $a" ;;
  esac
done
eval "$(parse_flags $ARGS)"

DATA=$(senler_api "deliveries/get" "count=${COUNT}")

if [ "$OUTPUT_JSON" -eq 1 ]; then
  echo "$DATA" | $JQ .
  exit 0
fi

SUCCESS=$(echo "$DATA" | $JQ -r '.success')
[ "$SUCCESS" != "true" ] && { echo "$DATA" | $JQ . >&2; exit 1; }

{
  echo "# Рассылки канала ${SENLER_CHANNEL_NAME:-} (всего $(echo "$DATA" | $JQ -r '.count // "?"'))"
  echo "# получатели / доставлено / ошибки / прочитано / переходы / отписки"
  echo ""
  echo "$DATA" | $JQ -r '
    (.items // [])[] |
    (if (.count_send // 0) > 0 then ((.count_read // 0) * 100 / .count_send | floor | tostring) + "%" else "—" end) as $rr |
    "[\(.delivery_id)] \(.name // "без названия") (\(.type // "?"), \(.status // "?"), \(.date // ""))  —  \(.count_recipients // 0) / \(.count_send // 0) / \(.count_error // 0) / \(.count_read // 0) (\($rr)) / \(.count_transits // 0) / \(.count_unsubscribers // 0)"
  '
} | limit_output
