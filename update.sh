#!/bin/bash

# First time run needs longer.
export COMPOSE_HTTP_TIMEOUT=600

DIR="$(dirname "$(readlink -f "$0")")"

export GIT_SSH="${DIR}/git-ssh"

if [ ! -e "${DIR}/api/Dockerfile" ]; then
	export REPOKEY="${HOME}/.ssh/id_rsa_api"
	git clone git@github.com:ShaneMcC/mydnshost-api.git "${DIR}/api"
fi;

if [ ! -e "${DIR}/frontend/Dockerfile" ]; then
	export REPOKEY="${HOME}/.ssh/id_rsa_frontend"
	git clone git@github.com:ShaneMcC/mydnshost-frontend.git "${DIR}/frontend"
fi;

if [ ! -e "${DIR}/bind/Dockerfile" ]; then
	export REPOKEY="${HOME}/.ssh/id_rsa_bind"
	git clone git@github.com:ShaneMcC/mydnshost-bind.git "${DIR}/bind"
fi

if [ ! -e "${DIR}/nginx-proxy/docker-compose.yml" ]; then
        git clone https://github.com/csmith/docker-automatic-nginx-letsencrypt.git "${DIR}/nginx-proxy/"
fi;

if [ ! -e "${DIR}/api/Dockerfile" -o ! -e "${DIR}/frontend/Dockerfile" -o ! -e "${DIR}/bind/Dockerfile" -o ! -e "${DIR}/nginx-proxy/docker-compose.yml" ]; then
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

APIVERSION=`git --git-dir="${DIR}/api/.git" describe --tags`
FRONTENDVERSION=`git --git-dir="${DIR}/frontend/.git" describe --tags`
BINDVERSION=`git --git-dir="${DIR}/bind/.git" describe --tags`

for REPODIR in "${DIR}/api" "${DIR}/frontend" "${DIR}/bind"; do
        echo "Updating '${REPODIR##*/}'.."
        cd "${REPODIR}"
        export REPOKEY="${HOME}/.ssh/id_rsa_${REPODIR##*/}"
        git reset --hard
        git checkout master
        git fetch origin
        git reset --hard origin/master
        git submodule update --init --recursive
        echo ""
done;

NEW_APIVERSION=`git --git-dir="${DIR}/api/.git" describe --tags`
NEW_FRONTENDVERSION=`git --git-dir="${DIR}/frontend/.git" describe --tags`
NEW_BINDVERSION=`git --git-dir="${DIR}/bind/.git" describe --tags`

docker-compose up -d

if [ "${NEW_APIVERSION}" != "${APIVERSION}" ]; then
	docker-compose build --no-cache api
	docker-compose up -d --no-deps api
fi;

if [ "${NEW_FRONTENDVERSION}" != "${FRONTENDVERSION}" ]; then
	docker-compose build --no-cache web
	docker-compose up -d --no-deps web
fi;

if [ "${NEW_BINDVERSION}" != "${BINDVERSION}" ]; then
	docker-compose build --no-cache bind
	docker-compose up -d --no-deps bind
fi;

# The nginx-hupper sucks, so force-hup it.
curl -X POST --silent --unix-socket /var/run/docker.sock "http:/containers/autoproxy_nginx/kill?signal=SIGHUP"

echo "Waiting for start..."
sleep 10;

docker exec -it mydnshost_api ln -sf /dnsapi/examples/hooks/bind.php /dnsapi/hooks/bind.php
docker exec -it mydnshost_api su www-data --shell=/bin/bash -c "/dnsapi/admin/init.php"

