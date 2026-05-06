#!/bin/sh
# senler-subscribers-count.sh — sanity-check + total subscribers
# Usage: senler-subscribers-count.sh [--json]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config
eval "$(parse_flags "$@")"

DATA=$(senler_api "subscribers/count" "")

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

COUNT=$(echo "$DATA" | $JQ -r '.count // .items.count // empty')
echo "# Senler — channel: ${SENLER_CHANNEL_NAME:-(unnamed)}, group_id=${SENLER_GROUP_ID}"
echo "Subscribers: ${COUNT:-(field not found, see --json)}"
