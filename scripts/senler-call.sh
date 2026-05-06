#!/bin/sh
# senler-call.sh — generic raw API invoker for ad-hoc method probing
# Usage: senler-call.sh <METHOD> [param1=val1] [param2=val2] ...
# Examples:
#   senler-call.sh subscribers/count
#   senler-call.sh bots/get count=10
#   senler-call.sh subscribers/get bot_id=123 count=5
#   senler-call.sh utms/statSubscribe date_from=2026-04-01 date_to=2026-04-30

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

load_config

METHOD="$1"
shift

if [ -z "$METHOD" ]; then
  echo "Usage: senler-call.sh <METHOD> [param1=val1] [param2=val2] ..." >&2
  echo "  Methods: subscribers/count, subscribers/get, bots/get, bots/getSteps," >&2
  echo "           utms/statSubscribe, deliveries/stat, etc." >&2
  exit 1
fi

PARAMS=""
for arg in "$@"; do
  if [ -n "$PARAMS" ]; then
    PARAMS="$PARAMS&$arg"
  else
    PARAMS="$arg"
  fi
done

senler_api "$METHOD" "$PARAMS" | $JQ .
