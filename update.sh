#!/bin/bash

# First time run needs longer.
export COMPOSE_HTTP_TIMEOUT=600

DIR="$(dirname "$(readlink -f "$0")")"

cd "${DIR}"

# Our main project name
export COMPOSE_PROJECT_NAME=mydnshost

touch traefik/acme.json
chmod 600 traefik/acme.json

docker compose >/dev/null 2>&1
if [ ${?} -ne 0 ]; then
	echo "Docker Compose v2 is required for this script."
	exit 1;
fi;

# Update images
echo 'Updating images...';
docker compose pull
# cat docker-compose.yml docker-compose.override.yml | grep -i "image:" | sort -u | awk '{print $2}' | while read IMAGE; do docker pull ${IMAGE}; done
# docker pull mydnshost/mydnshost-api
# docker pull mydnshost/mydnshost-frontend
# docker pull mydnshost/mydnshost-bind
# docker pull mydnshost/mydnshost-docker-cron

# Check for volume migrations.
./migrate-volumes.sh
if [ ${?} -ne 0 ]; then
	echo "Volume migration failed, stopping."
	exit 1;
fi;

# Ensure volumes exist with correct permissions
uid0Volumes=(chronograf-data influxdb-data)
uid33Volumes=(bind-data)
uid999Volumes=(db-data mongo-data rabbitmq-data rabbitmq-log redis-data)

for vol in ${uid0Volumes[@]}; do
    if [ ! -e "./volumes/${vol}" ]; then
		mkdir "./volumes/${vol}"
		chown 0:0 "./volumes/${vol}"
	fi;
done;

for vol in ${uid33Volumes[@]}; do
    if [ ! -e "./volumes/${vol}" ]; then
		mkdir "./volumes/${vol}"
		chown 33:33 "./volumes/${vol}"
	fi;
done;

for vol in ${uid999Volumes[@]}; do
    if [ ! -e "./volumes/${vol}" ]; then
		mkdir "./volumes/${vol}"
		chown 999:999 "./volumes/${vol}"
	fi;
done;

function prepareAPIContainers() {
	docker ps -a --format '{{.Names}}' | grep -i mydnshost_api_ | while read NAME; do
		docker exec -t "${NAME}" chown www-data: /bind
		docker exec -t "${NAME}" su www-data --shell=/bin/bash -c "/dnsapi/admin/init.php"
	done;
}

# Services that get a rolling (scale up, wait for healthy, drain old) update.
ROLLING_SERVICES=(api web)

# How long to wait for a new container to become healthy.
HEALTH_TIMEOUT=300
# How long to wait for a draining container to be marked unhealthy.
DRAIN_TIMEOUT=30
# Time for traefik to react to a health change (providersThrottleDuration
# defaults to 2s, so this gives it some slack).
TRAEFIK_GRACE=5

# Echo the health state of a container (starting, healthy, unhealthy), "none"
# if it has no healthcheck, or "exited" if it is no longer running.
function containerHealth() {
	docker inspect --format '{{if not .State.Running}}exited{{else if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${1}" 2>/dev/null || echo "exited"
}

# Wait for a container to reach the given health state.
function waitForHealth() {
	local ID="${1}"
	local WANT="${2}"
	local TIMEOUT="${3}"
	local END=$(( $(date +%s) + TIMEOUT ))

	while [ "$(date +%s)" -lt "${END}" ]; do
		local STATE=$(containerHealth "${ID}")
		if [ "${STATE}" = "${WANT}" ]; then
			return 0;
		fi;

		# Don't wait around for a container that has already failed. (Exiting
		# isn't fatal, restart: always will bring it back.)
		if [ "${WANT}" = "healthy" ] && [ "${STATE}" = "unhealthy" ]; then
			return 1;
		fi;

		sleep 1;
	done;

	return 1;
}

# Check if a container differs from what compose would create now, either
# because the image has been updated or the service config has changed.
function needsUpgrade() {
	local SERVICE="${1}"
	local ID="${2}"

	local WANT_HASH=$(docker compose config --hash "${SERVICE}" | awk '{print $2}')
	local HAVE_HASH=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.config-hash"}}' "${ID}")
	local WANT_IMAGE=$(docker image inspect --format '{{.Id}}' "$(docker inspect --format '{{.Config.Image}}' "${ID}")")
	local HAVE_IMAGE=$(docker inspect --format '{{.Image}}' "${ID}")

	[ "${WANT_HASH}" != "${HAVE_HASH}" ] || [ "${WANT_IMAGE}" != "${HAVE_IMAGE}" ]
}

function rollingUpdate() {
	local SERVICE="${1}"
	local OLD_IDS=$(docker compose ps -q --status running "${SERVICE}")

	if [ "" = "${OLD_IDS}" ]; then
		echo "${SERVICE} is not running, starting...";
		docker compose up -d --no-deps "${SERVICE}"
		return;
	fi;

	echo 'Checking '"${SERVICE}"'...';
	local NEED_UPGRADE="0";
	for ID in ${OLD_IDS}; do
		if needsUpgrade "${SERVICE}" "${ID}"; then
			echo "${SERVICE} (${ID:0:12}) needs upgrading."
			NEED_UPGRADE="1"
		fi;
	done;

	if [ "${NEED_UPGRADE}" = "0" ]; then
		echo "${SERVICE} is up to date."
		return;
	fi;

	local OLD_COUNT=$(echo "${OLD_IDS}" | wc -l)
	echo "Scaling up ${SERVICE}...";
	docker compose up -d --no-deps --no-recreate --scale "${SERVICE}=$(( OLD_COUNT * 2 ))" "${SERVICE}"

	local NEW_IDS=$(docker compose ps -a -q "${SERVICE}" | grep -vxF "${OLD_IDS}")
	if [ "" = "${NEW_IDS}" ]; then
		echo "Failed to start new ${SERVICE} containers, stopping."
		exit 1;
	fi;

	for ID in ${NEW_IDS}; do
		echo "Waiting for ${ID:0:12} to become healthy..."
		if [ "$(containerHealth "${ID}")" = "none" ]; then
			echo "${ID:0:12} has no healthcheck, can't tell when it is ready."
			sleep 10;
		elif ! waitForHealth "${ID}" healthy "${HEALTH_TIMEOUT}"; then
			echo "${ID:0:12} did not become healthy ($(containerHealth "${ID}")), removing new containers and stopping."
			docker logs --tail 20 "${ID}"
			docker rm -f ${NEW_IDS}
			exit 1;
		fi;
	done;

	# Give traefik time to start routing to the new containers.
	sleep "${TRAEFIK_GRACE}";

	echo "Draining old ${SERVICE} containers...";
	for ID in ${OLD_IDS}; do
		docker exec "${ID}" touch /tmp/drain
	done;

	for ID in ${OLD_IDS}; do
		if [ "$(containerHealth "${ID}")" = "none" ]; then
			echo "${ID:0:12} has no healthcheck, can't drain it first."
		elif ! waitForHealth "${ID}" unhealthy "${DRAIN_TIMEOUT}"; then
			echo "${ID:0:12} did not drain, stopping it anyway."
		fi;
	done;

	# Give traefik time to stop routing to the old containers.
	sleep "${TRAEFIK_GRACE}";

	for ID in ${OLD_IDS}; do
		echo "Stopping old container: ${ID:0:12}";
		docker stop "${ID}" >/dev/null
		docker rm -f "${ID}" >/dev/null
	done;
}

# Bring up everything else first. --no-deps stops this touching the rolling
# services (most things depend on api), so they only get recreated below.
OTHER_SERVICES=$(docker compose config --services | grep -vxF "$(printf '%s\n' "${ROLLING_SERVICES[@]}")")

echo "Starting all..."
docker compose up -d --no-deps --remove-orphans ${OTHER_SERVICES}

# Anything with a healthcheck (eg the database) needs to be up before new
# api/web containers can start properly.
for SERVICE in ${OTHER_SERVICES}; do
	for ID in $(docker compose ps -q "${SERVICE}"); do
		if [ "$(containerHealth "${ID}")" != "none" ]; then
			echo "Waiting for ${SERVICE} to become healthy..."
			if ! waitForHealth "${ID}" healthy "${HEALTH_TIMEOUT}"; then
				echo "${SERVICE} did not become healthy ($(containerHealth "${ID}")), stopping."
				exit 1;
			fi;
		fi;
	done;
done;

for SERVICE in "${ROLLING_SERVICES[@]}"; do
	rollingUpdate "${SERVICE}"
done;
