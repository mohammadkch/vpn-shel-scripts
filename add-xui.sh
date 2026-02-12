#!/bin/bash
set -e

DB="/etc/x-ui/x-ui.db"
INBOUND_ID=1

CLIENT_NAME="$1"
TRAFFIC_GB="${2:-0}" 

if [ -z "$CLIENT_NAME" ]; then
    CLIENT_NAME="user_$(date +%s)"
fi

# Convert GB to Bytes
TOTAL_BYTES=$(($TRAFFIC_GB * 1024 * 1024 * 1024))

# Check duplicate client
EXISTS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM client_traffics WHERE email='$CLIENT_NAME';")
if [ "$EXISTS" -gt 0 ]; then
    echo "__RESULT__={\"status\":\"error\",\"error\":\"DUPLICATE_CLIENT\",\"client\":\"$CLIENT_NAME\"}"
    exit 0
fi

UUID=$(uuidgen)
SUBID=$(tr -dc a-z0-9 </dev/urandom | head -c 16)
EXPIRY=0

# Insert client into Database
sqlite3 "$DB" <<EOF
BEGIN;

UPDATE inbounds
SET settings = json_set(
  settings,
  '$.clients[#]',
  json_object(
    'email','$CLIENT_NAME',
    'enable',1,
    'expiryTime',$EXPIRY,
    'id','$UUID',
    'subId','$SUBID',
    'totalGB',$TOTAL_BYTES
  )
)
WHERE id=$INBOUND_ID;

INSERT INTO client_traffics
(inbound_id, enable, email, up, down, expiry_time, total, reset)
VALUES
($INBOUND_ID,1,'$CLIENT_NAME',0,0,$EXPIRY,$TOTAL_BYTES,0);

COMMIT;
EOF

# Fetch inbound details
INFO=$(sqlite3 "$DB" "SELECT json_extract(stream_settings,'$.externalProxy[0].dest'), port, remark FROM inbounds WHERE id=$INBOUND_ID;")
HOST=$(echo "$INFO" | cut -d'|' -f1)
PORT=$(echo "$INFO" | cut -d'|' -f2)
REMARK=$(echo "$INFO" | cut -d'|' -f3)

# Build VLESS link with correct format
VLESS="vless://${UUID}@${HOST}:${PORT}?type=tcp&security=none#${REMARK}-${CLIENT_NAME}"

# Restart service
x-ui restart >/dev/null 2>&1

# Output result
echo "__RESULT__={\"status\":\"ok\",\"client\":\"$CLIENT_NAME\",\"traffic_gb\":\"$TRAFFIC_GB\",\"uuid\":\"$UUID\",\"config\":\"$VLESS\"}"