#!/usr/bin/env bash

DB="/etc/x-ui/x-ui.db"

show_help() {
cat <<EOF
Usage:
  update-xui.sh <client> <mode> [value]

Modes:
  add <GB>        Add <GB> to current traffic (0 = unlimited)
  reset-add <GB>  Reset current usage and set total traffic to <GB> (0 = unlimited)
  disable         Disable client
  enable          Enable client
  reset           Reset traffic usage (up/down = 0)
  expiry <ts>     Set expiry time (unix timestamp)

Examples:
  update-xui.sh user1 add 50
  update-xui.sh user1 reset-add 50
  update-xui.sh user1 disable
  update-xui.sh user1 enable
  update-xui.sh user1 reset
  update-xui.sh user1 expiry 1735689600

Output:
  __RESULT__={"status":"ok","client":"user1","total":...,"enable":...,"expiry":...}
EOF
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  show_help
  exit 0
fi

CLIENT="$1"
MODE="$2"
VALUE="$3"

if [ -z "$CLIENT" ] || [ -z "$MODE" ]; then
  echo "__RESULT__={\"status\":\"error\",\"error\":\"INVALID_ARGS\"}"
  exit 1
fi

# Get INBOUND_ID and INDEX safely
INBOUND_DATA=$(sqlite3 "$DB" "
SELECT inbounds.id || ':' || json_each.key
FROM inbounds, json_each(inbounds.settings, '\$.clients')
WHERE json_extract(json_each.value,'\$.email')='$CLIENT'
LIMIT 1;")

if [ -z "$INBOUND_DATA" ]; then
  echo "__RESULT__={\"status\":\"error\",\"error\":\"CLIENT_NOT_FOUND\",\"client\":\"$CLIENT\"}"
  exit 1
fi

INBOUND_ID="${INBOUND_DATA%%:*}"
INDEX="${INBOUND_DATA##*:}"

# Uncomment for debug
# echo "DEBUG: INBOUND_ID=$INBOUND_ID INDEX=$INDEX"

case "$MODE" in
  add)
    [ -z "$VALUE" ] && VALUE=0
    TOTAL=$((VALUE * 1024 * 1024 * 1024))
    sqlite3 "$DB" "
    UPDATE inbounds
    SET settings=json_set(settings,'\$.clients[$INDEX].totalGB',$TOTAL)
    WHERE id=$INBOUND_ID;"
    ;;

  reset-add)
    [ -z "$VALUE" ] && VALUE=0
    TOTAL=$((VALUE * 1024 * 1024 * 1024))
  
    sqlite3 "$DB" "
    UPDATE client_traffics
    SET up=0,
        down=0,
        total=$TOTAL
    WHERE email='$CLIENT';"
  
    sqlite3 "$DB" "
    UPDATE inbounds
    SET settings=json_set(settings,'\$.clients[$INDEX].totalGB',$TOTAL)
    WHERE id=$INBOUND_ID;"
    ;;


  disable)
    sqlite3 "$DB" "
    UPDATE inbounds
    SET settings=json_set(settings,'\$.clients[$INDEX].enable',0)
    WHERE id=$INBOUND_ID;"
    ;;

  enable)
    sqlite3 "$DB" "
    UPDATE inbounds
    SET settings=json_set(settings,'\$.clients[$INDEX].enable',1)
    WHERE id=$INBOUND_ID;"
    ;;

  reset)
    sqlite3 "$DB" "
    UPDATE client_traffics
    SET up=0, down=0
    WHERE email='$CLIENT';"
    ;;

  expiry)
    if [ -z "$VALUE" ]; then
      echo "__RESULT__={\"status\":\"error\",\"error\":\"MISSING_VALUE_FOR_EXPIRY\"}"
      exit 1
    fi
    sqlite3 "$DB" "
    UPDATE inbounds
    SET settings=json_set(settings,'\$.clients[$INDEX].expiryTime',$VALUE)
    WHERE id=$INBOUND_ID;"
    ;;

  *)
    echo "__RESULT__={\"status\":\"error\",\"error\":\"UNKNOWN_MODE\"}"
    exit 1
    ;;
esac

# Restart X-UI silently
x-ui restart >/dev/null 2>&1

# Read inbound info safely
read TOTAL ENABLE EXPIRY <<<$(sqlite3 -separator ' ' "$DB" "
SELECT
  json_extract(settings,'\$.clients[$INDEX].totalGB'),
  json_extract(settings,'\$.clients[$INDEX].enable'),
  json_extract(settings,'\$.clients[$INDEX].expiryTime')
FROM inbounds WHERE id=$INBOUND_ID;
")

# Handle unlimited (0) for clients that were previously unlimited
if [ "$TOTAL" -eq 0 ]; then
  TOTAL=0
fi

# Return JSON result
echo "__RESULT__={\"status\":\"ok\",\"client\":\"$CLIENT\",\"total\":${TOTAL:-0},\"enable\":${ENABLE:-1},\"expiry\":${EXPIRY:-0}}"
