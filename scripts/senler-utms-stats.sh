#!/bin/sh
# senler-utms-stats.sh — UTM-source attribution for subscribes
# Usage: senler-utms-stats.sh [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config

FROM=""
TO=""
ARGS=""
prev=""
for a in "$@"; do
  case "$prev" in
    --from) FROM="$a"; prev=""; continue ;;
    --to)   TO="$a"; prev=""; continue ;;
  esac
  case "$a" in
    --from|--to) prev="$a" ;;
    *) ARGS="$ARGS $a" ;;
  esac
done
eval "$(parse_flags $ARGS)"

PARAMS=""
[ -n "$FROM" ] && PARAMS="date_from=${FROM}"
[ -n "$TO" ]   && PARAMS="${PARAMS}${PARAMS:+&}date_to=${TO}"

DATA=$(senler_api "utms/statSubscribe" "$PARAMS")

if [ "$OUTPUT_JSON" -eq 1 ]; then
  echo "$DATA" | $JQ .
  exit 0
fi

SUCCESS=$(echo "$DATA" | $JQ -r '.success')
[ "$SUCCESS" != "true" ] && { echo "$DATA" | $JQ . >&2; exit 1; }

{
  echo "# UTM stats — subscribes${FROM:+ from ${FROM}}${TO:+ to ${TO}}"
  echo ""
  echo "$DATA" | $JQ -r '
    (.items // []) | to_entries[] |
    "\(.value.utm_source // "—")|\(.value.utm_medium // "—")|\(.value.utm_campaign // "—")|\(.value.subscribe_count // .value.count // 0)"
  ' | sort -t'|' -k4 -rn | while IFS='|' read -r src med camp cnt; do
    printf "%5d  src=%s  medium=%s  camp=%s\n" "$cnt" "$src" "$med" "$camp"
  done
} | limit_output
