#!/bin/bash
# Verifies BIND 9.20 production deployment after migration.
#
# Usage: ./verify-prod-migration.sh [container_name]
#
# Checks:
# 1. DNSKEY records present for all signed zones
# 2. Trust chain validation via AD flag from public resolver
# 3. Key adoption: omnipresent state, keys predate container start

PROD_CONTAINER="${1:-mydnshost_bind}"

# Counters
TOTAL=0
DNSKEY_OK=0
DNSKEY_MISSING=0
CHAIN_OK=0
CHAIN_NODS=0
CHAIN_FAIL=0
ADOPT_OK=0
ADOPT_BAD=0
KEY_AGE_OK=0
KEY_AGE_BAD=0
ERRORS=0

declare -a DNSKEY_PROBLEMS
declare -a CHAIN_PROBLEMS
declare -a ADOPT_PROBLEMS
declare -a KEY_AGE_PROBLEMS

# Get container start time as epoch
echo "Checking container '$PROD_CONTAINER'..."
CONTAINER_START_RAW=$(docker inspect --format='{{.State.StartedAt}}' "$PROD_CONTAINER" 2>/dev/null)
if [ -z "$CONTAINER_START_RAW" ]; then
    echo "ERROR: Could not inspect container '$PROD_CONTAINER'"
    exit 1
fi
CONTAINER_START=$(date -d "$CONTAINER_START_RAW" +%s 2>/dev/null)
echo "Container started at: $CONTAINER_START_RAW"
echo ""

# Get all zones from the container's catalog
echo "Fetching zone list..."
ZONES=$(docker exec "$PROD_CONTAINER" cat /bind/catalog.db 2>/dev/null \
    | grep -E "IN[[:space:]]+PTR" \
    | awk -F"PTR[[:space:]]+" '{print $2}' \
    | sed 's/.$//' \
    | sort)

if [ -z "$ZONES" ]; then
    echo "ERROR: Could not fetch zone list from $PROD_CONTAINER"
    exit 1
fi

ZONE_COUNT=$(echo "$ZONES" | wc -l)
echo "Found $ZONE_COUNT zones. Running checks..."
echo ""

while read -r ZONE; do
    [ -z "$ZONE" ] && continue
    TOTAL=$((TOTAL + 1))

    printf "\r[%d/%d] Checking %s...                    " "$TOTAL" "$ZONE_COUNT" "$ZONE" >&2

    # 1. Check DNSKEY records present
    DNSKEY=$(docker exec "$PROD_CONTAINER" dig @localhost DNSKEY "$ZONE" +short 2>/dev/null)
    if [ -z "$DNSKEY" ]; then
        DNSKEY_MISSING=$((DNSKEY_MISSING + 1))
        DNSKEY_PROBLEMS+=("$ZONE")
        # Skip remaining checks — zone has no keys
        continue
    fi
    DNSKEY_OK=$((DNSKEY_OK + 1))

    # 2. Trust chain validation — check AD flag from public resolver
    DS_RECORDS=$(dig @8.8.8.8 +short DS "$ZONE" 2>/dev/null)
    if [ -z "$DS_RECORDS" ]; then
        # No DS at parent — can't validate chain (normal for zones without delegation signing)
        CHAIN_NODS=$((CHAIN_NODS + 1))
    else
        # DS exists at parent — check if public resolver validates us
        AD_CHECK=$(dig @8.8.8.8 "$ZONE" SOA +dnssec 2>/dev/null | grep -c "flags:.*ad")
        if [ "$AD_CHECK" -gt 0 ]; then
            CHAIN_OK=$((CHAIN_OK + 1))
        else
            CHAIN_FAIL=$((CHAIN_FAIL + 1))
            CHAIN_PROBLEMS+=("$ZONE")
        fi
    fi

    # 3. Key adoption state and age check
    STATUS=$(docker exec "$PROD_CONTAINER" rndc dnssec -status "$ZONE" 2>/dev/null)

    # 3a. Check all keys are omnipresent
    if echo "$STATUS" | grep -q "goal:.*omnipresent"; then
        ADOPT_OK=$((ADOPT_OK + 1))
    else
        ADOPT_BAD=$((ADOPT_BAD + 1))
        ADOPT_PROBLEMS+=("$ZONE")
    fi

    # 3b. Check key dates predate container start
    KEY_DATES_OK=true
    while IFS= read -r DATE_LINE; do
        # Extract date from lines like "  published:      yes - since Tue Sep 12 02:29:51 2017"
        KEY_DATE_STR=$(echo "$DATE_LINE" | sed 's/.*since //')
        KEY_DATE_EPOCH=$(date -d "$KEY_DATE_STR" +%s 2>/dev/null)
        if [ -n "$KEY_DATE_EPOCH" ] && [ "$KEY_DATE_EPOCH" -ge "$CONTAINER_START" ]; then
            KEY_DATES_OK=false
            break
        fi
    done <<< "$(echo "$STATUS" | grep "since")"

    if $KEY_DATES_OK; then
        KEY_AGE_OK=$((KEY_AGE_OK + 1))
    else
        KEY_AGE_BAD=$((KEY_AGE_BAD + 1))
        KEY_AGE_PROBLEMS+=("$ZONE")
    fi

done <<< "$ZONES"

# Clear progress line
printf "\r                                                              \r" >&2

echo "=========================================="
echo "Production Migration Verification Results"
echo "=========================================="
echo ""
echo "Zones checked: $TOTAL"
echo ""

echo "DNSKEY records present:"
echo "  OK:      $DNSKEY_OK"
echo "  Missing: $DNSKEY_MISSING"
if [ ${#DNSKEY_PROBLEMS[@]} -gt 0 ]; then
    for Z in "${DNSKEY_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

echo "Trust chain (AD flag from 8.8.8.8):"
echo "  Valid:  $CHAIN_OK"
echo "  No DS:  $CHAIN_NODS"
echo "  Failed: $CHAIN_FAIL"
if [ ${#CHAIN_PROBLEMS[@]} -gt 0 ]; then
    for Z in "${CHAIN_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

echo "Key adoption (omnipresent):"
echo "  OK:    $ADOPT_OK"
echo "  Other: $ADOPT_BAD"
if [ ${#ADOPT_PROBLEMS[@]} -gt 0 ]; then
    for Z in "${ADOPT_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

echo "Key age (predate container start):"
echo "  OK:           $KEY_AGE_OK"
echo "  Post-startup: $KEY_AGE_BAD"
if [ ${#KEY_AGE_PROBLEMS[@]} -gt 0 ]; then
    echo "  (These zones may have had keys regenerated after migration)"
    for Z in "${KEY_AGE_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

# Overall verdict
if [ "$DNSKEY_MISSING" -eq 0 ] && [ "$CHAIN_FAIL" -eq 0 ] && [ "$ADOPT_BAD" -eq 0 ] && [ "$KEY_AGE_BAD" -eq 0 ]; then
    echo "=========================================="
    echo "RESULT: ALL CHECKS PASSED"
    echo "=========================================="
    exit 0
else
    echo "=========================================="
    echo "RESULT: ISSUES FOUND — review above"
    echo "=========================================="
    exit 1
fi
