#!/bin/bash
set -euo pipefail

# ----------------------------
# config
# ----------------------------
OPENVPN_INSTALL="/root/openvpn-install.sh"
OUTPUT_DIR="/root"

CLIENT="${1:-}"

if [[ -z "$CLIENT" ]]; then
  echo "__RESULT__={\"status\":\"error\",\"error\":\"CLIENT_NAME_REQUIRED\"}"
  exit 2
fi

# ----------------------------
# run openvpn-install (simulate interactive via stdin)
# ----------------------------
TMP_OUT="$(mktemp)"

# input for interactive script:
# 1 -> add client
# $CLIENT -> client name
# 1 -> default for key size/other questions
printf "1\n%s\n1\n" "$CLIENT" | bash "$OPENVPN_INSTALL" >"$TMP_OUT" 2>&1 || true

# capture output completely inside TMP_OUT
OUTPUT="$(cat "$TMP_OUT")"
rm -f "$TMP_OUT"

OVPN_FILE="${OUTPUT_DIR}/${CLIENT}.ovpn"

# ----------------------------
# detect duplicate client
# ----------------------------
if echo "$OUTPUT" | grep -qi "already found in easy-rsa"; then
  echo "__RESULT__={\"status\":\"error\",\"error\":\"DUPLICATE_CLIENT\",\"client\":\"$CLIENT\"}"
  exit 10
fi

# ----------------------------
# detect success
# ----------------------------
if echo "$OUTPUT" | grep -qi "Client .* added" && [[ -f "$OVPN_FILE" ]]; then
  echo "__RESULT__={\"status\":\"ok\",\"client\":\"$CLIENT\",\"path\":\"$OVPN_FILE\"}"
  exit 0
fi

# ----------------------------
# unknown failure
# ----------------------------
echo "__RESULT__={\"status\":\"error\",\"error\":\"UNKNOWN\",\"client\":\"$CLIENT\"}"
exit 1
