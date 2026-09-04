#!/bin/sh

# Load Surface storage, USB/Type-C PHY, I2C-HID, and fingerprint dependencies
# before root discovery.  The initramfs carries the exact module tree for the
# kernel in this UKI, so no modules from the installed OS are mixed in.

set -u

krel=$(cat /proc/sys/kernel/osrelease 2>/dev/null || true)
modprobe_bin=/usr/sbin/modprobe
[ -x "$modprobe_bin" ] || modprobe_bin=/sbin/modprobe

load_module() {
	module_name=$1
	if ! "$modprobe_bin" -d /usr -S "$krel" "$module_name" >/dev/null 2>&1; then
		printf 'surface-initramfs: failed to load %s for %s\n' \
			"$module_name" "$krel" >/dev/kmsg 2>/dev/null || true
	fi
}

# Load the USB-root path before optional input and desktop support. The QMP
# combo and primary eUSB2 drivers are built in, but keeping the modprobe calls
# makes this hook compatible with older integration kernels as well.
load_module aux_bridge
load_module phy_qcom_qmp_combo
load_module phy_qcom_qmp_usbc
load_module phy_qcom_m31
load_module phy_qcom_m31_eusb2
load_module phy_qcom_eusb2_repeater
load_module phy_qcom_qusb2
load_module phy_qcom_usb_hs
load_module phy_qcom_usb_ss

# The external NVMe enclosure is presented through USB mass storage/UAS.
load_module scsi_mod
load_module sd_mod
load_module usb_storage
load_module uas
load_module nvme_core
load_module nvme

# The internal storage is a Qualcomm UFS device. The QMP UFS PHY and host
# glue may be modules in a distribution kernel, so load them before root
# discovery as well as carrying them in the matching initramfs.
load_module phy_qcom_qmp_ufs
load_module ufshcd_core
load_module ufshcd_pltfrm
load_module ufs_qcom

if command -v udevadm >/dev/null 2>&1; then
	udevadm trigger --type=devices --action=add >/dev/null 2>&1 || true
	udevadm settle --timeout=10 >/dev/null 2>&1 || true
fi

# GENI I2C and HID are needed by the internal touchscreen.
load_module gpi
load_module i2c_qcom_geni
load_module i2c_hid
load_module i2c_hid_of
load_module hid_multitouch

# Keep the desktop features usable even when the target OS has no matching
# /usr/lib/modules/<release> tree after switch_root.
load_module cifs
load_module wireguard
