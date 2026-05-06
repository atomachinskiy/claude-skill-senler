#!/bin/sh
# senler-subscribers-list.sh — list subscribers (paginated)
# Usage: senler-subscribers-list.sh [--bot BOT_ID] [--count N] [--offset N] [--json] [--full]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config

BOT_ID=""
COUNT=50
OFFSET=0
ARGS=""
prev=""
for a in "$@"; do
  case "$prev" in
    --bot)    BOT_ID="$a"; prev=""; continue ;;
    --count)  COUNT="$a"; prev=""; continue ;;
    --offset) OFFSET="$a"; prev=""; continue ;;
  esac
  case "$a" in
    --bot|--count|--offset) prev="$a" ;;
    *) ARGS="$ARGS $a" ;;
  esac
done
eval "$(parse_flags $ARGS)"

PARAMS="count=${COUNT}&offset=${OFFSET}"
[ -n "$BOT_ID" ] && PARAMS="${PARAMS}&bot_id=${BOT_ID}"

DATA=$(senler_api "subscribers/get" "$PARAMS")

if [ "$OUTPUT_JSON" -eq 1 ]; then
  echo "$DATA" | $JQ .
  exit 0
fi

SUCCESS=$(echo "$DATA" | $JQ -r '.success')
if [ "$SUCCESS" != "true" ]; then
  echo "Failed. Raw response:" >&2
  echo "$DATA" | $JQ . >&2
  exit 1
fi

{
  N=$(echo "$DATA" | $JQ -r '(.items // .subscribers // []) | length')
  echo "# Subscribers (showing ${N} from offset=${OFFSET})${BOT_ID:+, bot=${BOT_ID}}"
  echo ""
  echo "$DATA" | $JQ -r '
    (.items // .subscribers // []) | to_entries[] |
    "\(.key + 1 + '"$OFFSET"')|\(.value.subscriber_id // .value.id // "?")|\(.value.vk_user_id // .value.user_id // "?")|\(.value.name // .value.first_name // "")|\(.value.last_name // "")|\(.value.subscribe_date // .value.date_subscribe // "?")"
  ' | while IFS='|' read -r num sid vk first last date; do
    echo "${num}. [${sid}] vk=${vk}  ${first} ${last}  —  ${date}"
  done
} | limit_output
