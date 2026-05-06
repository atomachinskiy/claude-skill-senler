#!/bin/sh
# _common.sh — shared module for Senler skill
# Sourced by all other scripts. Provides config, API wrapper, output limiting.

# ── Paths ──────────────────────────────────────────────────────────
SKILL_DIR="$HOME/.claude/skills/senler"
CONFIG_FILE="$SKILL_DIR/config/.env"
CACHE_DIR="$SKILL_DIR/cache"
JQ="$(command -v jq || echo /usr/local/bin/jq)"

# ── Globals (set by parse_flags) ───────────────────────────────────
OUTPUT_FULL=0
OUTPUT_JSON=0

# ── Config loader ──────────────────────────────────────────────────
load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config not found: $CONFIG_FILE" >&2
    echo "Run: cp $SKILL_DIR/config/.env.example $CONFIG_FILE  (then fill it in)" >&2
    exit 1
  fi
  set -a
  . "$CONFIG_FILE"
  set +a

  if [ -z "$SENLER_ACCESS_TOKEN" ]; then
    echo "ERROR: SENLER_ACCESS_TOKEN not set in $CONFIG_FILE" >&2
    exit 1
  fi
  if [ -z "$SENLER_GROUP_ID" ]; then
    echo "ERROR: SENLER_GROUP_ID not set in $CONFIG_FILE" >&2
    exit 1
  fi
  SENLER_V="${SENLER_V:-2}"
  export SENLER_V
}

# ── Flag parser ────────────────────────────────────────────────────
# Usage: eval "$(parse_flags "$@")"
# Recognises --full, --json. POSITIONAL_ARGS keeps the rest.
parse_flags() {
  _pf_full=0
  _pf_json=0
  _pf_remaining=""
  for _arg in "$@"; do
    case "$_arg" in
      --full) _pf_full=1 ;;
      --json) _pf_json=1 ;;
      *)      _pf_remaining="$_pf_remaining $_arg" ;;
    esac
  done
  _pf_remaining=$(echo "$_pf_remaining" | sed 's/^ //')
  printf 'OUTPUT_FULL=%d; OUTPUT_JSON=%d; POSITIONAL_ARGS="%s"' \
    "$_pf_full" "$_pf_json" "$_pf_remaining"
}

# ── Senler API call ────────────────────────────────────────────────
# Usage: senler_api METHOD "param1=val1&param2=val2"
# Method e.g. "subscribers/count", "bots/get".
# Returns raw JSON. Logs errors to stderr.
_last_api_call=0

senler_api() {
  _method="$1"
  _params="$2"

  # Gentle pacing: ~3 req/sec
  _now=$(date +%s)
  if [ "$_last_api_call" -gt 0 ] 2>/dev/null; then
    _elapsed=$(( _now - _last_api_call ))
    if [ "$_elapsed" -lt 1 ]; then
      sleep 0.35
    fi
  fi

  _body="group_id=${SENLER_GROUP_ID}&access_token=${SENLER_ACCESS_TOKEN}&v=${SENLER_V}"
  if [ -n "$_params" ]; then
    _body="${_body}&${_params}"
  fi

  _response=$(curl -s --max-time 30 -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data "$_body" \
    "https://senler.ru/api/${_method}")
  _last_api_call=$(date +%s)

  # Surface API errors to stderr (don't swallow)
  _success=$(echo "$_response" | $JQ -r '.success // empty' 2>/dev/null)
  if [ "$_success" = "false" ]; then
    _ec=$(echo "$_response" | $JQ -r '.error_code // empty' 2>/dev/null)
    _em=$(echo "$_response" | $JQ -r '.error_message // empty' 2>/dev/null)
    echo "Senler API error ($_method): [$_ec] $_em" >&2
  fi

  echo "$_response"
}

# ── Output limiter ─────────────────────────────────────────────────
limit_output() {
  if [ "$OUTPUT_FULL" -eq 1 ]; then
    cat
    return
  fi
  _max=30
  _count=0
  _has_more=0
  while IFS= read -r _line; do
    _count=$(( _count + 1 ))
    if [ "$_count" -le "$_max" ]; then
      echo "$_line"
    else
      _has_more=1
    fi
  done
  if [ "$_has_more" -eq 1 ]; then
    _hidden=$(( _count - _max ))
    echo "# ... truncated ($_hidden more lines). Use --full for complete output."
  fi
}

# ── URL encoder ────────────────────────────────────────────────────
# urlencode VALUE → echoes urlencoded
urlencode() {
  _str="$1"
  _len=${#_str}
  _i=0
  while [ "$_i" -lt "$_len" ]; do
    _c=$(printf '%s' "$_str" | cut -c $((_i+1)))
    case "$_c" in
      [a-zA-Z0-9.~_-]) printf '%s' "$_c" ;;
      *) printf '%%%02X' "'$_c" ;;
    esac
    _i=$((_i+1))
  done
}
