#!/bin/sh
export PATH=${PATH}:/scripts/

TODAY=`date +'%d-%b-%Y'`
NOW=`date +'%d-%b-%Y-%H-%M'`
BACKUPDIR=/output/bindbackup
mkdir -p "${BACKUPDIR}/${TODAY}/"

echo "========================================";
echo "Bind Data";
echo "====================";
tar -zcvf "${BACKUPDIR}/${TODAY}/backup-${NOW}.tgz" /bind/
echo "Backups completed.";
echo "========================================";
echo "";

find "${BACKUPDIR}/" -mtime +30 -exec rm -Rf {}  \;

exit 0;
