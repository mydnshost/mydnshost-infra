#!/bin/bash

export COMPOSE_PROJECT_NAME=mydnshost
DIR="$(dirname "$(readlink -f "$0")")"

cd "${DIR}"
docker compose down
