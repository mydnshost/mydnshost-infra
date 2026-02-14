#!/bin/bash
# Validates all zone files using named-checkzone.
#
# Usage: ./check-zone-files.sh
#        Run inside the bind container or pass container name as $1
#
# If run outside a container, wraps calls in docker exec.

CONTAINER="${1:-}"
CATALOGFILE="/bind/catalog.db"
ZONEDIR="/bind/zones"

run_cmd() {
    if [ -n "$CONTAINER" ]; then
        docker exec "$CONTAINER" "$@"
    else
        "$@"
    fi
}

ERRORS=0
OK=0
MISSING=0
TOTAL=0

ZONES=$(run_cmd cat "$CATALOGFILE" 2>/dev/null \
    | grep -E "IN[[:space:]]+PTR" \
    | awk -F"PTR[[:space:]]+" '{print $2}' \
    | sed 's/.$//' \
    | sort)

if [ -z "$ZONES" ]; then
    echo "ERROR: Could not read catalog"
    exit 1
fi

ZONE_COUNT=$(echo "$ZONES" | wc -l)
echo "Checking $ZONE_COUNT zone files..."
echo ""

declare -a ERROR_ZONES
declare -a MISSING_ZONES

while read -r ZONE; do
    [ -z "$ZONE" ] && continue
    TOTAL=$((TOTAL + 1))

    ZONEFILE="$ZONEDIR/$ZONE.db"

    # Check file exists
    if ! run_cmd test -f "$ZONEFILE" 2>/dev/null; then
        MISSING=$((MISSING + 1))
        MISSING_ZONES+=("$ZONE — $ZONEFILE")
        continue
    fi

    # Run named-checkzone
    OUTPUT=$(run_cmd named-checkzone -q "$ZONE" "$ZONEFILE" 2>&1)
    RC=$?

    if [ $RC -eq 0 ]; then
        OK=$((OK + 1))
    else
        ERRORS=$((ERRORS + 1))
        ERROR_ZONES+=("$ZONE — $OUTPUT")
    fi
done <<< "$ZONES"

echo "=========================================="
echo "Zone File Validation Results"
echo "=========================================="
echo ""
echo "Total zones: $TOTAL"
echo "OK:          $OK"
echo "Errors:      $ERRORS"
echo "Missing:     $MISSING"
echo ""

if [ ${#ERROR_ZONES[@]} -gt 0 ]; then
    echo "Zones with errors:"
    for Z in "${ERROR_ZONES[@]}"; do
        echo "  - $Z"
    done
    echo ""
fi

if [ ${#MISSING_ZONES[@]} -gt 0 ]; then
    echo "Missing zone files:"
    for Z in "${MISSING_ZONES[@]}"; do
        echo "  - $Z"
    done
    echo ""
fi

if [ "$ERRORS" -eq 0 ] && [ "$MISSING" -eq 0 ]; then
    echo "RESULT: ALL ZONE FILES OK"
else
    echo "RESULT: ISSUES FOUND"
fi
