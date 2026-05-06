#!/bin/sh
# senler-bot-steps.sh — list steps (questions) of one bot scenario
# Usage: senler-bot-steps.sh <bot_id> [--json] [--full]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config
eval "$(parse_flags "$@")"

BOT_ID=$(echo "$POSITIONAL_ARGS" | awk '{print $1}')
if [ -z "$BOT_ID" ]; then
  echo "Usage: senler-bot-steps.sh <bot_id> [--json] [--full]" >&2
  echo "Get bot_id via: senler-bots-list.sh" >&2
  exit 1
fi

DATA=$(senler_api "bots/getSteps" "bot_id=${BOT_ID}")

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
  echo "# Bot ${BOT_ID} — funnel steps"
  echo ""
  echo "$DATA" | $JQ -r '
    (.items // .steps // []) | to_entries[] |
    "\(.key + 1)|\(.value.step_id // .value.id // "?")|\(.value.name // .value.title // .value.text // "Untitled" | gsub("\n"; " ") | .[0:80])|\(.value.subscribers_count // "?")"
  ' | while IFS='|' read -r num id name subs; do
    echo "${num}. [${id}] ${name}  —  на шаге: ${subs}"
  done
} | limit_output
