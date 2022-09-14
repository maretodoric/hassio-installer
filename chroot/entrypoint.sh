#!/bin/bash

# User Check
if [ ! "$(whoami)" == "build" ]; then
	echo "Need to use build user for container to work"
	exit 1
fi

# Permission Check
find /build ! -user build | sudo xargs -r chown build
find /build ! -group abuild | sudo xargs -r chgrp abuild

# Keys Loading
if [ -d /build/.abuild ]; then
	rm -rf /build/.abuild
fi
sudo mv /.abuild /build/

cd /build/aports/scripts
exec $@

# Removing /tmp
sudo rm -rf /tmp/*
