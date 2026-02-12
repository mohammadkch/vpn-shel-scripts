#!/usr/bin/env bash

DB="/etc/x-ui/x-ui.db"

FILTER=""
if [[ "$1" == "--active" ]]; then
    FILTER="WHERE enable_val=1"
elif [[ "$1" == "--inactive" ]]; then
    FILTER="WHERE enable_val=0"
fi

RESULT=$(sqlite3 -json "$DB" "
    SELECT * FROM (
        SELECT 
            json_extract(json_each.value, '$.email') AS client,
            json_extract(json_each.value, '$.enable') AS enable_val,
            json_extract(json_each.value, '$.totalGB') AS total,
            json_extract(json_each.value, '$.id') AS uuid
        FROM inbounds, json_each(inbounds.settings, '$.clients')
    ) $FILTER;
")

echo "__RESULT__=$RESULT"