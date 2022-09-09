profile_hassio_installer() {
	title="Hassio Installer"
	desc="Just Enough OS to install Home Assistant OS."
	profile_base
	hostname="hassio-installer"
	profile_abbrev="hassinstaller"
	image_ext="iso"
	arch="x86_64"
	output_format="iso"
	kernel_addons="xtables-addons"
	apks="$apks dialog git bash iwd pv parted hdparm nvme-cli curl ntfs-3g ntfs-3g-progs"
	apkovl="genapkovl-hassio-installer.sh"
}
