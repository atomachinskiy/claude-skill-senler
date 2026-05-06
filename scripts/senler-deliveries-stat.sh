#!/bin/sh
# senler-deliveries-stat.sh — broadcasts statistics
# Usage: senler-deliveries-stat.sh [--json]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config
eval "$(parse_flags "$@")"

DATA=$(senler_api "deliveries/stat" "")

if [ "$OUTPUT_JSON" -eq 1 ]; then
  echo "$DATA" | $JQ .
  exit 0
fi

SUCCESS=$(echo "$DATA" | $JQ -r '.success')
[ "$SUCCESS" != "true" ] && { echo "$DATA" | $JQ . >&2; exit 1; }

{
  echo "# Deliveries / broadcasts stats"
  echo ""
  echo "$DATA" | $JQ -r '
    (.items // []) | to_entries[] |
    "\(.value.delivery_id // .value.id // "?")|\(.value.name // .value.title // "Untitled")|\(.value.sent_count // 0)|\(.value.read_count // 0)|\(.value.click_count // 0)"
  ' | while IFS='|' read -r id name sent read click; do
    echo "[${id}] ${name}  sent=${sent}  read=${read}  click=${click}"
  done
} | limit_output
