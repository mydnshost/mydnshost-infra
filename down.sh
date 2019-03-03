#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"

cd "${DIR}"
docker-compose down
