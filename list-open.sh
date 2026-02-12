#!/bin/bash

INDEX_FILE="/etc/openvpn/easy-rsa/pki/index.txt"

if [ ! -f "$INDEX_FILE" ]; then
    echo "__RESULT__={\"status\":\"error\",\"message\":\"Index file not found\"}"
    exit 1
fi

# 1. Get only Valid certificates (starts with V)
# 2. Extract client names (after /CN=)
# 3. Filter out the server certificate (usually starts with 'server')
CLIENTS=$(grep "^V" "$INDEX_FILE" | sed -n 's/.*\/CN=\([^/]*\).*/\1/p' | grep -v "^server")

JSON_CLIENTS=""
for CLIENT in $CLIENTS; do
    if [ -z "$JSON_CLIENTS" ]; then
        JSON_CLIENTS="\"$CLIENT\""
    else
        JSON_CLIENTS="$JSON_CLIENTS, \"$CLIENT\""
    fi
done

echo "__RESULT__={\"status\":\"ok\",\"clients\":[$JSON_CLIENTS]}"