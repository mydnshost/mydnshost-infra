#!/bin/bash

if test $# -lt 3; then
    cat <<EOF
Need at least 3 arguments:
  - the container id,
  - the signal,
  - one or more files (or folders) to watch
EOF
    exit 1
fi

CONTAINER_ID="$1"
SIGNAL="$2"

if [[ "$SIGNAL" != SIG* ]]; then
    echo -e "Invalid signal name: $SIGNAL"
    exit 1
fi

# Leave just file and folder arguments
shift
shift

NEXT=0

function setup {
    NEXT=$(( NEXT + 1 ))
    echo $NEXT > /tmp/next
    (
        sleep 1
        if [ `cat /tmp/next` = $NEXT ]; then
            echo -e "POST /containers/$CONTAINER_ID/kill?signal=$SIGNAL HTTP/1.1\nHost: docker.sock\n" | ncat -U /var/run/docker.sock
        fi
    ) &
}

setup

inotifywait --event modify --monitor "$@" | \
    while read -r change; do
        echo "$change"
        setup
    done
