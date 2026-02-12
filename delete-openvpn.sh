#!/bin/bash
set -euo pipefail

CLIENT="$1"

if [[ -z "$CLIENT" ]]; then
  echo "__RESULT__={\"status\":\"error\",\"error\":\"NO_CLIENT_SPECIFIED\"}"
  exit 1
fi

LOG_FILE="/tmp/revoke_${CLIENT}_$(date +%s).log"
exec > >(tee -a "$LOG_FILE") 2>&1

EASYRSA_DIR="/etc/openvpn/easy-rsa"
CERT_FILE="$EASYRSA_DIR/pki/issued/${CLIENT}.crt"

# check if certificate exists
if [[ ! -f "$CERT_FILE" ]]; then
    echo "__RESULT__={\"status\":\"error\",\"error\":\"CLIENT_NOT_FOUND\",\"client\":\"$CLIENT\"}"
    exit 1
fi

cd "$EASYRSA_DIR" || {
    echo "__RESULT__={\"status\":\"error\",\"error\":\"EASYRSA_DIR_NOT_FOUND\",\"client\":\"$CLIENT\"}"
    exit 1
}

# revoke certificate
TMP_OUT="$(mktemp)"
if ! ./easyrsa --batch revoke "$CLIENT" >"$TMP_OUT" 2>&1; then
    echo "__RESULT__={\"status\":\"error\",\"error\":\"REVOKE_FAILED\",\"client\":\"$CLIENT\"}"
    rm -f "$TMP_OUT"
    exit 1
fi
rm -f "$TMP_OUT"

# generate CRL
if ! EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl >"$TMP_OUT" 2>&1; then
    echo "__RESULT__={\"status\":\"error\",\"error\":\"CRL_GEN_FAILED\",\"client\":\"$CLIENT\"}"
    rm -f "$TMP_OUT"
    exit 1
fi
cp pki/crl.pem /etc/openvpn/crl.pem
chmod 644 /etc/openvpn/crl.pem
rm -f "$TMP_OUT"

# remove ovpn files
DELETED_FILES=""
NOT_FOUND_FILES=""

CLIENT_FILES=$(find /home/ -maxdepth 2 -name "$CLIENT.ovpn")
if [[ -n "$CLIENT_FILES" ]]; then
    find /home/ -maxdepth 2 -name "$CLIENT.ovpn" -delete
    DELETED_FILES="$DELETED_FILES $CLIENT_FILES"
else
    NOT_FOUND_FILES="$NOT_FOUND_FILES /home/*/$CLIENT.ovpn"
fi

if [[ -f "/root/$CLIENT.ovpn" ]]; then
    rm -f "/root/$CLIENT.ovpn"
    DELETED_FILES="$DELETED_FILES /root/$CLIENT.ovpn"
else
    NOT_FOUND_FILES="$NOT_FOUND_FILES /root/$CLIENT.ovpn"
fi

# remove from ipp.txt
if grep -q "^$CLIENT," /etc/openvpn/ipp.txt; then
    sed -i "/^$CLIENT,.*/d" /etc/openvpn/ipp.txt
    DELETED_FILES="$DELETED_FILES ipp.txt entry"
else
    NOT_FOUND_FILES="$NOT_FOUND_FILES ipp.txt entry"
fi

# backup index.txt
cp pki/index.txt pki/index.txt.bk

# final JSON output
if [[ -n "$DELETED_FILES" ]]; then
    echo "__RESULT__={\"status\":\"ok\",\"client\":\"$CLIENT\",\"deleted_files\":\"$DELETED_FILES\"}"
    exit 0
else
    echo "__RESULT__={\"status\":\"error\",\"error\":\"NOTHING_DELETED\",\"client\":\"$CLIENT\",\"not_found\":\"$NOT_FOUND_FILES\"}"
    exit 1
fi
