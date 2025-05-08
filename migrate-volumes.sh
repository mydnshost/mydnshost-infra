#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"
cd "${DIR}"
export COMPOSE_PROJECT_NAME=mydnshost

legacyVolumes=(bind-data chronograf-data db-data influxdb-data mongo-data rabbitmq-data rabbitmq-log redis-data)

MIGRATION_NEEDED=0

# Sanity-Check before we do anything.
for vol in ${legacyVolumes[@]}; do
    VOLPATH=$(docker volume inspect "${COMPOSE_PROJECT_NAME}_${vol}" 2>/dev/null | ./jq -r .[].Mountpoint )

    if [ "${VOLPATH}" != "" -a -e "volumes/${vol}" ]; then
        echo "Error - Volume for ${vol} exists, but so does bind-mount path. Aborting."
        exit 1;
    fi;

    if [ "${VOLPATH}" == "" -a ! -e "volumes/${vol}" ]; then
        echo "Error - Volume for ${vol} does not exist, but neither does bind-mount path. Aborting."
        exit 1;
    fi;

    if [ "${VOLPATH}" != "" -a ! -e "volumes/${vol}" ]; then
        MIGRATION_NEEDED="1"
    fi;
done;

# Now actually migrate things if needed.
if [ "${MIGRATION_NEEDED}" == "1" ]; then
    if [ $(id -u) != 0 ]; then
        echo "Migrate-volumes script needs to run as root to actually migrate volumes."
        exit 1;
    fi;

    docker compose down

    for vol in ${legacyVolumes[@]}; do
        echo "Migrating: ${vol}"
        VOLPATH=$(docker volume inspect "${COMPOSE_PROJECT_NAME}_${vol}" 2>/dev/null | ./jq -r .[].Mountpoint )

        mv ${VOLPATH} "volumes/${vol}"

        if [ $? ]; then
            echo "Success."
            docker volume rm "${COMPOSE_PROJECT_NAME}_${vol}"
        else
            echo "Failed to migrate volume: ${vol}"
            exit 1
        fi;
    done;
fi;

exit 0;
