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

# Rebuild any running containers if needed.
for IMAGE in api web bind maintenance; do
        RUNNING=`docker-compose ps "${IMAGE}" | grep " Up "`
        if [ "" != "${RUNNING}" ]; then
                docker-compose up -d --no-deps "${IMAGE}"
        fi;
done;

docker-compose up -d

echo "Waiting for start..."
sleep 10;

docker exec -it mydnshost_api ln -sf /dnsapi/examples/hooks/bind.php /dnsapi/hooks/bind.php
docker exec -it mydnshost_api chown www-data: /bind
docker exec -it mydnshost_api su www-data --shell=/bin/bash -c "/dnsapi/admin/init.php"
