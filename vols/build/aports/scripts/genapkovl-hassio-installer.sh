#!/bin/sh -e

HOSTNAME="$1"
#HOSTNAME="hassio-installer"
if [ -z "$HOSTNAME" ]; then
	echo "usage: $0 hostname"
	exit 1
fi

cleanup() {
	rm -rf "$tmp"
}

makefile() {
	OWNER="$1"
	PERMS="$2"
	FILENAME="$3"
	cat > "$FILENAME"
	chown "$OWNER" "$FILENAME"
	chmod "$PERMS" "$FILENAME"
}

rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

mkdir -p "$tmp"/etc
makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF

makefile root:root 0644 "$tmp"/etc/inittab <<EOF
# /etc/inittab

::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

# Set up a couple of getty's
tty1::respawn:/bin/login -f root
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3
tty4::respawn:/sbin/getty 38400 tty4
tty5::respawn:/sbin/getty 38400 tty5
tty6::respawn:/sbin/getty 38400 tty6

# Put a getty on the serial port
#ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100

# Stuff to do for the 3-finger salute
::ctrlaltdel:/sbin/reboot

# Stuff to do before rebooting
::shutdown:/sbin/openrc shutdown
EOF

mkdir -p "$tmp"/etc/network
makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF

mkdir -p "$tmp"/etc/apk
makefile root:root 0644 "$tmp"/etc/apk/world <<EOF
alpine-base
dialog
git
bash
iwd
pv
parted
hdparm
nvme-cli
curl
ntfs-3g
ntfs-3g-progs
EOF

makefile root:root 0644 "$tmp"/etc/motd <<EOF
Welcome to Home Assistant OS Installer

For script options, type /installer.sh --help
For issues and bug report refer to : https://github.com/maretodoric/hassio-installer

Please make sure to read Bug Report Guidelines before opening to make sore you have all the details correct.

EOF

mkdir -p "$tmp"/root
makefile root:root 0644 "$tmp"/root/.profile <<EOF
l() {
	local log_level
	local func=\$1
	shift

	case \$1 in
		"i") log_level="INFO"; shift ;;
		"e") log_level="ERROR"; shift ;;
		"w") log_level="WARNING"; shift ;;
		"d") log_level="DEBUG"; shift ;;
		*) log_level="INFO" ;;
	esac

	logger -t \$func[\$$] "\$log_level \${@}"
}

_exit() {
	local opt
	opt=\$(dialog --stdout --no-cancel --title "Exit Menu (DEBUG MODE)" --clear --menu "Select action below - Defaults to reboot" 10 55 5 1 "Reboot Host" 2 "Upload Logs" 3 "Restart Installer")
	case \$opt in
		1) reboot ;;
		2) /installer.sh --collect-logs; reboot ;;
		3) logout ;;
		*) reboot ;;
	esac
}

export -f l

#### HANDLE KERNEL PARAMETERS ####
# Debug logging
if grep -q 'hass.debug=1' /proc/cmdline; then
	export DEBUG=true
else
	export DEBUG=false
fi

# Testing - no reboot
if grep -q 'hass.test=1' /proc/cmdline; then
	export HOSTNAME='test'
fi

# Fake pastebin reply
if grep -q 'hass.fake_url=1' /proc/cmdline; then
	export FAKE_URL=true
else
	export FAKE_URL=false
fi

# Fake image write
if grep -q 'hass.fake_image=1' /proc/cmdline; then
	export FAKE_IMAGE=true
else
	export FAKE_IMAGE=false
fi

# Starting installer only on tty1
if [ "\$(tty)" == "/dev/tty1" ]; then
	/bin/bash /installer.sh
	ec=\$?
	clear

	if \$DEBUG; then
		if [ \$ec -eq 141 ]; then
			_exit
		else
			l main-login-shell d "Exit code: \$ec"
			echo Exit Code: \$ec
		fi
	fi

	# Handle Installer Reload
	if [ -f /tmp/_reload_installer ]; then
		echo "Restarting installer..."
		sleep 2
		rm -rf /tmp/_reload_installer
		logout
	fi
fi
EOF

mkdir -p "$tmp"/etc/init.d
makefile root:root 0755 "$tmp"/etc/init.d/bashdefault <<EOF
#!/sbin/openrc-run
# Copyright (c) 2007-2015 The OpenRC Authors.
# See the Authors file at the top-level directory of this distribution and
# https://github.com/OpenRC/openrc/blob/master/AUTHORS
#
# This file is part of OpenRC. It is subject to the license terms in
# the LICENSE file found in the top-level directory of this
# distribution and at https://github.com/OpenRC/openrc/blob/master/LICENSE
# This file may not be copied, modified, propagated, or distributed
# except according to the terms contained in the LICENSE file.

description="Make /bin/bash default shell"

start()
{
	ebegin "Making /bin/bash default shell"
	sed -i 's|/bin/ash|/bin/bash|g' /etc/passwd && sync
}

stop()
{
	ebegin "Reverting default shell to /bin/ash"
	sed -i 's|/bin/bash|/bin/ash|g' /etc/passwd && sync
}
EOF

cp /build/aports/custom-scripts/installer.sh "$tmp"/

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit
rc_add bashdefault sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

cp -R /build/aports/custom-scripts/drivers_rootfs/* "$tmp"/
tar -c -C "$tmp" . | gzip -9n > $HOSTNAME.apkovl.tar.gz
