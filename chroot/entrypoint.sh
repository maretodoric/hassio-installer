#!/bin/bash

if [ ! "$(whoami)" == "build" ]; then
	echo "Need to use build user for container to work"
	exit 1
else
	export USER=build
fi

if [ -d /build/.abuild ] && [ -f /build/.abuild/abuild.conf ]; then
	. /build/.abuild/abuild.conf
	if [ -f $PACKAGER_PRIVKEY ] && [ -f ${PACKAGER_PRIVKEY}.pub ]; then
		echo "Using existig key in ${PACKAGER_PRIVKEY}"
		sudo cp ${PACKAGER_PRIVKEY}.pub /etc/apk/keys/
	else
		echo "abuild directory and config file is present but not the keys, creating new pairs"
		rm -rf /build/.abuild
		abuild-keygen -a -i -n
	fi
else
	echo "abuild directory and/or config file is not present, creating new pairs"
	abuild-keygen -a -i -n
fi


cd /build/aports/scripts
exec $@
