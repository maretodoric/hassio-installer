#!/bin/bash

SD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MYNAME=$(basename $SD/$(basename $0))
cd $SD

_customCmd() {
	if [ ! x"$cmd" == "x" ]; then
		echo "Custom command used, parameters will be ignored"
		exit
	fi
}

_help() {

cat << EOF
Usage: $MYNAME [options...] <cmd>

Options:
 --rm                             Will remove ISO file after creation
 --send-to <host> or <user@host>  This will SCP the ISO after build is completed to host
 --release                        This will tag the ISO with version instead of "test".
                                  Version will be used from vols/build/aports/custom-scripts/installer.sh

<cmd> is optional, you can use "bash" here to enter docker container itself rather than to trigger a build.
If ommited , it will trigger standard ISO build - if provided, all other parameters will be ignored.
EOF
}

until [ $# -eq 0 ]; do
	case $1 in
		"--rm") REMOVE=1 ;;
		"--send-to"*|"--upload-to"*)
                        if [[ $1 =~ \= ]]; then
                                IFS='=' read -r opt REMOTE_HOST <<< $1
                        else
                                shift
                                REMOTE_HOST=$1
                        fi
                        if ! [[ $REMOTE_HOST =~ : ]]; then
                                REMOTE_HOST=${REMOTE_HOST}:
                        fi
                        ;;
		"--release"|"--publish")
			echo "Publish requested, will tag with version instead of test"
			VARS="-e RELEASE=1"
			;;
		"--help"|"-h") _help; exit ;;
		*) cmd="${@}" ;;
	esac
	shift
done

SECONDS=0
docker run \
	-it \
	--rm \
	-v $SD/vols/build:/build \
	-v $SD/vols/tmp:/tmp \
	-u build \
	-a STDOUT -a STDERR \
	$VARS \
	alpine-build-iso ${cmd}
EC=$?
date -ud "@$SECONDS" "+Build time: %H:%M:%S"

if [ $EC -eq 0 ];then
	if [ ! -z "$REMOTE_HOST" ]; then
		_customCmd
		echo "Upload of ISO to remote host requested..."
		scp vols/build/iso/* ${REMOTE_HOST}
	fi

	if [ ! -z $REMOVE ]; then
		_customCmd
		echo "Auto-removing created ISO"
		rm -rfv vols/build/iso/*
	fi
fi
