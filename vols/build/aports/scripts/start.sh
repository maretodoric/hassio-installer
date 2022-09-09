#!/bin/bash


SD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $SD

# Get the installer version
if [ -z $RELEASE ]; then
	INSTALLER_VERSION=test
else
	eval $(egrep '^export INSTALLER_VERSION' ../custom-scripts/installer.sh)
fi

if [ "$SD" == "/build/aports/scripts" ] && [ "$(whoami)" == "build" ]; then
./mkimage.sh --tag $INSTALLER_VERSION \
	--outdir ~/iso \
	--arch x86_64 \
	--repository http://dl-cdn.alpinelinux.org/alpine/v3.16/main \
	--repository http://dl-cdn.alpinelinux.org/alpine/v3.16/community \
	--profile hassio_installer
else
	echo "This script was not meant to be started this way"
	exit 1
fi
