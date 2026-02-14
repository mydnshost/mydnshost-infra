#!/bin/bash
# Identifies duplicate keys and recommends which to keep/remove.
# Queries DNS for DS records to determine which KSKs are in use.
#
# Usage: ./list-anomaly-keys.sh /path/to/bind/keys
#        (defaults to /bind/keys)

KEYDIR="${1:-/bind/keys}"

if [ ! -d "$KEYDIR" ]; then
    echo "ERROR: Key directory '$KEYDIR' does not exist."
    exit 1
fi

# First pass: count keys per domain
declare -A DOMAIN_KEY_COUNT
for PRIVFILE in "$KEYDIR"/*.private; do
    [ -e "$PRIVFILE" ] || continue
    BASENAME=$(basename "$PRIVFILE" .private)
    KEYFILE="$KEYDIR/$BASENAME.key"
    [ -e "$KEYFILE" ] || continue

    DOMAIN=$(echo "$BASENAME" | sed 's/^K//;s/\.+[0-9]*+[0-9]*$//')
    DOMAIN_KEY_COUNT["$DOMAIN"]=$(( ${DOMAIN_KEY_COUNT["$DOMAIN"]:-0} + 1 ))
done

# Find domains with more than 2 keys (1 KSK + 1 ZSK = 2)
declare -a ANOMALY_DOMAINS
for DOMAIN in "${!DOMAIN_KEY_COUNT[@]}"; do
    if [ ${DOMAIN_KEY_COUNT["$DOMAIN"]} -gt 2 ]; then
        ANOMALY_DOMAINS+=("$DOMAIN")
    fi
done

if [ ${#ANOMALY_DOMAINS[@]} -eq 0 ]; then
    echo "No anomaly domains found. All domains have exactly 1 KSK + 1 ZSK."
    exit 0
fi

echo "Found ${#ANOMALY_DOMAINS[@]} domain(s) with extra keys."
echo ""

# Track jobs to create
declare -a JOBS_TO_CREATE

for DOMAIN in $(printf '%s\n' "${ANOMALY_DOMAINS[@]}" | sort); do
    echo "=========================================="
    echo "Domain: $DOMAIN"
    echo "=========================================="

    # Query DNS for DS records at parent, store full records per key ID
    DS_KEYIDS=()
    declare -A DS_RECORDS_BY_KEY
    DS_OUTPUT=$(dig @8.8.8.8 +short DS "$DOMAIN" 2>/dev/null)
    if [ -n "$DS_OUTPUT" ]; then
        while read -r LINE; do
            DSKEYID=$(echo "$LINE" | awk '{print $1}')
            DS_KEYIDS+=("$DSKEYID")
            DS_RECORDS_BY_KEY["$DSKEYID"]+="      $DOMAIN. IN DS $LINE"$'\n'
        done <<< "$DS_OUTPUT"
        echo "  DS at parent: key-id(s) $(echo "${DS_KEYIDS[@]}" | tr ' ' '\n' | sort -un | tr '\n' ' ')"
    else
        echo "  DS at parent: NONE"
    fi

    # Collect all keys for this domain
    declare -a KSKS=()
    declare -a ZSKS=()
    declare -A KEY_CREATED
    declare -A KEY_HAS_DS

    for PRIVFILE in "$KEYDIR"/K"$DOMAIN".+*.private; do
        [ -e "$PRIVFILE" ] || continue
        BASENAME=$(basename "$PRIVFILE" .private)
        KEYFILE="$KEYDIR/$BASENAME.key"
        [ -e "$KEYFILE" ] || continue

        KEYID=$(echo "$BASENAME" | grep -oP '\+\K[0-9]+$')
        # Strip leading zeros for comparison with DS key IDs
        KEYID_NUM=$((10#$KEYID))
        FLAGS=$(grep -v "^;" "$KEYFILE" | grep "DNSKEY" | sed 's/.*DNSKEY[[:space:]]*//' | awk '{print $1}')
        CREATED=$(grep "^Created:" "$PRIVFILE" 2>/dev/null | awk '{print $2}')

        KEY_CREATED["$KEYID_NUM"]="$CREATED"
        KEY_HAS_DS["$KEYID_NUM"]="no"
        for DSKEYID in "${DS_KEYIDS[@]}"; do
            if [ "$KEYID_NUM" = "$DSKEYID" ]; then
                KEY_HAS_DS["$KEYID_NUM"]="yes"
            fi
        done

        if [ "$FLAGS" = "257" ]; then
            KSKS+=("$KEYID_NUM")
        elif [ "$FLAGS" = "256" ]; then
            ZSKS+=("$KEYID_NUM")
        fi
    done

    # Decide which KSK to keep
    KEEP_KSK=""
    REMOVE_KSKS=()

    # If only one KSK has a DS, keep that one
    KSK_WITH_DS=()
    KSK_WITHOUT_DS=()
    for KID in "${KSKS[@]}"; do
        if [ "${KEY_HAS_DS[$KID]}" = "yes" ]; then
            KSK_WITH_DS+=("$KID")
        else
            KSK_WITHOUT_DS+=("$KID")
        fi
    done

    if [ ${#KSK_WITH_DS[@]} -eq 1 ]; then
        KEEP_KSK="${KSK_WITH_DS[0]}"
        REMOVE_KSKS=("${KSK_WITHOUT_DS[@]}")
    elif [ ${#KSK_WITH_DS[@]} -eq 0 ]; then
        # No DS records, keep the newest
        NEWEST=""
        NEWEST_DATE=""
        for KID in "${KSKS[@]}"; do
            if [ -z "$NEWEST_DATE" ] || [[ "${KEY_CREATED[$KID]}" > "$NEWEST_DATE" ]]; then
                NEWEST="$KID"
                NEWEST_DATE="${KEY_CREATED[$KID]}"
            fi
        done
        KEEP_KSK="$NEWEST"
        for KID in "${KSKS[@]}"; do
            [ "$KID" != "$KEEP_KSK" ] && REMOVE_KSKS+=("$KID")
        done
    else
        # Multiple KSKs with DS — keep the newest, flag the DS removal needed
        NEWEST=""
        NEWEST_DATE=""
        for KID in "${KSK_WITH_DS[@]}"; do
            if [ -z "$NEWEST_DATE" ] || [[ "${KEY_CREATED[$KID]}" > "$NEWEST_DATE" ]]; then
                NEWEST="$KID"
                NEWEST_DATE="${KEY_CREATED[$KID]}"
            fi
        done
        KEEP_KSK="$NEWEST"
        for KID in "${KSKS[@]}"; do
            [ "$KID" != "$KEEP_KSK" ] && REMOVE_KSKS+=("$KID")
        done
    fi

    # Decide which ZSK to keep (newest, no DS dependency)
    KEEP_ZSK=""
    REMOVE_ZSKS=()
    NEWEST=""
    NEWEST_DATE=""
    for KID in "${ZSKS[@]}"; do
        if [ -z "$NEWEST_DATE" ] || [[ "${KEY_CREATED[$KID]}" > "$NEWEST_DATE" ]]; then
            NEWEST="$KID"
            NEWEST_DATE="${KEY_CREATED[$KID]}"
        fi
    done
    KEEP_ZSK="$NEWEST"
    for KID in "${ZSKS[@]}"; do
        [ "$KID" != "$KEEP_ZSK" ] && REMOVE_ZSKS+=("$KID")
    done

    # Output results
    echo ""
    echo "  KSKs (flags=257):"
    for KID in "${KSKS[@]}"; do
        if [ "$KID" = "$KEEP_KSK" ]; then
            echo "    KEEP   key-id=$KID  created=${KEY_CREATED[$KID]}"
        else
            echo "    REMOVE key-id=$KID  created=${KEY_CREATED[$KID]}"
        fi
        if [ -n "${DS_RECORDS_BY_KEY[$KID]}" ]; then
            printf "%s" "${DS_RECORDS_BY_KEY[$KID]}"
        fi
    done

    echo "  ZSKs (flags=256):"
    for KID in "${ZSKS[@]}"; do
        if [ "$KID" = "$KEEP_ZSK" ]; then
            echo "    KEEP   key-id=$KID  created=${KEY_CREATED[$KID]}"
        else
            echo "    REMOVE key-id=$KID  created=${KEY_CREATED[$KID]}"
        fi
    done

    # Collect jobs to create
    for KID in "${REMOVE_KSKS[@]}" "${REMOVE_ZSKS[@]}"; do
        JOBS_TO_CREATE+=("{\"domain\": \"$DOMAIN\", \"key_id\": $KID}")
    done

    echo ""

    # Clean up per-domain arrays
    unset KSKS ZSKS KEY_CREATED KEY_HAS_DS DS_RECORDS_BY_KEY
done

# Output actionable jobs
if [ ${#JOBS_TO_CREATE[@]} -gt 0 ]; then
    echo ""
    echo "=========================================="
    echo "Cleanup jobs to dispatch"
    echo "=========================================="
    echo ""
    echo "# Submit these bind_delete_key jobs to remove the extra keys."
    echo "# The worker will delete from DB, clean up disk files, and refresh the zone."
    echo ""
    for PAYLOAD in "${JOBS_TO_CREATE[@]}"; do
        echo "job: bind_delete_key payload: $PAYLOAD"
    done
    echo ""
    echo "# For any removed keys that had DS records at the parent, update the registrar."
fi
