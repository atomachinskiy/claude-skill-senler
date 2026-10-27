#!/bin/sh
# senler-bots-list.sh — list all bot scenarios in the channel
# Usage: senler-bots-list.sh [--json] [--full]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config
eval "$(parse_flags "$@")"

DATA=$(senler_api "bots/get" "count=100")

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

# Senler API may put list under .items or .bots — try both
N=$(echo "$DATA" | $JQ -r '(.items // .bots // []) | length')

{
  echo "# Senler bots — channel: ${SENLER_CHANNEL_NAME:-(unnamed)}, group_id=${SENLER_GROUP_ID}"
  echo "# Found ${N} bot scenarios"
  echo ""

  echo "$DATA" | $JQ -r '
    (.items // .bots // []) | to_entries[] |
    "\(.key + 1)|\(.value.bot_id // .value.id // "?")|\(.value.title // .value.name // "Untitled")|\(if .value.active == 1 then "запущен" elif .value.active == 0 then "остановлен" else "?" end)|\(if .value.published == 0 then ", есть неопубликованные изменения" else "" end)|\(.value.date // "")"
  ' | while IFS='|' read -r num id name status pub date; do
    echo "${num}. [${id}] ${name}  —  ${status}${pub}  (создан ${date})"
  done
} | limit_output
