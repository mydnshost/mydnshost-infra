#!/bin/bash

# First time run needs longer.
export COMPOSE_HTTP_TIMEOUT=600

DIR="$(dirname "$(readlink -f "$0")")"

cd "${DIR}"

# Our main project name
export COMPOSE_PROJECT_NAME=mydnshost

touch traefik/acme.json
chmod 600 traefik/acme.json

# Update images
echo 'Updating images...';
docker-compose pull
# cat docker-compose.yml docker-compose.override.yml | grep -i "image:" | sort -u | awk '{print $2}' | while read IMAGE; do docker pull ${IMAGE}; done
# docker pull mydnshost/mydnshost-api
# docker pull mydnshost/mydnshost-frontend
# docker pull mydnshost/mydnshost-bind
# docker pull mydnshost/mydnshost-docker-cron

function prepareAPIContainers() {
	docker ps -a --format '{{.Names}}' | grep -i mydnshost_api_ | while read NAME; do
		docker exec -t "${NAME}" chown www-data: /bind
		docker exec -t "${NAME}" su www-data --shell=/bin/bash -c "/dnsapi/admin/init.php"
	done;
}

api_VERSION=`docker inspect $(docker images mydnshost/mydnshost-api --format "{{.ID}}") | "${DIR}/jq" .[0].Id`
web_VERSION=`docker inspect $(docker images mydnshost/mydnshost-frontend --format "{{.ID}}") | "${DIR}/jq" .[0].Id`

# Create any needed containers.
# echo 'Creating...';
# docker-compose up --no-start

# Rebuild running stateless containers if needed by scaling up then killing off the older containers.
for IMAGE in api web; do
        RUNNING=`docker-compose ps "${IMAGE}" | grep " Up "`
        if [ "" != "${RUNNING}" ]; then
		echo 'Checking '${IMAGE}'...';
		NEED_UPGRADE="0";

		while read NAME; do
			ID=`docker ps --filter name="${NAME}" --format {{.ID}}`
			MY_VERSION=`docker inspect "${ID}" | "${DIR}/jq" .[0].Image`
			IMAGE_VERSION="${IMAGE}_VERSION"

			if [ "${MY_VERSION}" != "${!IMAGE_VERSION}" ]; then
				echo "${NAME} needs upgrading."
				NEED_UPGRADE="1"
			else
				echo "${NAME} is up to date."
			fi;
		done <<< $(docker-compose ps "${IMAGE}" | grep " Up " | awk '{print $1}')

		if [ "${NEED_UPGRADE}" = "1" ]; then
			echo 'Updating with scale...';

			# Scale up to 2 to start new container.
			echo 'Scaling up container: '"${NAME}";
	                docker-compose up -d --no-deps --no-recreate --scale "${IMAGE}"=2 "${IMAGE}"

			# Prepare all containers
			# if [ "${IMAGE}" = "api" ]; then
			# 	prepareAPIContainers;
			# fi;

			# Wait for traefik
			sleep 2;

			echo 'Scaling back down...';
			# Kill off older containers.
			docker-compose ps "${IMAGE}" | grep " Up " | sort -V | head -n -1 | awk '{print $1}' | while read NAME; do
				echo 'Stopping older container: '"${NAME}";
				ID=`docker ps --filter name="${NAME}" --format {{.ID}}`
				docker stop "${ID}"
				docker rm -f "${ID}"
			done;
		fi;
        fi;
done;

# Rebuild any single-instance containers if needed.
for IMAGE in bind maintenance; do
	RUNNING=`docker-compose ps "${IMAGE}" | grep " Up "`
	if [ "" != "${RUNNING}" ]; then
		echo 'Checking '${IMAGE}'...';
		docker-compose up -d --no-deps "${IMAGE}"
	fi;
done;

DB_RUNNING=`docker-compose ps database | grep " Up "`

echo "Starting all..."
docker-compose up -d --remove-orphans


# if [ "" = "${DB_RUNNING}" ]; then
# 	echo "Waiting for database to start..."
# 	sleep 10;
# fi;

# prepareAPIContainers;
