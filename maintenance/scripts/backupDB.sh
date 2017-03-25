#!/bin/sh
export PATH=${PATH}:/scripts/

TODAY=`date +'%d-%b-%Y'`
NOW=`date +'%d-%b-%Y-%H-%M'`
BACKUPDIR=/output/mysqlbackup
mkdir -p "${BACKUPDIR}"

curl --silent --unix-socket /var/run/docker.sock "http:/containers/json" | /scripts/jq -r '.[] | select(.Labels."uk.co.mydnshost.maintenance.db.backup" == "true") | .Id' | while read CID; do
	echo "========================================";
	echo "Container: ${CID}";
	echo "====================";
	JSON=`mktemp`
	curl --silent --unix-socket /var/run/docker.sock "http:/containers/${CID}/json" > "${JSON}"

	CHOST=`jq -r '.Config.Hostname + "." + .Config.Domainname' "${JSON}"`
	DBUSER=`jq -r '.Config.Labels."uk.co.mydnshost.maintenance.db.user"' "${JSON}"`
	DBPASS=`jq -r '.Config.Labels."uk.co.mydnshost.maintenance.db.pass"' "${JSON}"`
	DBs=`jq -r '.Config.Labels."uk.co.mydnshost.maintenance.db.dbs"' "${JSON}" | sed "s/,/ /g"`
	DBHOST=`jq -r '.NetworkSettings.Networks."mydnshost_mydnshost-internal".IPAddress' "${JSON}"`

	for DB in ${DBs}; do
		echo "Backing up DB: ${DB}"
		echo "====================";
		LOCATION="${BACKUPDIR}/${CHOST}/${TODAY}/${DB}"
		mkdir -p "${LOCATION}"

		export MYSQL_PWD="${DBPASS}"
		echo "Check:"
	    /usr/bin/mysqlcheck -u"${DBUSER}" -h"${DBHOST}" --auto-repair --check "${DB}"
	    echo "Optimize:"
	    /usr/bin/mysqlcheck -u"${DBUSER}" -h"${DBHOST}" --auto-repair --optimize "${DB}"
	    echo "Dump:"
	    /usr/bin/mysqldump -u"${DBUSER}" -h"${DBHOST}" --hex-blob --lock-tables --databases --single-transaction "${DB}" > "${LOCATION}/backup-${NOW}.sql" 2> "${LOCATION}/error-${NOW}.txt"

		ERRORS=`cat "${LOCATION}/error-${NOW}.txt"`
		if [ "${ERRORS}" = "" ]; then
			rm "${LOCATION}/error-${NOW}.txt";
		fi;
		echo "====================";
	done

	rm -Rf "${JSON}"
	echo "Backups completed.";
	echo "========================================";
	echo "";
done;

find "${BACKUPDIR}/" -mtime +30 -exec rm -Rf {}  \;

exit 0;
