#!/bin/bash

# First time run needs longer.
export COMPOSE_HTTP_TIMEOUT=600

DIR="$(dirname "$(readlink -f "$0")")"

export GIT_SSH="${DIR}/git-ssh"

if [ ! -e "${DIR}/nginx-proxy/docker-compose.yml" ]; then
        git clone https://github.com/csmith/docker-automatic-nginx-letsencrypt.git "${DIR}/nginx-proxy/"
fi;

if [ ! -e "${DIR}/nginx-proxy/docker-compose.yml" ]; then
	echo 'Unable to obtain dependencies, aborting.';
	exit 1;
fi;

echo "DEPS OK";

cd "${DIR}/nginx-proxy/"
git reset --hard
git checkout master
git fetch origin
git reset --hard origin/master
git submodule update --init --recursive
rm -Rfv "${DIR}/nginx-proxy/docker-compose.override.yml";
ln -s "${DIR}/automagic-override.yml" "${DIR}/nginx-proxy/docker-compose.override.yml"
docker-compose up -d

# Extra files that we want.
docker cp extra/hsts.conf autoproxy_nginx:/etc/nginx/conf.d/
docker cp extra/security.conf autoproxy_nginx:/etc/nginx/conf.d/
docker cp extra/ssl.conf autoproxy_nginx:/etc/nginx/conf.d/
docker cp ../nginx-default.conf autoproxy_nginx:/etc/nginx/conf.d/

cd "${DIR}"

# Update images
docker pull mydnshost/mydnshost-api
docker pull mydnshost/mydnshost-frontend
docker pull mydnshost/mydnshost-bind
docker pull mydnshost/mydnshost-docker-cron

api_VERSION=`docker inspect $(docker images mydnshost/mydnshost-api --format "{{.ID}}") | "${DIR}/maintenance/scripts/jq" .[0].Id`
web_VERSION=`docker inspect $(docker images mydnshost/mydnshost-frontend --format "{{.ID}}") | "${DIR}/maintenance/scripts/jq" .[0].Id`

# Rebuild running stateless containers if needed by scaling up then killing off the older containers.
for IMAGE in api web; do
        RUNNING=`docker-compose ps "${IMAGE}" | grep " Up "`
        if [ "" != "${RUNNING}" ]; then
		NEED_UPGRADE="0";

		while read NAME; do
			ID=`docker ps --filter name="${NAME}" --format {{.ID}}`
			MY_VERSION=`docker inspect "${ID}" | "${DIR}/maintenance/scripts/jq" .[0].Image`
			IMAGE_VERSION="${IMAGE}_VERSION"

			if [ "${MY_VERSION}" != "${!IMAGE_VERSION}" ]; then
				echo "${NAME} needs upgrading."
				NEED_UPGRADE="1"
			else
				echo "${NAME} is up to date."
			fi;
		done <<< $(docker-compose ps "${IMAGE}" | grep " Up " | awk '{print $1}')

		if [ "${NEED_UPGRADE}" = "1" ]; then
			# Scale up to 2 to start new container.
			echo 'Scaling up container: '"${NAME}";
	                docker-compose up -d --no-deps --scale "${IMAGE}"=2 "${IMAGE}"

			# Kill off older containers.
			docker-compose ps "${IMAGE}" | grep " Up " | head -n -1 | awk '{print $1}' | while read NAME; do
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
		docker-compose up -d --no-deps "${IMAGE}"
	fi;
done;

docker-compose up -d

echo "Waiting for start..."
sleep 10;

docker ps -a --format '{{.Names}}' | grep -i mydnshost_api_ | while read NAME; do
	docker exec -t "${NAME}" ln -sf /dnsapi/examples/hooks/bind_workers.php /dnsapi/hooks/bind.php
	docker exec -t "${NAME}" ln -sf /dnsapi/examples/hooks/webhook_workers.php /dnsapi/hooks/webhook.php
	docker exec -t "${NAME}" chown www-data: /bind
	docker exec -t "${NAME}" su www-data --shell=/bin/bash -c "/dnsapi/admin/init.php"
done;
