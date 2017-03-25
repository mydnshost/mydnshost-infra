#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"

cd "${DIR}/nginx-proxy/"
docker-compose down

cd "${DIR}"
docker-compose down
