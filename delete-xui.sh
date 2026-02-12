#!/usr/bin/env bash

DB="/etc/x-ui/x-ui.db"

show_help() {
cat <<EOF
Usage:
  delete-xui.sh <client>

Example:
  delete-xui.sh shell-test

Output:
  __RESULT__={"status":"ok","client":"shell-test","deleted":true}
EOF
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  show_help
  exit 0
fi

CLIENT="$1"

if [ -z "$CLIENT" ]; then
  echo "__RESULT__={\"status\":\"error\",\"error\":\"MISSING_CLIENT\"}"
  exit 1
fi

FOUND=0

while read -r INBOUND_ID; do
  FOUND=1

  sqlite3 "$DB" "
  UPDATE inbounds
  SET settings = json_set(
    settings,
    '\$.clients',
    (
      SELECT json_group_array(value)
      FROM json_each(settings, '\$.clients')
      WHERE json_extract(value, '\$.email') != '$CLIENT'
    )
  )
  WHERE id = $INBOUND_ID;
  "

done < <(sqlite3 "$DB" "
SELECT DISTINCT inbounds.id
FROM inbounds, json_each(inbounds.settings,'\$.clients')
WHERE json_extract(json_each.value,'\$.email')='$CLIENT';
")

sqlite3 "$DB" "
DELETE FROM client_traffics WHERE email='$CLIENT';
"

if [ "$FOUND" -eq 0 ]; then
  echo "__RESULT__={\"status\":\"error\",\"error\":\"CLIENT_NOT_FOUND\",\"client\":\"$CLIENT\"}"
  exit 1
fi

x-ui restart >/dev/null 2>&1

echo "__RESULT__={\"status\":\"ok\",\"client\":\"$CLIENT\",\"deleted\":true}"
