#!/bin/sh

mkdir -p /bind/keys
chmod a+w /bind/

ls -1 /bind/zones/ | while read ZONE; do
	EXT=${ZONE##*.}
	ZONE=${ZONE%.*}
	if [ "${EXT}" = "db" -a -e "/bind/zones/${ZONE}.db" ]; then
		KEYS=`ls '/bind/keys/K'"${ZONE}"*'.key' 2>/dev/null`

		if [ "${KEYS}" = "" ]; then
			echo "Generating Keys for: ${ZONE}"
			dnssec-keygen -r /dev/urandom -a RSASHA256 -b 2048 -K /bind/keys/ -f KSK ${ZONE}
			dnssec-keygen -r /dev/urandom -a RSASHA256 -b 1024 -K /bind/keys/ ${ZONE}

			rndc loadkeys ${ZONE}
			rndc sign ${ZONE}
		fi;
	fi;
done;


