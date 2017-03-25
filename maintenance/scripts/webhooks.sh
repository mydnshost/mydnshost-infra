#!/bin/sh
export PATH=${PATH}:/scripts/

FREQUENCY="${1}"

if [ "${FREQUENCY}" = "" ]; then
	echo "Please specify a frequency."
	exit 1;
fi;

curl --silent --unix-socket /var/run/docker.sock "http:/containers/json" |
    /scripts/jq -r '.
                    | map(first(select(.Labels
                                       | keys
                                       | .[]
                                       | match("uk.co.mydnshost.maintenance.webhook"))))
                    | .[] .Id' | while read CID; do
	JSON=`mktemp`
	curl --silent --unix-socket /var/run/docker.sock "http:/containers/${CID}/json" > "${JSON}"
	HOOKHOST=`jq -r '.NetworkSettings.Networks."mydnshost_mydnshost-internal".IPAddress' "${JSON}"`

	# Find all hooks.
	/scripts/jq -r '.Config.Labels
                    | keys
                    | map(select(capture("uk.co.mydnshost.maintenance.webhook.[0-9]+.hook")))
                    | .[]
                    | capture("uk.co.mydnshost.maintenance.webhook.(?<hookid>[0-9]+).hook")
                    | .hookid' "${JSON}" | while read HOOKID; do

		HOOK=`jq -r '.Config.Labels."uk.co.mydnshost.maintenance.webhook.'${HOOKID}'.hook"' "${JSON}"`
		HOOKFREQUENCY=`jq -r '.Config.Labels."uk.co.mydnshost.maintenance.webhook.'${HOOKID}'.frequency"' "${JSON}"`
		LOCALHOOKKEY=`jq -r '.Config.Labels."uk.co.mydnshost.maintenance.webhook.'${HOOKID}'.key"' "${JSON}"`

		if [ "${LOCALHOOKKEY}" = "null" ]; then
			LOCALHOOKKEY=${HOOKKEY}
		fi;

		if [ "${HOOKFREQUENCY}" = "${FREQUENCY}" ]; then
			echo "========================================";
			echo "Running ${FREQUENCY} hook for container: ${CID}";
			echo "========================================";
			echo "http://${HOOKHOST}/${HOOK}";
			echo "====================";
			wget -qO- --header="X-HOOK-KEY: ${LOCALHOOKKEY}" "http://${HOOKHOST}/${HOOK}"
			echo "========================================";
		fi;

	done;

	rm -Rf "${JSON}"
done;

exit 0;




