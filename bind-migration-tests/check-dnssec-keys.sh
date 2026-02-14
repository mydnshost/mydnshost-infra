#!/bin/bash
# Pre-migration check script for BIND 9.16 → 9.20 (auto-dnssec → dnssec-policy)
#
# Run this against the bind data volume before migrating.
# Usage: ./check-dnssec-keys.sh /path/to/bind/keys
#        (defaults to /bind/keys if no argument given)

set -e

KEYDIR="${1:-/bind/keys}"

if [ ! -d "$KEYDIR" ]; then
    echo "ERROR: Key directory '$KEYDIR' does not exist."
    exit 1
fi

PRIVATE_FILES=("$KEYDIR"/*.private)
if [ ! -e "${PRIVATE_FILES[0]}" ]; then
    echo "No .private key files found in $KEYDIR"
    exit 0
fi

echo "Scanning keys in: $KEYDIR"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

declare -A DOMAIN_KSK_COUNT
declare -A DOMAIN_ZSK_COUNT
declare -A ALGORITHMS_SEEN

for PRIVFILE in "$KEYDIR"/*.private; do
    BASENAME=$(basename "$PRIVFILE" .private)
    KEYFILE="$KEYDIR/$BASENAME.key"

    # Extract domain from filename: K<domain>.+<alg>+<keyid>
    DOMAIN=$(echo "$BASENAME" | sed 's/^K//;s/\.+[0-9]*+[0-9]*$//')

    # Check .key file exists
    if [ ! -e "$KEYFILE" ]; then
        echo "WARNING: Missing .key file for $BASENAME (domain: $DOMAIN)"
        WARNINGS=$((WARNINGS + 1))
        continue
    fi

    # Extract algorithm from .private file
    ALG_LINE=$(grep "^Algorithm:" "$PRIVFILE" | head -1)
    ALG_NUM=$(echo "$ALG_LINE" | awk '{print $2}')

    ALGORITHMS_SEEN["$ALG_NUM"]=1

    # Extract flags from .key file (DNSKEY record: <domain> [TTL] IN DNSKEY <flags> <proto> <alg> <key>)
    # TTL may or may not be present, so extract the first field after "DNSKEY"
    FLAGS=$(grep -v "^;" "$KEYFILE" | grep "DNSKEY" | sed 's/.*DNSKEY[[:space:]]*//' | awk '{print $1}')

    if [ "$FLAGS" = "257" ]; then
        DOMAIN_KSK_COUNT["$DOMAIN"]=$(( ${DOMAIN_KSK_COUNT["$DOMAIN"]:-0} + 1 ))
    elif [ "$FLAGS" = "256" ]; then
        DOMAIN_ZSK_COUNT["$DOMAIN"]=$(( ${DOMAIN_ZSK_COUNT["$DOMAIN"]:-0} + 1 ))
    else
        echo "WARNING: Unexpected flags '$FLAGS' for $BASENAME (domain: $DOMAIN)"
        WARNINGS=$((WARNINGS + 1))
    fi
done

# Report algorithms
echo "Algorithms found:"
for ALG in "${!ALGORITHMS_SEEN[@]}"; do
    case "$ALG" in
        5)  ALG_NAME="RSASHA1" ;;
        7)  ALG_NAME="RSASHA1-NSEC3-SHA1" ;;
        8)  ALG_NAME="RSASHA256" ;;
        10) ALG_NAME="RSASHA512" ;;
        13) ALG_NAME="ECDSAP256SHA256" ;;
        14) ALG_NAME="ECDSAP384SHA384" ;;
        15) ALG_NAME="ED25519" ;;
        16) ALG_NAME="ED448" ;;
        *)  ALG_NAME="UNKNOWN" ;;
    esac
    echo "  Algorithm $ALG ($ALG_NAME)"
done
echo ""

if [ ${#ALGORITHMS_SEEN[@]} -gt 1 ]; then
    echo "WARNING: Multiple algorithms in use! A single dnssec-policy may not cover all zones."
    echo "         You may need separate policies per algorithm."
    WARNINGS=$((WARNINGS + 1))
fi

if [ ${#ALGORITHMS_SEEN[@]} -eq 1 ] && [ -n "${ALGORITHMS_SEEN[8]}" ]; then
    echo "OK: All keys use RSASHA256 (algorithm 8) — compatible with a single dnssec-policy."
fi
echo ""

# Report per-domain key counts
echo "Per-domain key counts:"
echo "=========================================="

# Collect all domains
declare -A ALL_DOMAINS
for DOMAIN in "${!DOMAIN_KSK_COUNT[@]}"; do ALL_DOMAINS["$DOMAIN"]=1; done
for DOMAIN in "${!DOMAIN_ZSK_COUNT[@]}"; do ALL_DOMAINS["$DOMAIN"]=1; done

for DOMAIN in $(echo "${!ALL_DOMAINS[@]}" | tr ' ' '\n' | sort); do
    KSK=${DOMAIN_KSK_COUNT["$DOMAIN"]:-0}
    ZSK=${DOMAIN_ZSK_COUNT["$DOMAIN"]:-0}

    STATUS="OK"
    if [ "$KSK" -ne 1 ] || [ "$ZSK" -ne 1 ]; then
        STATUS="ANOMALY"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [ "$STATUS" != "OK" ]; then
        echo "  [$STATUS] $DOMAIN: KSK=$KSK ZSK=$ZSK"
    fi
done

TOTAL_DOMAINS=${#ALL_DOMAINS[@]}
echo "  Total domains with keys: $TOTAL_DOMAINS"
echo ""

# Summary
echo "=========================================="
echo "Summary: $ERRORS error(s), $WARNINGS warning(s)"

if [ $WARNINGS -gt 0 ]; then
    echo "RESULT: WARNINGS found — review before migrating."
    exit 0
else
    echo "RESULT: All checks passed — safe to migrate."
    exit 0
fi
