#!/bin/sh

# Load the Qualcomm Bluetooth serdev stack before the initramfs switches to
# the persistent root. The module paths are derived from the running release.

set -u

krel=$(cat /proc/sys/kernel/osrelease 2>/dev/null || true)
module_root="/usr/lib/modules/$krel"

load_module() {
	module_path=$1
	[ -r "$module_root/$module_path" ] || return 0
	/sbin/insmod "$module_root/$module_path" 2>/dev/null || true
}

load_module kernel/crypto/ecc.ko
load_module kernel/crypto/kpp.ko
load_module kernel/crypto/ecdh_generic.ko
load_module kernel/net/bluetooth/bluetooth.ko
load_module kernel/drivers/bluetooth/btbcm.ko
load_module kernel/drivers/bluetooth/btqca.ko
load_module kernel/drivers/bluetooth/hci_uart.ko
