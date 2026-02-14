#!/bin/bash
# Verifies BIND 9.16→9.20 migration by comparing test instance against production.
#
# Usage: ./verify-migration.sh
#
# Compares DNSKEY records, checks DNSSEC signatures, verifies key adoption,
# and checks NSEC3 params across all zones.

PROD_SERVER="www.mydnshost.co.uk"
TEST_CONTAINER="mydnshost_bind_test"

# Counters
TOTAL=0
DNSKEY_MATCH=0
DNSKEY_MISMATCH=0
RRSIG_OK=0
RRSIG_MISSING=0
NSEC3_OK=0
NSEC3_BAD=0
ADOPT_OK=0
ADOPT_BAD=0
ERRORS=0

# Get all zones from the test container's catalog
echo "Fetching zone list from test container..."
ZONES=$(docker exec "$TEST_CONTAINER" cat /bind/catalog.db 2>/dev/null \
    | grep -E "IN[[:space:]]+PTR" \
    | awk -F"PTR[[:space:]]+" '{print $2}' \
    | sed 's/.$//' \
    | sort)

if [ -z "$ZONES" ]; then
    echo "ERROR: Could not fetch zone list from $TEST_CONTAINER"
    exit 1
fi

ZONE_COUNT=$(echo "$ZONES" | wc -l)
echo "Found $ZONE_COUNT zones. Running checks..."
echo ""

# Arrays to collect problem zones for the summary
declare -a DNSKEY_PROBLEMS
declare -a RRSIG_PROBLEMS
declare -a NSEC3_PROBLEMS
declare -a ADOPT_PROBLEMS

while read -r ZONE; do
    [ -z "$ZONE" ] && continue
    TOTAL=$((TOTAL + 1))

    # Progress indicator
    printf "\r[%d/%d] Checking %s...                    " "$TOTAL" "$ZONE_COUNT" "$ZONE" >&2

    # 1. Compare DNSKEY records
    PROD_DNSKEY=$(dig @"$PROD_SERVER" DNSKEY "$ZONE" +short 2>/dev/null | sort)
    TEST_DNSKEY=$(docker exec "$TEST_CONTAINER" dig @localhost DNSKEY "$ZONE" +short 2>/dev/null | sort)

    if [ -z "$TEST_DNSKEY" ] && [ -z "$PROD_DNSKEY" ]; then
        # No keys on either side — unsigned zone, skip DNSSEC checks
        continue
    fi

    if [ "$PROD_DNSKEY" = "$TEST_DNSKEY" ]; then
        DNSKEY_MATCH=$((DNSKEY_MATCH + 1))
    else
        DNSKEY_MISMATCH=$((DNSKEY_MISMATCH + 1))
        PROD_COUNT=$(echo "$PROD_DNSKEY" | grep -c . 2>/dev/null || echo 0)
        TEST_COUNT=$(echo "$TEST_DNSKEY" | grep -c . 2>/dev/null || echo 0)
        DETAIL="prod=${PROD_COUNT}keys test=${TEST_COUNT}keys"
        if [ -z "$PROD_DNSKEY" ]; then
            DETAIL="prod=NONE test=${TEST_COUNT}keys (new keys generated?)"
        elif [ -z "$TEST_DNSKEY" ]; then
            DETAIL="prod=${PROD_COUNT}keys test=NONE (keys not loaded?)"
        elif [ "$PROD_COUNT" != "$TEST_COUNT" ]; then
            DETAIL="prod=${PROD_COUNT}keys test=${TEST_COUNT}keys (extra keys on test?)"
        fi
        DNSKEY_PROBLEMS+=("$ZONE — $DETAIL")
    fi

    # 2. Check RRSIG present on test instance
    TEST_RRSIG=$(docker exec "$TEST_CONTAINER" dig @localhost "$ZONE" SOA +dnssec 2>/dev/null | grep "RRSIG")
    if [ -n "$TEST_RRSIG" ]; then
        RRSIG_OK=$((RRSIG_OK + 1))
    else
        RRSIG_MISSING=$((RRSIG_MISSING + 1))
        RRSIG_PROBLEMS+=("$ZONE")
    fi

    # 3. Check NSEC3PARAM (should be iterations=0 on test)
    TEST_NSEC3=$(docker exec "$TEST_CONTAINER" dig @localhost "$ZONE" NSEC3PARAM +short 2>/dev/null)
    if [ -n "$TEST_NSEC3" ]; then
        ITERATIONS=$(echo "$TEST_NSEC3" | awk '{print $3}')
        if [ "$ITERATIONS" = "0" ]; then
            NSEC3_OK=$((NSEC3_OK + 1))
        else
            NSEC3_BAD=$((NSEC3_BAD + 1))
            NSEC3_PROBLEMS+=("$ZONE (iterations=$ITERATIONS)")
        fi
    fi

    # 4. Check key adoption state
    STATUS=$(docker exec "$TEST_CONTAINER" rndc dnssec -status "$ZONE" 2>/dev/null)
    if echo "$STATUS" | grep -q "goal:.*omnipresent"; then
        ADOPT_OK=$((ADOPT_OK + 1))
    else
        ADOPT_BAD=$((ADOPT_BAD + 1))
        ADOPT_PROBLEMS+=("$ZONE")
    fi

done <<< "$ZONES"

# Clear progress line
printf "\r                                                              \r" >&2

echo "=========================================="
echo "Migration Verification Results"
echo "=========================================="
echo ""
echo "Zones checked: $TOTAL"
echo ""

echo "DNSKEY comparison (test vs production):"
echo "  Match:    $DNSKEY_MATCH"
echo "  Mismatch: $DNSKEY_MISMATCH"
if [ ${#DNSKEY_PROBLEMS[@]} -gt 0 ]; then
    for Z in "${DNSKEY_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

echo "RRSIG present on test instance:"
echo "  OK:      $RRSIG_OK"
echo "  Missing: $RRSIG_MISSING"
if [ ${#RRSIG_PROBLEMS[@]} -gt 0 ]; then
    for Z in "${RRSIG_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

echo "NSEC3PARAM (should be iterations=0):"
echo "  OK:  $NSEC3_OK"
echo "  Bad: $NSEC3_BAD"
if [ ${#NSEC3_PROBLEMS[@]} -gt 0 ]; then
    for Z in "${NSEC3_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

echo "Key adoption:"
echo "  Omnipresent: $ADOPT_OK"
echo "  Other:       $ADOPT_BAD"
if [ ${#ADOPT_PROBLEMS[@]} -gt 0 ]; then
    for Z in "${ADOPT_PROBLEMS[@]}"; do
        echo "    - $Z"
    done
fi
echo ""

# Overall verdict
if [ "$DNSKEY_MISMATCH" -eq 0 ] && [ "$RRSIG_MISSING" -eq 0 ] && [ "$ADOPT_BAD" -eq 0 ]; then
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
