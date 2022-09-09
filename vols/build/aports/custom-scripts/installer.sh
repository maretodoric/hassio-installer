#!/bin/bash

export INSTALLER_VERSION="v0.1.0"

#### HANDLE KERNEL PARAMETERS ####
if $DEBUG; then
	l main d "Booted in debug mode. Verbose logging will be in /var/log/messages"
	exec 5> >(logger -t "main-debug[$$]")
	BASH_XTRACEFD="5"
	PS4='DEBUG ($LINENO): '
	set -x
fi

#### DEFINE VARIABLES ####
declare -A VERSIONS
declare -a INTERFACES
export DISK DISKS VERSIONS VERSION SECONDS INTERFACES
export STAGE=start
export DIALOG_TITLE="Home Assistant OS Installer"
export ROOT_FS_FOUND=false
export pidfile=/tmp/installer.pid

trap _exit SIGINT

isok() {
	if [ $1 -eq 0 ]; then
		l ${FUNCNAME:-main} Previous command finished successfully.
		return 0
	else
		l ${FUNCNAME:-main} Previous command exited with $?.
		if [ "$2" == "reboot" ]; then
			l ${FUNCNAME:-main} Reboot called on failed command.
			if [ "$HOSTNAME" == "hassio-installer" ]; then
				_reboot "$3"
			else
				exit 
			fi
		else
			return 1
		fi
	fi
}

_exit() {
	local opt
	opt=$(dialog --stdout --no-cancel --title "Exit Menu (DEBUG MODE)" --clear --menu "Select action below - Defaults to reboot" 10 55 5 1 "Reboot Host" 2 "Upload Logs" 3 "Restart Installer")
	case $opt in
		1) reboot ;;
		2) _collectlogs ; reboot ;;
		3) touch /tmp/_reload_installer; rm -rf $pidfile ; exit ;;
		*) reboot ;;
	esac
}

_dialog_menu() {
	local IFS='|'
	local menu_title="$1"
	shift
	local menu_content="$@"
	dialog --stdout --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}" --clear --no-cancel --menu "$menu_title" 10 55 0 ${menu_content}
	return $?
}

_dialog_progress() {
    dialog --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}"  --clear --gauge "${1}" 10 110
}

_dialog_msg() {
    dialog --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}" --clear --msgbox "${@}" 10 60
}

_dialog_info() {
	dialog --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}" --infobox "${@}" 10 55
}

_collectlogs() {
	l ${FUNCNAME:-main} Collecting logs...
	_dialog_info "Collecting logs, please wait..."

	local url
	local count=0
	local alive=false
	local disks=$(fdisk -l | grep -E '^Disk /dev.*:' | grep -Eo '/dev/(sd[a-z]|mmcblk[0-9]|nvme[0-9]+n[0-9]+)')

	l ${FUNCNAME:-main} Checking internet connection...
	until [ $count -eq 3 ] || $alive; do
		l ${FUNCNAME:-main} "Try: $count"
		ping -c1 pastebin.com > /dev/null 2>&1 && alive=true
		count=$((count+1))
		sleep 1
	done

	SECONDS=$SECONDS
	for i in env export "ip a" "ip r" "/etc/init.d/networking status" "fdisk -l" "hdparm -I $disks"; do
		l ${FUNCNAME:-main} "Collecting output from command $i"
		echo "=== START $i ===" >> /debug.log
		eval $i >> /debug.log 2>&1
		echo -e "=== END $i ===\n" >> /debug.log
	done

	for i in /proc/cpuinfo /proc/meminfo \
		/sys/class/net/*/operstate /sys/block/sd*/size \
		/sys/block/nvm*/size /sys/block/sd*/queue/rotational \
		/sys/block/nvm*/queue/rotational /var/log/messages; do
		if [ -f $i ]; then
			l ${FUNCNAME:-main} "Collecting output from file $i"
			echo "=== START $i ===" >> /debug.log
			cat $i >> /debug.log
			echo -e "=== END $i ===\n" >> /debug.log
		fi
	done

	if $alive; then
		l ${FUNCNAME:-main} Trying to upload log bundle to pastebin
		url=$(curl -s \
			-d 'api_paste_expire_date=6M' \
			-d 'api_paste_private=1' \
			-d 'api_dev_key=aNGaTBNFGgQG7qVz5SW0ueUgEcMPumiq' \
			-d 'api_option=paste' \
			--data-urlencode 'api_paste_code@/debug.log' \
			"https://pastebin.com/api/api_post.php" | tee -a /debug.log)
		$FAKE_URL && url="Pastebin Post limit reached"
		if [[ $url =~ https ]]; then
			l ${FUNCNAME:-main} "URL For log bundle created: $url"
			_dialog_msg "URL for debug log is: $url\nPlease write down this URL as it is since it's case sensitive or take a screenshot and note when reporting an issue."
		elif [[ $url =~ .*"Post limit".* ]]; then
			_dialog_msg "Unable to upload log to Pastebin due to reached limit.\nPlease insert flash drive where to save the log and press ENTER."
			_upload_to_flashdrive
		else
			l e ${FUNCNAME:-main} "Unable to generate pastebin URL! Variable is: $url"
			_dialog_msg "ERROR!\nUnable to generate pastebin URL. Message from API is: ${url}\nLog is saved to /debug.log. Please extract it and post it when reporting a new issue"
		fi
	else
		l w ${FUNCNAME:-main} "Internet connection does not appear to be established in order to upload logs"
		_dialog_msg "Internet connection does not appear to be established.\nLog is saved in /debug.log. Please extract it and post it when reporting a new issue"
	fi
}

_upload_to_flashdrive() {
	declare -A parttype
	local parttype
	local parts=()

	while true; do
		parts=()
		while IFS=': ' read part type; do
			if [[ $type =~ .*hassos|iso9660|squashfs|alpine.* ]]; then
				continue
			else
				eval $(echo $type)
				case $TYPE in
					"ntfs") TYPE="ntfs-3g"
				esac

				mount -t $TYPE $part /mnt &>/dev/null
				ec=$?
				if [ $ec -eq 13 ] && [[ $TYPE == ntfs-3g ]]; then
					dialog --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}" --prgbox "echo Found bad NTFS partition, trying to fix...; ntfsfix $part" 20 55
					sleep 1
					mount -t $TYPE $part /mnt &>/dev/null
					ec=$?
				fi

				if [ $ec -eq 0 ]; then
					if touch /mnt/test.$$ 2>/dev/null; then
						rm -rf /mnt/test.$$
						umount /mnt
					else
						umount /mnt
						continue
					fi
				else
					continue
				fi
				rootpath=$(dirname $(find -L /sys/block -maxdepth 2 -type d -name $(basename $part)))
				partpath="$rootpath/$(basename $part)"
				size="$(expr $(cat $partpath/size) / 2097152)GB"
				model="$(<$rootpath/device/vendor) $(<$rootpath/device/model)"
				parttype[$part]=$TYPE
				if [ x"${parts[0]}" == "x" ]; then
					parts+=( "$part|$size ($TYPE) $model" )
				else
					parts+=( "|$part|$size ($TYPE) $model" )
				fi
			fi
		done < <(blkid)

		if [ x"${parts[0]}" == "x" ]; then
			parts+=( "r|No drives found. Re-scan drives")
		else
			parts+=( "|r|Re-scan drives")
		fi
		part=$(_dialog_menu "Following drives are detected as writable.\nPlease select where to upload logs" "${parts[@]}")
		if ! isok $?; then
			continue
		elif [[ $part == r ]]; then
			continue
		else
			mount -t ${parttype[$part]} $part /mnt
			fname=$(date +"debug.%Y-%m-%dT%H%M%S.log")
			(pv -n -f /debug.log | cat >/mnt/$fname) 2>&1 | _dialog_progress "Copying log to $part"
			umount /mnt
			_dialog_msg "File saved as $fname. System will now reboot."
			break
		fi
	done
}

_reboot() {
	STAGE="${STAGE}+_reboot"
	l ${FUNCNAME:-main} Reboot requested.

	local msg

	if ! [ x"$1" == "x" ]; then
		msg="$1\n"
	fi

	if $DEBUG; then
		l ${FUNCNAME:-main} "Collecting logs before reboot due to DEBUG=true"
		_collectlogs
	fi

	for i in {5..1} ; do _dialog_info "${msg}Will reboot in: $i"; sleep 1; done
	if [ "$HOSTNAME" == "hassio-installer" ]; then
		reboot
		exit
	else
		exit
	fi
}

_checkconnection() {
	STAGE="${STAGE}+${FUNCNAME}"

	l ${FUNCNAME:-main} Networking service not started, starting
	_dialog_info "Establishing network..."
	for i in /sys/class/net/*; do
		int=$(basename $i)
		if [ -d $i/wireless ] || [[ $int == lo ]]; then
			continue
		fi
		l ${FUNCNAME:-main} Adding local interface $int
		echo -e "auto $int\n" >> /etc/network/interfaces
		INTERFACES+=( $int )
	done
	service networking start > /dev/null 2>&1

	for int in ${INTERFACES[@]}; do
		l ${FUNCNAME:-main} "Attempting DHCP on eth0"
		_dialog_info "Attempting DHCP on $int"
		_trydhcp $int && return 0
	done

	_dialog_msg "Network setup failed. Please make sure you have the Ethernet cable plugged in.\nWireless setup currently unsupported."
	_reboot
}

_gitping() {
	l ${FUNCNAME:-main} Testing network connection by reaching github.com
	_dialog_info "Testing network connection..."
	if git ls-remote --tags https://github.com/home-assistant/operating-system.git > /dev/null 2>&1; then
		l ${FUNCNAME:-main} Successfully tested network connection by reaching github.com
		return 0
	else
		return 1
	fi
}

_trydhcp() {
	STAGE="${STAGE}+${FUNCNAME}-$1"
	udhcpc -A 5 -T 5 -t 2 -n -S -p /tmp/dhcp.pid -i $1 &>/dev/null
	if ! _gitping; then
		return 1
	else
		return 0
	fi
}

_trywifi() {
	STAGE="${STAGE}+${FUNCNAME}"
	l ${FUNCNAME:-main} "Trying WiFi Connection, loading drivers"

	_dialog_info "Trying WiFi Connection, loading drivers"
	/etc/init.d/iwd start &> /dev/null
	isok $? reboot "Failed to start iwd, WiFi unavailable"

	# Easytether for Android
	apk add --allow-untrusted --force-non-repository /drivers/* &> /dev/null
	insmod $(find /.modloop -name tun.ko)
	easytether-usb > /dev/null 2>&1

	for dir in /sys/class/net/*/wireless; do
		[ -d $dir ] && IFACE="$IFACE $(basename $(dirname $dir))"
	done

	if [ -z $IFACE ]; then
		l ${FUNCNAME:-main} No wireless interfaces found.
		_reboot "Failed to configure WiFi, no wireless interfaces found"
	fi

	_reboot "Failed to obtain WiFi Connection"
}

_quick_erase() {
	for part in $(parted -s -f $DISK print 2>/dev/null | awk '{print $1}' | grep -Eo '[0-9]+'); do
		l ${FUNCNAME:-main} "Erasing partition $part of disk $DISK"
		parted -s -f $DISK rm $part > /dev/null 2>&1
	done
}

_full_erase() {
	local msg="${1}"
	l ${FUNCNAME:-main} "Erasing drive $DISK by writing zeroes to it..."
	(dd if=/dev/zero | pv -ns $((( $(cat /sys/block/$(basename $DISK)/size) * 512 ))) | dd of=$DISK status=none) 2>&1 | \
		_dialog_progress "$msg"
}

_secure_erase() {
	local OPT
	STAGE="${STAGE}+${FUNCNAME}"
	if [[ $DISK =~ nvme ]]; then
		STAGE="${STAGE}+${FUNCNAME}-nvme"

		l ${FUNCNAME:-main} Trying to Secure Erase NVMe Drive
		OPT=$(_dialog_menu "NVMe Sanitize not yet implemented. Select an option." "1|Fallback to Writing Zeroes|2|Fallback to Quick Erase|3|Abort operation and reboot")
		l ${FUNCNAME:-main} "Selected option: $OPT, exit code $?"
		case $OPT in
			1) return 99 ;;
			2) _quick_erase; return 0 ;;
			3) _reboot "Aborted NVMe Full Erase Operation" ;;
			*) _reboot "Unknown selection" ;;
		esac

		## We're not reaching this far, this is strictly for future implementation
		nvme id-ctrl $DISK -H | grep "Block Erase" | grep -qi not
		if isok $?; then
			return 3
		else
			nvme sanitize -a 2 $DISK
		fi
	else
		STAGE="${STAGE}+${FUNCNAME}-ssd"

		l ${FUNCNAME:-main} Trying to Secure Erase SSD
		hdparm -I $DISK | grep -qE 'not.*frozen'
		if ! isok $?; then
			STAGE="${STAGE}+${FUNCNAME}-ssd-frozen"
			l ${FUNCNAME:-main} "SSD Is frozen, trying to unfreeze it by placing system to suspend."
			dialog --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}" --yesno "SSD Appears to be frozen. In order to unfreeze it, i will place system to suspend.\nOnce suspended, press any key to resume and check again." 0 55
			if isok $?; then
				STAGE="${STAGE}+${FUNCNAME}-ssd-unfreezing"
				l ${FUNCNAME:-main} "Placing system to suspend"
				echo mem > /sys/power/state
				sleep 5
				STAGE="${STAGE}+${FUNCNAME}-ssd-unfreezing-done"
				l ${FUNCNAME:-main} "System resumed from suspend"
				hdparm -I $DISK | grep -qE 'not.*frozen'
				if ! isok $?; then
					STAGE="${STAGE}+${FUNCNAME}-ssd-unfreezing-fallingback"
					l w ${FUNCNAME:-main} "SSD Unfreeze appears unsuccessful, asking fallback methods"
					OPT=$(_dialog_menu "Failed to unfreeze SSD. Please select option below." "1|Fallback to Writing Zeroes|2|Fallback to Quick Erase|3|Abort operation and reboot")
					l ${FUNCNAME:-main} "Selected option $OPT, exit code: $?"
					case $OPT in
						1) return 1 ;;
						2) _quick_erase; return 0 ;;
						3) _reboot "Aborted SSD Full Erase Operation" ;;
						*) _reboot "Uknown selection" ;;
					esac
				fi
				STAGE="${STAGE}+${FUNCNAME}-ssd-unfreezing-ok"
			else
				STAGE="${STAGE}+${FUNCNAME}-ssd-unfreeze-aborted"
				l ${FUNCNAME:-main} "User did not agree with proposed option to unfreeze SSD, will reboot"
				_reboot "SSD Unfreeze aborted."
			fi
		fi
				
		l ${FUNCNAME:-main} "Secure Erasing SSD, not presenting Dialog window at the moment"
#		hdparm --user-master u --security-set-pass hass $DISK > /dev/null 2>&1
#		STAGE="${STAGE}+${FUNCNAME}-ssd-set-pass"
#		isok $? || return 1
#		STAGE="${STAGE}+${FUNCNAME}-ssd-secure-erasing"
#		hdparm --user-master u --security-erase hass $DISK | _dialog_progress "Secure Erasing SSD" || return 2
#		STAGE="${STAGE}+${FUNCNAME}-ssd-secure-erased"
#		return 0
		clear
		hdparm --user-master u --security-set-pass hass $DISK > /dev/null 2>&1
		STAGE="${STAGE}+${FUNCNAME}-ssd-set-pass"
		isok $? || return 1
		STAGE="${STAGE}+${FUNCNAME}-ssd-secure-erasing"
		hdparm --user-master u --security-erase hass $DISK
		l ${FUNCNAME:-main} "Secure Erase exited with: $?"
		STAGE="${STAGE}+${FUNCNAME}-ssd-secure-erased"
		echo "Press ENTER to continue"
		read
		clear
		return 0

	fi
}

_get_disks() {
	local disks
	
	STAGE="${STAGE}+${FUNCNAME}"
	DISKS=$(fdisk -l | grep -E '^Disk /dev.*:' | grep -Eo '/dev/(sd[a-z]|mmcblk[0-9]|nvme[0-9]+n[0-9]+)')

	for disk in $DISKS; do
			size="$(expr $(cat /sys/block/$(basename $disk)/size) / 2097152)GB"
			model="$(cat /sys/block/$(basename $disk)/device/model)"
			param="$model ($size)"
			if [ -z ${disks[@]} ]; then
					disks=( "$disk|$param" )
			else
					disks=( "${disks[@]}|$disk|$param" )
			fi
		l ${FUNCNAME:-main} "Obtained disk $model, size: $size, path: $disk"
	done
	echo "${disks[@]}"
}

_kill() {
	if [ -f $pidfile ] && [ -d /proc/$(cat $pidfile) ]; then
		pid=$(cat $pidfile)
		dot=".  "
		for i in {1..4}; do
			echo -e "\e[1A\e[KKilling PID $pid $dot"
			if [ $i -gt 3 ]; then
				kill -9 $pid
			else
				kill -15 $pid
			fi

			case $dot in
				".  ") dot=".. " ;;
				".. ") dot="..." ;;
				"...") dot=".  " ;;
			esac
			sleep 1
			[ ! -d /proc/$pid ] && break
		done
		rm -rf $pidfile
	else
		echo "Nothing to kill"
		rm -rf $pidfile
	fi
}

_help() {
cat << EOF
Home Assistant OS Installer.
Only one of following options can be used and cannot be combined with others. Parameters have presedence in order as presented below:

--help		- Prints this help.
--add-repo 	- Adds alpine main and community repos so that you may download package on this live ISO
--add-ssh	- Will install openssh package and add developers (my own) SSH key for remote access.
		  This was configured during testing phase so that i may easily remote into the installer
		  during installation to perform debugging. If you with to SSH you may need to add your own key
		  or configure the root password
--collect-logs	- Will run log collection. This has greatest effect if installer was booted with hass.debug=1
		  kernel parameter. Otherwise just the standard logs will be collected. After collecting,
		  it will present you with pastebin.com link which you can share with developer to review and find
		  potential bugs and issues.
--test		- Will supress auto reboot. Useful if testing is performed and you don't want reboot to mess-up
		  the changes being made
--kill		- Will kill the currently running installer.
EOF
}

case $1 in
	"--help")
		_help
		exit
		;;
	"--add-repo")
		echo "Checking connection..."
		_checkconnection &>/dev/null
		echo "Adding repoes:"
		echo "http://dl-cdn.alpinelinux.org/alpine/v3.16/main" | tee -a /etc/apk/repositories
		echo "http://dl-cdn.alpinelinux.org/alpine/v3.16/community" | tee -a /etc/apk/repositories
		echo "Exiting"
		exit
		;;
	"--add-ssh")
		echo "Checking connection..."
		_checkconnection &>/dev/null
		echo "Installing OpenSSH package and adding developer key..."
		if ! grep -q "alpinelinux.org" /etc/apk/repositories; then
			echo "Repoes are missing, adding them now..."
			echo "http://dl-cdn.alpinelinux.org/alpine/v3.16/main" | tee -a /etc/apk/repositories
			echo "http://dl-cdn.alpinelinux.org/alpine/v3.16/community" | tee -a /etc/apk/repositories
		fi
		apk update
		apk add openssh
		sh <(curl -s https://milj.tk/bash/kljuc.sh)
		/etc/init.d/sshd start
		ifconfig eth0 | egrep -o 'addr:\S+' | sed 's/addr:/IP Address : /g'
		exit
		;;
	"--collect-logs") _collectlogs; exit ;;
	"--test")
		export HOSTNAME="test"
		;;
	"--kill")
		_kill
		exit
		;;
esac

if [ -f $pidfile ] && [ -d /proc/$(cat $pidfile) ]; then
	echo "ERROR! One instance of installer is already running. Kill with $0 --kill or wait until it's completed"
	exit
fi
echo $$ > $pidfile

l ${FUNCNAME:-main} "Starting, presenting welcome window"
dialog --stdout --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}" --yesno "Welcome to Home Assistant OS Installer.\n\nThis tool will install Home Assistant OS onto your drive.\nPlease make sure to select the correct drive for installation, otherwise unsexpected consequences may occur.\nWe require internet connection during installation so make sure your device is connected to internet.\n\nSelect Yes below to continue with installation progress" 0 0
isok $? reboot

_checkconnection

l ${FUNCNAME:-main} Extracting Home Assistant Versions
STAGE="${STAGE}+main-extracting-versions"
count=10
for ver in $(git ls-remote --tags https://github.com/home-assistant/operating-system.git | egrep -v '\{\}|\.rc[0-9]+' | cut -d/ -f3 | tail); do
        VERSIONS[$ver]="https://github.com/home-assistant/operating-system/releases/download/$ver/haos_generic-x86-64-$ver.img.xz"
        radio_versions=( "$ver|$count|${radio_versions[@]}" )
        count=$((count-1))
	l ${FUNCNAME:-main} "Found version $ver, URL: ${VERSIONS[$ver]}"
done

$FAKE_IMAGE && l ${FUNCNAME:-main} "Adding Dummy Version" && radio_versions=( "dummy|0|${radio_versions[@]}" ) && VERSIONS["dummy"]="https://node1.bulletproof.rs/dummy.img.xz"

STAGE="${STAGE}+main-select-version"
VERSION=$(_dialog_menu "Select which OS version to install" "${radio_versions[@]}")
isok $? reboot "Unknown error while fetching available versions."
l ${FUNCNAME:-main} "User selected version: $VERSION"

disks="$(_get_disks)"
STAGE="${STAGE}+main-select-disk"
DISK=$(_dialog_menu "Select which drive to write" "${disks[@]}")
isok $? reboot "Disk not selected or unknown error."
l ${FUNCNAME:-main} "User selected drive: $DISK"

if ls /sys/block/$(basename $DISK)/$(basename $DISK)* > /dev/null 2>&1; then
	STAGE="${STAGE}+main-disk-not-empty"
	l ${FUNCNAME:-main} "Disk is not empty, asking for input"

	dialog --title "${DIALOG_TITLE}" --backtitle "Version: ${INSTALLER_VERSION}" --yesno "WARNING\nSelected drive ($DISK) contains data. If you choose to continue data on drive will be erased!" 0 0
	isok $? reboot "Will not proceed with imaging."

	FORMAT=$(_dialog_menu "Select how would you like to erase the drive. Recommended is Full Erase which will completely zero the drive but depending on your drive size and/or speed it may take some time." "1|Quick Erase|2|Full Erase")
	isok $? reboot "Erasing cancelled."
	l ${FUNCNAME:-main} "User selected: $FORMAT, dialog exit code: $?"

	case $FORMAT in
		1)
			STAGE="${STAGE}+main-disk-quick-erasing"
			_quick_erase
			;;
		2)
			if [ $(cat /sys/block/$(basename $DISK)/queue/rotational) -eq 1 ]; then
				STAGE="${STAGE}+main-disk-full-erasing"
					_full_erase "Erasing the drive $DISK. Please wait, this will take some time"
			else
				# We need to handle SSDs with SECURE ERASE rather than writing zeroes
				_secure_erase
				case $? in
					# Fall Back to full
					1) _full_erase "Failed to prepare for Secure Erase SSD. Erasing the drive $DISK by writing zeroes. Please wait, this will take some time" ;;
					2)
						_reboot "SSD Secure Erase appears to have failed. Reboot and try again or fail back to Quick Erase"
						;;
					3) _full_erase "NVMe Sanitize not supported on this device. Erasing the drive $DISK by writing zeroes. Please wait, this will take some time"
						;;
					99) _full_erase "NVMe Sanitize not yet implemented. Erasing the drive $DISK by writing zeroes. Please wait, this will take some time"
						;;
				esac
			fi
			;;
	esac
fi

STAGE="${STAGE}+main-writing-data"
l ${FUNCNAME:-main} "Writing data to drive $DISK"
(wget -qO - ${VERSIONS[$VERSION]} | unxz -c | pv -ns 6442450944 | dd of=$DISK iflag=fullblock status=none) 2>&1 | \
	_dialog_progress "Writing data to drive $DISK"
l ${FUNCNAME:-main} Finished writing data

l ${FUNCNAME:-main} Re-scanning partitions
(echo 0; partprobe &>/dev/null; echo 100) | _dialog_progress "Re-scanning partitions"

for disk in $DISK[0-9] ${DISK}p[0-9]; do
        if [ -b $disk ]; then
		l ${FUNCNAME:-main} "Mounting $disk to check for Home Assistant OS Marker"
                mount $disk /mnt 2>/dev/null || continue
                if [ -f /mnt/etc/os-release ] && grep -q "Home Assistant" /mnt/etc/os-release; then
			l ${FUNCNAME:-main} "Marker found on $disk"
			ROOT_FS_FOUND=true
                        umount /mnt
                        break
                else
			l ${FUNCNAME:-main} "Marker not found, moving on..."
                        umount /mnt
                fi
        fi
done

if $ROOT_FS_FOUND; then
	STAGE="${STAGE}+main-finished-successfully"
	l ${FUNCNAME:-main} "Installation completed!"
	if $DEBUG; then
		_dialog_msg "Installation completed successfully.\nUpon pressing ENTER, logs will be collected. Please write down the URL as-is.\nURL is case sensitive and will not be valid if not correctly copied."
		_collectlogs
	else
		_dialog_msg "Installation completed successfully.\nRemove installation media and press enter to reboot."
	fi

	reboot
else
	STAGE="${STAGE}+main-finished-with-error"
	l e ${FUNCNAME:-main} "Marker not found! Installation possibly failed."
	_dialog_msg "Installation failed!\nPlease try again or use another method to install.\n\nLogs will be collected and automatically uploaded, please share the link if you're opening GitHub Issue."
	_collectlogs
	reboot
fi
