#!/bin/sh
cd /scripts/statuscake-updater
composer install

cd /scripts/gather-statistics
composer install
