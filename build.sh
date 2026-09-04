#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PUBLIC_DIR="$ROOT_DIR"
# Kernel/Kconfig builds need symlinks, which are not available on some SMB
# mounts. Keep scratch data local while committing only final components.
WORK_DIR=${SURFACE_WORK_DIR:-/tmp/surface-laptop-13-build}
CURRENT_DIR="$ROOT_DIR/SURFACE-CURRENT"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

# All build inputs are supplied by the environment or by an OS integration.
# Nothing in this script references a private development workspace.
KERNEL_SOURCE=${KERNEL_SOURCE:-}
INITRD_BASE=${INITRD_BASE:-}
FIRMWARE_SOURCE=${FIRMWARE_SOURCE:-}
KERNEL_CONFIG=${KERNEL_CONFIG:-$PUBLIC_DIR/kernel/config/base.config}
KERNEL_CONFIG_FRAGMENT=${KERNEL_CONFIG_FRAGMENT:-$PUBLIC_DIR/kernel/config/desktop.config}
BASE_DTS=${BASE_DTS:-$PUBLIC_DIR/device-tree/base/surface-laptop-13-typec.dts}
# Optional separately measured DTB.  A clean checkout must be buildable from
# the public DTS, so this is intentionally not a required default input.
BASE_DTB_INPUT=${BASE_DTB_INPUT:-}
UKI_STUB=${UKI_STUB:-/usr/lib/systemd/boot/efi/linuxaa64.efi.stub}
KERNEL_JOBS=${KERNEL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
# Keep the out-of-tree kernel objects by default. Set this to 0 only when a
# deliberately clean kernel build is required.
KERNEL_REUSE_OUTPUT=${KERNEL_REUSE_OUTPUT:-1}
# Public kernel patches are applied by default; set this to 0 only when the
# supplied source tree already contains every public patch.
KERNEL_APPLY_PATCHES=${KERNEL_APPLY_PATCHES:-1}
# Optional OS-specific command line for a local boot test.  Public builds
# keep the neutral placeholder below when this is unset.
CMDLINE_INPUT=${SURFACE_CMDLINE_FILE:-}

KERNEL_OUT="$WORK_DIR/kernel"
KERNEL_WORK_SOURCE="$WORK_DIR/kernel-source"
MODULE_OUT="$WORK_DIR/modules"
DTB_OUT="$WORK_DIR/dtb"
INITRD_OUT="$WORK_DIR/initramfs"
UKI_OUT="$WORK_DIR/uki"
ANDROID_MODE_OUT="$WORK_DIR/android-mode"
OS_RELEASE="$WORK_DIR/os-release"
CMDLINE="$WORK_DIR/cmdline"
ANDROID_CMDLINE="$WORK_DIR/android-cmdline"
SLEEP_CMDLINE="$WORK_DIR/sleep-cmdline"

kernel_image="$KERNEL_OUT/Image"
kernel_config="$KERNEL_OUT/config"
kernel_release="$KERNEL_OUT/release"
base_dtb="$DTB_OUT/surface-laptop-13-current.dtb"
bluetooth_dtb="$DTB_OUT/surface-laptop-13-bluetooth.dtb"
fingerprint_dtb="$DTB_OUT/surface-laptop-13-fingerprint.dtb"
bluetooth_fingerprint_dtb="$DTB_OUT/surface-laptop-13-bluetooth-fingerprint.dtb"
current_initrd="$INITRD_OUT/surface-laptop-13-current.img"
bluetooth_initrd="$INITRD_OUT/surface-laptop-13-bluetooth.img"
current_uki="$UKI_OUT/surface-laptop-13-current.efi"
bluetooth_uki="$UKI_OUT/surface-laptop-13-bluetooth.efi"
fingerprint_uki="$UKI_OUT/surface-laptop-13-fingerprint.efi"
android_uki="$UKI_OUT/surface-laptop-13-android.efi"
sleep_uki="$UKI_OUT/surface-laptop-13-s2idle.efi"

mkdirs() { mkdir -p "$KERNEL_OUT" "$MODULE_OUT" "$DTB_OUT" "$INITRD_OUT" "$UKI_OUT"; }

write_neutral_metadata() {
	mkdirs
	cat >"$OS_RELEASE" <<'EOF'
NAME="Surface Laptop 13 Linux Hardware Support"
ID=surface-laptop-13
ID_LIKE=linux
VERSION_ID=1
PRETTY_NAME="Surface Laptop 13 Linux Hardware Support"
VARIANT="Hardware Support"
VARIANT_ID=surface-laptop-13
HOME_URL="https://github.com/amania-Jailbreak/Surface-Laptop-for-Business-13in-1st-Ed-with-Snapdragon-Linux"
EOF
	if [[ -n "$CMDLINE_INPUT" ]]; then
		[[ -f "$CMDLINE_INPUT" ]] || die "command line input not found: $CMDLINE_INPUT"
		[[ -s "$CMDLINE_INPUT" ]] || die "command line input is empty: $CMDLINE_INPUT"
		cp "$CMDLINE_INPUT" "$CMDLINE"
	else
		# The UUID is intentionally supplied by the consumer.  A label or UUID
		# may be appended by an OS-specific wrapper without rebuilding the UKI.
		cat >"$CMDLINE" <<'EOF'
root=UUID=CHANGE-ME rootfstype=ext4 rootwait rw quiet splash cma=128M
EOF
	fi
}

check_inputs() {
	local f
	need bash; need find; need dtc; need fdtoverlay; need fdtget
	for f in "$KERNEL_CONFIG" "$KERNEL_CONFIG_FRAGMENT" "$BASE_DTS"; do
		[[ -f "$f" ]] || die "input not found: $f"
	done
	if [[ -n "$BASE_DTB_INPUT" ]]; then
		[[ -f "$BASE_DTB_INPUT" ]] || die "measured base DTB not found: $BASE_DTB_INPUT"
	fi
	[[ -f "$PUBLIC_DIR/device-tree/overlays/touchscreen.dtso" ]] || die "public touchscreen overlay missing"
	[[ -f "$PUBLIC_DIR/device-tree/overlays/bluetooth.dtso" ]] || die "public Bluetooth overlay missing"
	[[ -f "$PUBLIC_DIR/device-tree/overlays/fingerprint-usb.dtso" ]] || die "public fingerprint USB overlay missing"
	if command -v docker >/dev/null 2>&1; then
		printf 'container runtime: docker\n'
	elif command -v podman >/dev/null 2>&1; then
		printf 'container runtime: podman\n'
	else
		printf 'container runtime: unavailable (native build remains supported)\n'
	fi
	printf 'config: %s\nDT source: %s\n' "$KERNEL_CONFIG" "$BASE_DTS"
	[[ -z "$KERNEL_SOURCE" ]] || printf 'kernel source: %s\n' "$KERNEL_SOURCE"
}

check_full_inputs() {
	check_inputs
	need make; need python3; need sha256sum; need strings; need grep
	need gzip; need cpio; need depmod
	local f
	for f in "$KERNEL_SOURCE/Makefile" "$INITRD_BASE" "$UKI_STUB"; do
		[[ -f "$f" ]] || die "input not found: $f"
	done
	[[ -d "$FIRMWARE_SOURCE" ]] || die "firmware directory not found: $FIRMWARE_SOURCE"
}

check_android_inputs() {
	local f
	for f in \
		"$PUBLIC_DIR/android-mode/install-android-mode.sh" \
		"$PUBLIC_DIR/android-mode/bin/surface-android-session" \
		"$PUBLIC_DIR/android-mode/bin/surface-android-control" \
		"$PUBLIC_DIR/android-mode/systemd/surface-android-mode.service" \
		"$PUBLIC_DIR/android-mode/systemd/surface-android-control.service" \
		"$PUBLIC_DIR/android-mode/systemd/surface-android-control.socket" \
		"$PUBLIC_DIR/android-mode/systemd/waydroid-control.conf" \
		"$PUBLIC_DIR/android-mode/systemd/greetd.service.d.conf" \
		"$PUBLIC_DIR/android-mode/systemd/getty-tty1.service.d.conf" \
		"$PUBLIC_DIR/android-mode/tmpfiles.d/surface-android-control.conf" \
		"$PUBLIC_DIR/android-mode/waydroid/surface-control.conf" \
		"$PUBLIC_DIR/android-mode/app/build-android-apk.sh" \
		"$PUBLIC_DIR/android-mode/app/AndroidManifest.xml" \
		"$PUBLIC_DIR/android-mode/app/res/values/strings.xml" \
		"$PUBLIC_DIR/android-mode/app/res/values/styles.xml" \
		"$PUBLIC_DIR/android-mode/app/res/drawable/ic_surface_controls.xml" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/MainActivity.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/HostControlClient.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/AndroidSettings.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/SyncService.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/HostControlsTileService.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/HostWifiTileService.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/HostBluetoothTileService.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/HostAudioTileService.java" \
		"$PUBLIC_DIR/android-mode/app/src/org/surface/hardwarecontrol/HostBrightnessTileService.java"; do
		[[ -f "$f" ]] || die "Android Mode input not found: $f"
	done
}

patch_features_present() {
	local name="$(basename "$1")"
	case "$name" in
		0001-*) grep -q 'qcom,force-host-role' "$KERNEL_WORK_SOURCE/drivers/usb/dwc3/drd.c" ;;
		0002-*)
			grep -q 'qcom,force-ucsi-registration' "$KERNEL_WORK_SOURCE/drivers/soc/qcom/pmic_glink.c" &&
			grep -q 'UCSI registration state' "$KERNEL_WORK_SOURCE/drivers/usb/typec/ucsi/ucsi_glink.c" &&
			grep -q 'charger PD notification' "$KERNEL_WORK_SOURCE/drivers/usb/typec/ucsi/ucsi_glink.c"
		;;
		0003-*) grep -q '0x07ad' "$KERNEL_WORK_SOURCE/drivers/gpu/drm/panel/panel-edp.c" ;;
		0004-*) grep -q 'qcom,keep-host-on-suspend' "$KERNEL_WORK_SOURCE/drivers/usb/dwc3/dwc3-qcom.c" ;;
		0005-*) grep -q 'xhci_plat_keep_host_active' "$KERNEL_WORK_SOURCE/drivers/usb/host/xhci-plat.c" ;;
		0006-*)
			grep -q 'qcom,keep-edp-active-on-blank' "$KERNEL_WORK_SOURCE/drivers/gpu/drm/msm/dp/dp_display.c" &&
			grep -q 'keep-panel-prepared-on-disable' "$KERNEL_WORK_SOURCE/drivers/gpu/drm/bridge/panel.c"
		;;
		*) return 1 ;;
	esac
}

apply_public_patches() {
	[[ "${KERNEL_APPLY_PATCHES:-1}" == 1 ]] || return 0
	need patch
	local patch_file
	for patch_file in "$PUBLIC_DIR"/kernel/patches/*.patch; do
		[[ -f "$patch_file" ]] || continue
		if patch_features_present "$patch_file"; then
			printf 'patch already present (source feature): %s\n' "$(basename "$patch_file")"
		elif patch --dry-run --batch --forward --silent -d "$KERNEL_WORK_SOURCE" -p1 <"$patch_file" >/dev/null 2>&1; then
			patch --batch --forward --silent -d "$KERNEL_WORK_SOURCE" -p1 <"$patch_file"
		else
			die "kernel patch does not apply cleanly: $patch_file"
		fi
	done
}

merge_kernel_config() {
	local merge_config="$KERNEL_WORK_SOURCE/scripts/kconfig/merge_config.sh"
	if [[ -x "$merge_config" ]]; then
		"$merge_config" -m -O "$KERNEL_OUT" "$KERNEL_OUT/.config" "$KERNEL_CONFIG_FRAGMENT"
	else
		# A few vendor source exports omit merge_config.sh.  The fragment is
		# deliberately additive, so appending it before olddefconfig is safe.
		cat "$KERNEL_CONFIG_FRAGMENT" >>"$KERNEL_OUT/.config"
	fi
}

check_kernel_features() {
	local config_file="$1"
	local symbol
	for symbol in \
		USB USB_DWC3 USB_DWC3_QCOM USB_XHCI_HCD USB_XHCI_PLATFORM \
		PHY_QCOM_QMP PHY_QCOM_QMP_USB DRM_AUX_BRIDGE PHY_QCOM_QMP_COMBO \
		PHY_QCOM_USB_SNPS_FEMTO_V2 USB_STORAGE USB_UAS SCSI BLK_DEV_SD EXT4_FS \
		IP_ADVANCED_ROUTER; do
		grep -Eq "^CONFIG_${symbol}=y$" "$config_file" \
			|| die "USB-root feature must be built in: CONFIG_${symbol}"
	done
	for symbol in \
		CIFS WIREGUARD \
		SCSI_UFSHCD SCSI_UFSHCD_PLATFORM SCSI_UFS_QCOM PHY_QCOM_QMP_UFS \
		ANDROID_BINDER_IPC ANDROID_BINDERFS PSI MEMFD_CREATE \
		BRIDGE BRIDGE_NETFILTER VETH \
		NF_CONNTRACK NF_NAT IP_NF_IPTABLES IP_NF_FILTER IP_NF_NAT IP_NF_MANGLE \
		NETFILTER_XT_TARGET_CHECKSUM NETFILTER_XT_TARGET_MASQUERADE; do
		grep -Eq "^CONFIG_${symbol}=(y|m)$" "$config_file" \
			|| die "required kernel feature is disabled: CONFIG_${symbol}"
	done
	for symbol in CIFS_DEBUG CIFS_DEBUG2 CIFS_DEBUG_DUMP_KEYS WIREGUARD_DEBUG DRM_PANIC_DEBUG DRM_DEBUG_DP_MST_TOPOLOGY_REFS; do
		if grep -Eq "^CONFIG_${symbol}=(y|m)$" "$config_file"; then
			die "verbose diagnostic feature is enabled: CONFIG_${symbol}"
		fi
	done
}

build_kernel() {
	need make; need aarch64-linux-gnu-gcc
	[[ -f "$KERNEL_SOURCE/Makefile" ]] || die "kernel source directory not found: $KERNEL_SOURCE"
	mkdirs
	if [[ "${KERNEL_IN_PLACE:-0}" == 1 && ! -f "$KERNEL_SOURCE/.config" && ! -d "$KERNEL_SOURCE/include/config" && ! -d "$KERNEL_SOURCE/arch/arm64/include/generated" ]]; then
		# A clean checkout can be used directly with O=; the kernel build writes
		# generated files into the separate output directory.
		KERNEL_WORK_SOURCE="$KERNEL_SOURCE"
	fi
	if [[ "$KERNEL_WORK_SOURCE" != "$KERNEL_SOURCE" && ! -f "$KERNEL_WORK_SOURCE/.surface-source-prepared" ]]; then
		log "Creating isolated kernel source view"
		if [[ -e "$KERNEL_WORK_SOURCE" ]]; then
			find "$KERNEL_WORK_SOURCE" -depth -mindepth 1 -delete
			rmdir "$KERNEL_WORK_SOURCE"
		fi
		# Hard-linked files keep this fast on large local checkouts. mrproper and
		# patch replace/unlink files in the view, leaving the user's source tree
		# untouched.
		cp -al "$KERNEL_SOURCE" "$KERNEL_WORK_SOURCE"
		make -C "$KERNEL_WORK_SOURCE" mrproper >/dev/null
		touch "$KERNEL_WORK_SOURCE/.surface-source-prepared"
	fi
	log "Preparing neutral kernel configuration"
	if [[ "${KERNEL_REUSE_OUTPUT:-0}" == 1 && -f "$KERNEL_OUT/.config" ]]; then
		log "Reusing existing kernel build output"
		mkdir -p "$MODULE_OUT"
	else
		rm -rf "$KERNEL_OUT" "$MODULE_OUT"
		mkdir -p "$KERNEL_OUT" "$MODULE_OUT"
	fi
	if [[ "${KERNEL_REUSE_OUTPUT:-0}" != 1 || ! -f "$KERNEL_OUT/.config" ]]; then
		cp "$KERNEL_CONFIG" "$KERNEL_OUT/.config"
	fi
	merge_kernel_config
	make -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
	if grep -q '^CONFIG_LOCALVERSION=' "$KERNEL_OUT/.config"; then
		sed -i -E 's#^CONFIG_LOCALVERSION=.*#CONFIG_LOCALVERSION="-surface-laptop-13"#' "$KERNEL_OUT/.config"
	else
		printf '%s\n' 'CONFIG_LOCALVERSION="-surface-laptop-13"' >>"$KERNEL_OUT/.config"
	fi
	if grep -q '^CONFIG_LOCALVERSION_AUTO=' "$KERNEL_OUT/.config"; then
		sed -i -E 's#^CONFIG_LOCALVERSION_AUTO=.*#CONFIG_LOCALVERSION_AUTO=n#' "$KERNEL_OUT/.config"
	else
		printf '%s\n' 'CONFIG_LOCALVERSION_AUTO=n' >>"$KERNEL_OUT/.config"
	fi
	make -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
	apply_public_patches
	# Re-run configuration after optional source patches; no private distro
	# settings are added here.
	make -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
	log "Building ARM64 kernel and modules"
	make -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" -j"$KERNEL_JOBS" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules
	local krel module_release_dir module_install_stamp
	krel=$(make -s -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)
	case "$krel" in
		""|*/*|*..*) die "unsafe kernel release: $krel" ;;
	esac
	module_release_dir="$MODULE_OUT/lib/modules/$krel"
	module_install_stamp="$MODULE_OUT/.modules-installed-$krel"
	local install_modules=1
	if [[ "${KERNEL_FORCE_MODULE_INSTALL:-0}" != 1 && -f "$module_install_stamp" ]]; then
		if [[ -z "$(find "$KERNEL_OUT" -type f \( -name '*.ko' -o -name 'modules.order' -o -name 'modules.builtin' -o -name 'modules.builtin.modinfo' \) -newer "$module_install_stamp" -print -quit)" ]]; then
			install_modules=0
		fi
	fi
	if (( install_modules )); then
		if [[ -e "$module_release_dir" ]]; then
			[[ -d "$module_release_dir" && ! -L "$module_release_dir" ]] \
				|| die "unsafe module output directory: $module_release_dir"
			find "$module_release_dir" -depth -mindepth 1 -delete
			rmdir "$module_release_dir"
		fi
		make -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$MODULE_OUT" modules_install
		touch "$module_install_stamp"
	else
		log "Reusing installed kernel modules"
	fi
	cp "$KERNEL_OUT/arch/arm64/boot/Image" "$kernel_image"
	cp "$KERNEL_OUT/.config" "$kernel_config"
	check_kernel_features "$kernel_config"
	printf '%s\n' "$krel" >"$kernel_release"
	[[ "$krel" == *surface-laptop-13* ]] || die "kernel release is not neutral: $krel"
	printf 'kernel release: %s\n' "$krel"
}

build_dtb() {
	need dtc; need fdtoverlay; need fdtget
	mkdirs
	log "Building Type-C, touchscreen, Bluetooth, fingerprint, and UFS device trees"
	local raw_base_dtb="$DTB_OUT/surface-laptop-13-typec-base.dtb"
	# The public DTS is the normal source of truth. A separately supplied
	# measured DTB can be selected explicitly for comparison, but a clean clone
	# never depends on an ignored binary.
	if [[ "${REBUILD_BASE_DTB:-1}" == 1 || -z "$BASE_DTB_INPUT" ]]; then
		dtc -@ -I dts -O dtb -o "$raw_base_dtb" "$BASE_DTS" >"$DTB_OUT/base-dtc.log" 2>&1
	else
		[[ -f "$BASE_DTB_INPUT" ]] || die "measured base DTB not found: $BASE_DTB_INPUT"
		cp "$BASE_DTB_INPUT" "$raw_base_dtb"
		printf 'copied measured base DTB from %s\n' "$BASE_DTB_INPUT" >"$DTB_OUT/base-dtc.log"
	fi
	local touchscreen_overlay="$DTB_OUT/touchscreen.dtbo"
	local bluetooth_overlay="$DTB_OUT/bluetooth.dtbo"
	local fingerprint_overlay="$DTB_OUT/fingerprint-usb.dtbo"
	dtc -@ -I dts -O dtb -o "$touchscreen_overlay" "$PUBLIC_DIR/device-tree/overlays/touchscreen.dtso" >"$DTB_OUT/touchscreen-dtc.log" 2>&1
	dtc -@ -I dts -O dtb -o "$bluetooth_overlay" "$PUBLIC_DIR/device-tree/overlays/bluetooth.dtso" >"$DTB_OUT/bluetooth-dtc.log" 2>&1
	dtc -@ -I dts -O dtb -o "$fingerprint_overlay" "$PUBLIC_DIR/device-tree/overlays/fingerprint-usb.dtso" >"$DTB_OUT/fingerprint-dtc.log" 2>&1
	fdtoverlay -i "$raw_base_dtb" -o "$base_dtb" "$touchscreen_overlay"
	fdtoverlay -i "$base_dtb" -o "$bluetooth_dtb" "$bluetooth_overlay"
	fdtoverlay -i "$base_dtb" -o "$fingerprint_dtb" "$fingerprint_overlay"
	fdtoverlay -i "$bluetooth_dtb" -o "$bluetooth_fingerprint_dtb" "$fingerprint_overlay"
	for candidate in "$base_dtb" "$bluetooth_dtb" "$fingerprint_dtb" "$bluetooth_fingerprint_dtb"; do
		fdtget "$candidate" /soc@0/display-subsystem@ae00000/displayport-controller@aea0000 qcom,keep-edp-active-on-blank >/dev/null 2>&1 || die "eDP blanking guard is missing in $candidate"
		fdtget "$candidate" /soc@0/display-subsystem@ae00000/displayport-controller@aea0000/aux-bus/panel keep-panel-prepared-on-disable >/dev/null 2>&1 || die "eDP panel preparation guard is missing in $candidate"
	done
	for candidate in "$base_dtb" "$bluetooth_dtb"; do
		[[ -s "$candidate" ]] || die "empty DTB: $candidate"
		[[ "$(fdtget "$candidate" /soc@0/usb@a600000 dr_mode)" == host ]] || die "USB-C port 0 is not host in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/usb@a800000 dr_mode)" == host ]] || die "USB-C port 1 is not host in $candidate"
		fdtget "$candidate" /soc@0/usb@a600000 qcom,keep-host-on-suspend >/dev/null 2>&1 || die "USB-C port 0 sleep guard is missing in $candidate"
		fdtget "$candidate" /soc@0/usb@a800000 qcom,keep-host-on-suspend >/dev/null 2>&1 || die "USB-C port 1 sleep guard is missing in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/geniqup@ac0000/i2c@a80000 status)" == okay ]] || die "touchscreen I2C controller is disabled in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 compatible)" == hid-over-i2c ]] || die "touchscreen node is missing in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 hid-descr-addr)" == 0 ]] || die "touchscreen HID descriptor address is not zero in $candidate"
	done
	for candidate in "$base_dtb" "$bluetooth_dtb" "$fingerprint_dtb" "$bluetooth_fingerprint_dtb"; do
		[[ "$(fdtget "$candidate" /soc@0/phy@1d80000 status)" == okay ]] || die "UFS PHY is disabled in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/ufshc@1d84000 status)" == okay ]] || die "UFS controller is disabled in $candidate"
	done
	[[ "$(fdtget "$bluetooth_dtb" /soc@0/geniqup@ac0000/serial@a98000 status)" == okay ]] || die "Bluetooth UART is disabled"
	[[ "$(fdtget "$bluetooth_dtb" /soc@0/geniqup@ac0000/serial@a98000/bluetooth compatible)" == qcom,wcn7850-bt ]] || die "Bluetooth compatible is unexpected"
	[[ "$(fdtget "$bluetooth_dtb" /soc@0/geniqup@ac0000/serial@a98000/bluetooth max-speed)" == 3200000 ]] || die "Bluetooth UART speed is unexpected"
	for candidate in "$fingerprint_dtb" "$bluetooth_fingerprint_dtb"; do
		[[ "$(fdtget "$candidate" /soc@0/usb@a200000 status)" == okay ]] || die "fingerprint USB controller is disabled in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/usb@a200000 dr_mode)" == host ]] || die "fingerprint USB controller is not host mode in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/phy@88e0000 status)" == okay ]] || die "fingerprint eUSB2 PHY is disabled in $candidate"
	done
}

build_initramfs() {
	need python3; need gzip; need cpio; need depmod
	[[ -f "$INITRD_BASE" ]] || die "initramfs input not found: $INITRD_BASE"
	[[ -d "$FIRMWARE_SOURCE" ]] || die "firmware directory not found: $FIRMWARE_SOURCE"
	mkdirs
	log "Preparing OS-neutral initramfs inputs"
	# The base initramfs is a boot component only.  It is deliberately not
	# rebuilt from a desktop root filesystem here.
	local krel="$1"
	local manifest="$WORK_DIR/surface-files.manifest"
	: >"$manifest"
	local base_copy="$WORK_DIR/initramfs-base.img"
	cp "$INITRD_BASE" "$base_copy"

	# Preserve the old boot initramfs module set by path, but resolve every
	# dependency against the newly built kernel.  This retains storage, USB,
	# input, power, and Qualcomm support without carrying a foreign release's
	# .ko files into the new UKI.
	local seed_modules="$WORK_DIR/initramfs-module-seeds.txt"
	: >"$seed_modules"
	local module
	for module in \
		kernel/crypto/af_alg.ko \
		kernel/crypto/ecc.ko \
		kernel/crypto/kpp.ko \
		kernel/crypto/ecdh_generic.ko \
		kernel/drivers/crypto/qce/qcrypto.ko \
		kernel/drivers/crypto/qcom-rng.ko \
		kernel/drivers/dma/qcom/gpi.ko \
		kernel/drivers/gpu/drm/bridge/aux-bridge.ko \
		kernel/drivers/hid/i2c-hid/i2c-hid.ko \
		kernel/drivers/hid/i2c-hid/i2c-hid-of.ko \
		kernel/drivers/hid/hid-multitouch.ko \
		kernel/drivers/i2c/busses/i2c-qcom-geni.ko \
		kernel/drivers/mailbox/qcom-cpucp-mbox.ko \
		kernel/drivers/misc/fastrpc.ko \
		kernel/drivers/net/wireguard/wireguard.ko \
		kernel/drivers/nvme/host/nvme-core.ko \
		kernel/drivers/nvme/host/nvme.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-qmp-ufs.ko \
		kernel/drivers/nvmem/nvmem_qcom-spmi-sdam.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-eusb2-repeater.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-m31.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-m31-eusb2.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-qmp-combo.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-qmp-usbc.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-qusb2.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-usb-hs.ko \
		kernel/drivers/phy/qualcomm/phy-qcom-usb-ss.ko \
		kernel/drivers/power/reset/qcom-pon.ko \
		kernel/drivers/rpmsg/rpmsg_char.ko \
		kernel/drivers/rpmsg/rpmsg_ctrl.ko \
		kernel/drivers/rtc/rtc-pm8xxx.ko \
		kernel/drivers/soc/qcom/icc-bwmon.ko \
		kernel/drivers/soc/qcom/qcom_stats.ko \
		kernel/drivers/soc/qcom/socinfo.ko \
		kernel/drivers/thermal/qcom/qcom-spmi-temp-alarm.ko \
		kernel/drivers/usb/storage/uas.ko \
		kernel/drivers/ufs/core/ufshcd-core.ko \
		kernel/drivers/ufs/host/ufshcd-pltfrm.ko \
		kernel/drivers/ufs/host/ufs-qcom.ko \
		kernel/fs/smb/client/cifs.ko \
		kernel/lib/crypto/libmd5.ko \
		kernel/net/ipv4/udp_tunnel.ko \
		kernel/net/ipv6/ip6_udp_tunnel.ko \
		kernel/net/llc/llc.ko \
		kernel/net/802/stp.ko \
		kernel/net/bridge/bridge.ko \
		kernel/net/bridge/br_netfilter.ko \
		kernel/drivers/net/veth.ko \
		kernel/net/netfilter/x_tables.ko \
		kernel/net/ipv4/netfilter/ip_tables.ko \
		kernel/net/ipv4/netfilter/iptable_filter.ko \
		kernel/net/ipv4/netfilter/iptable_nat.ko \
		kernel/net/ipv4/netfilter/iptable_mangle.ko \
		kernel/net/ipv4/netfilter/nf_defrag_ipv4.ko \
		kernel/net/ipv6/netfilter/nf_defrag_ipv6.ko \
		kernel/net/netfilter/nf_conntrack.ko \
		kernel/net/netfilter/nf_nat.ko \
		kernel/net/netfilter/xt_tcpudp.ko \
		kernel/net/netfilter/xt_MASQUERADE.ko \
		kernel/net/netfilter/xt_CHECKSUM.ko \
		kernel/net/bluetooth/bluetooth.ko \
		kernel/drivers/bluetooth/btbcm.ko \
		kernel/drivers/bluetooth/btqca.ko \
		kernel/drivers/bluetooth/hci_uart.ko; do
		printf '%s\n' "$module" >>"$seed_modules"
	done
	local selected_modules="$WORK_DIR/initramfs-modules.txt"
	python3 "$PUBLIC_DIR/initramfs/scripts/select-initramfs-modules.py" \
		"$base_copy" "$MODULE_OUT/lib/modules/$krel" "$seed_modules" "$selected_modules"
	local module_stage="$WORK_DIR/initramfs-module-stage"
	rm -rf "$module_stage"
	mkdir -p "$module_stage/lib/modules/$krel"
	local selected_count=0
	while IFS= read -r module; do
		[[ -n "$module" ]] || continue
		local module_source="$MODULE_OUT/lib/modules/$krel/$module"
		[[ -f "$module_source" ]] || die "selected initramfs module missing: $module"
		mkdir -p "$module_stage/lib/modules/$krel/$(dirname "$module")"
		cp "$module_source" "$module_stage/lib/modules/$krel/$module"
		printf 'usr/lib/modules/%s/%s %s 0644\n' "$krel" "$module" "$module_source" >>"$manifest"
		selected_count=$((selected_count + 1))
	done <"$selected_modules"
	[[ "$selected_count" -gt 0 ]] || die "no matching kernel modules selected for initramfs"
	local builtin_metadata
	for builtin_metadata in modules.builtin modules.builtin.modinfo modules.order; do
		[[ -f "$MODULE_OUT/lib/modules/$krel/$builtin_metadata" ]] \
			|| die "kernel module metadata missing: $builtin_metadata"
		cp "$MODULE_OUT/lib/modules/$krel/$builtin_metadata" \
			"$module_stage/lib/modules/$krel/$builtin_metadata"
	done
	depmod -b "$module_stage" "$krel" >"$WORK_DIR/depmod.log" 2>&1 || {
		cat "$WORK_DIR/depmod.log" >&2
		die "failed to generate initramfs module dependency metadata"
	}
	local metadata
	for metadata in "$module_stage/lib/modules/$krel"/modules.*; do
		[[ -f "$metadata" ]] || continue
		printf 'usr/lib/modules/%s/%s %s 0644\n' "$krel" "$(basename "$metadata")" "$metadata" >>"$manifest"
	done
	printf 'selected initramfs modules: %s\n' "$selected_count"
	local firmware
	for firmware in "$FIRMWARE_SOURCE"/*; do
		[[ -f "$firmware" ]] || continue
		printf 'usr/lib/firmware/qca/%s %s 0644\n' "$(basename "$firmware")" "$firmware" >>"$manifest"
	done
	printf '%s %s %s\n' "scripts/init-premount/surface-hardware" \
		"$PUBLIC_DIR/initramfs/scripts/surface-hardware-init-premount.sh" "0755" >>"$manifest"
	printf '%s %s %s\n' "scripts/init-premount/surface-bluetooth" \
		"$PUBLIC_DIR/initramfs/scripts/surface-bluetooth-init-premount.sh" "0755" >>"$manifest"
	printf '%s %s %s\n' "scripts/init-premount/surface-waydroid-network" \
		"$PUBLIC_DIR/initramfs/scripts/surface-waydroid-network-init-premount.sh" "0755" >>"$manifest"
	# Build both variants from the same untouched base.  The current variant
	# also needs the network modules for Waydroid, even when Bluetooth is not
	# selected in its DTB.
	rm -f "$current_initrd" "$bluetooth_initrd"
	python3 "$PUBLIC_DIR/initramfs/scripts/augment-newc-initramfs.py" \
		"$base_copy" "$current_initrd" "$manifest" usr/lib/modules/
	python3 "$PUBLIC_DIR/initramfs/scripts/augment-newc-initramfs.py" \
		"$base_copy" "$bluetooth_initrd" "$manifest" usr/lib/modules/
	local initrd order hook first_surface_hook builtin_list builtin_path
	for initrd in "$current_initrd" "$bluetooth_initrd"; do
		order=$(gzip -dc "$initrd" | cpio -i --to-stdout scripts/init-premount/ORDER 2>/dev/null) \
			|| die "cannot read initramfs premount order: $initrd"
		for hook in surface-hardware surface-bluetooth surface-waydroid-network; do
			printf '%s\n' "$order" | grep -Fq "/scripts/init-premount/$hook \"\$@\"" \
				|| die "initramfs premount hook is not registered: $hook ($initrd)"
		done
		first_surface_hook=$(printf '%s\n' "$order" | grep '/scripts/init-premount/surface-' | head -n 1)
		[[ "$first_surface_hook" == '/scripts/init-premount/surface-hardware "$@"' ]] \
			|| die "hardware premount hook does not run first: $initrd"
		builtin_list=$(gzip -dc "$initrd" | cpio -i --to-stdout \
			"usr/lib/modules/$krel/modules.builtin" 2>/dev/null) \
			|| die "cannot read initramfs built-in module metadata: $initrd"
		for builtin_path in \
			kernel/drivers/gpu/drm/bridge/aux-bridge.ko \
			kernel/drivers/phy/qualcomm/phy-qcom-qmp-combo.ko \
			kernel/drivers/usb/dwc3/dwc3-qcom.ko \
			kernel/drivers/usb/storage/uas.ko; do
			printf '%s\n' "$builtin_list" | grep -Fxq "$builtin_path" \
				|| die "USB-root built-in metadata is missing: $builtin_path ($initrd)"
		done
		for ufs_module in \
			kernel/drivers/phy/qualcomm/phy-qcom-qmp-ufs.ko \
			kernel/drivers/ufs/core/ufshcd-core.ko \
			kernel/drivers/ufs/host/ufshcd-pltfrm.ko \
			kernel/drivers/ufs/host/ufs-qcom.ko; do
			if [[ -f "$MODULE_OUT/lib/modules/$krel/$ufs_module" ]]; then
				gzip -dc "$initrd" | cpio -it --quiet \
					"usr/lib/modules/$krel/$ufs_module" >/dev/null 2>&1 \
					|| die "UFS module is missing from initramfs: $ufs_module ($initrd)"
			else
				printf '%s\n' "$builtin_list" | grep -Fxq "$ufs_module" \
					|| die "UFS module is neither built in nor in initramfs: $ufs_module ($initrd)"
			fi
		done
	done
	rm -f "$base_copy"
}

build_uki() {
	need ukify; need file
	local image="$1" initrd="$2" output="$3" dtb="$4" cmdline_file="${5:-$CMDLINE}"
	[[ -f "$image" && -f "$initrd" && -f "$dtb" ]] || die "UKI input missing"
	[[ -f "$UKI_STUB" ]] || die "UKI stub not found: $UKI_STUB"
	if grep -Eq '(^|[[:space:]])(drm\.debug|ignore_loglevel)(=|[[:space:]]|$)' "$cmdline_file"; then
		die "debug logging option found in UKI command line"
	fi
	mkdir -p "$(dirname "$output")"
	ukify build --stub="$UKI_STUB" --linux="$image" --initrd="$initrd" \
		--devicetree="$dtb" --cmdline="@$cmdline_file" --os-release="@$OS_RELEASE" \
		--output="$output"
	file "$output" | grep -Eqi 'PE32\+.*(Aarch64|ARM64|ARM aarch64)' || die "not an ARM64 UKI: $output"
}

build_uki_pair() {
	write_neutral_metadata
	[[ -f "$kernel_image" ]] || build_kernel
	[[ -f "$base_dtb" && -f "$bluetooth_dtb" && -f "$bluetooth_fingerprint_dtb" ]] || build_dtb
	local krel
	krel=$(tr -d '\n' <"$kernel_release")
	[[ -f "$current_initrd" ]] || build_initramfs "$krel"
	[[ -f "$bluetooth_initrd" ]] || build_initramfs "$krel"
	log "Building neutral UKIs"
	# The default current image is the all-feature configuration used for
	# normal boots: Type-C, touchscreen, Bluetooth, and fingerprint reader.
	build_uki "$kernel_image" "$current_initrd" "$current_uki" "$bluetooth_fingerprint_dtb"
	build_uki "$kernel_image" "$bluetooth_initrd" "$bluetooth_uki" "$bluetooth_dtb"
	build_uki "$kernel_image" "$bluetooth_initrd" "$fingerprint_uki" "$bluetooth_fingerprint_dtb"
}

build_bluetooth() {
	write_neutral_metadata
	[[ -f "$kernel_image" ]] || build_kernel
	[[ -f "$base_dtb" && -f "$bluetooth_dtb" ]] || build_dtb
	local krel
	krel=$(tr -d '\n' <"$kernel_release")
	build_initramfs "$krel"
	build_uki "$kernel_image" "$bluetooth_initrd" "$bluetooth_uki" "$bluetooth_dtb"
}

build_fingerprint() {
	write_neutral_metadata
	[[ -f "$kernel_image" ]] || build_kernel
	[[ -f "$bluetooth_fingerprint_dtb" ]] || build_dtb
	local krel
	krel=$(tr -d '\n' <"$kernel_release")
	[[ -f "$bluetooth_initrd" ]] || build_initramfs "$krel"
	build_uki "$kernel_image" "$bluetooth_initrd" "$fingerprint_uki" "$bluetooth_fingerprint_dtb"
}

write_sleep_cmdline() {
	[[ -f "$CMDLINE" ]] || die "base command line has not been generated"
	# The platform currently selects deep sleep by default.  Keep the target
	# command line intact except for the sleep policy used by this test UKI.
	sed -E 's/(^|[[:space:]])mem_sleep_default=[^[:space:]]+//g' "$CMDLINE" \
		| tr '\n' ' ' \
		| sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' >"$SLEEP_CMDLINE"
	printf ' mem_sleep_default=s2idle usbcore.autosuspend=-1\n' >>"$SLEEP_CMDLINE"
}

build_sleep() {
	[[ -n "$CMDLINE_INPUT" ]] || die "sleep test requires SURFACE_CMDLINE_FILE from the target OS"
	write_neutral_metadata
	[[ -f "$kernel_image" ]] || build_kernel
	[[ -f "$base_dtb" && -f "$bluetooth_fingerprint_dtb" ]] || build_dtb
	local krel
	krel=$(tr -d '\n' <"$kernel_release")
	[[ -f "$current_initrd" ]] || build_initramfs "$krel"
	write_sleep_cmdline
	build_uki "$kernel_image" "$current_initrd" "$sleep_uki" \
		"$bluetooth_fingerprint_dtb" "$SLEEP_CMDLINE"
	printf 'Sleep-test UKI: %s\n' "$sleep_uki"
}

write_android_cmdline() {
	[[ -f "$CMDLINE" ]] || die "base command line has not been generated"
	tr '\n' ' ' <"$CMDLINE" | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' >"$ANDROID_CMDLINE"
	grep -Eq '(^|[[:space:]])root=[^[:space:]]+' "$ANDROID_CMDLINE" \
		|| die "Android Mode command line must contain an explicit root= parameter"
	grep -Fq 'CHANGE-ME' "$ANDROID_CMDLINE" \
		&& die "Android Mode command line still contains the CHANGE-ME root placeholder"
	grep -Eq '(^|[[:space:]])surface\.mode=' "$ANDROID_CMDLINE" \
		&& die "base command line already contains surface.mode; use a neutral base cmdline"
	printf ' surface.mode=android\n' >>"$ANDROID_CMDLINE"
}

build_surface_controls_apk() {
	local apk_out="$ANDROID_MODE_OUT/android/SurfaceControls.apk"
	mkdir -p "$(dirname "$apk_out")"
	if [[ -n "${SURFACE_CONTROLS_APK:-}" ]]; then
		[[ -f "$SURFACE_CONTROLS_APK" ]] || die "Surface Controls APK not found: $SURFACE_CONTROLS_APK"
		if [[ "$SURFACE_CONTROLS_APK" != "$apk_out" ]]; then
			cp "$SURFACE_CONTROLS_APK" "$apk_out"
		fi
		return 0
	fi
	"$PUBLIC_DIR/android-mode/app/build-android-apk.sh" "$apk_out"
}

stage_android_mode() {
	local stage="$ANDROID_MODE_OUT"
	rm -rf "$stage"
	mkdir -p "$stage/android" "$stage/boot" "$stage/loader" "$stage/systemd" \
		"$stage/tmpfiles.d" "$stage/usr/bin" "$stage/usr/libexec" "$stage/waydroid"
	cp "$android_uki" "$stage/boot/surface-laptop-13-android.efi"
	cat >"$stage/loader/surface-android.conf" <<'EOF'
title Surface Laptop 13 Android Mode
efi /EFI/Linux/surface-laptop-13-android.efi
EOF
	cp "$PUBLIC_DIR/android-mode/systemd/surface-android-mode.service" "$stage/systemd/"
	cp "$PUBLIC_DIR/android-mode/systemd/surface-android-control.service" "$stage/systemd/"
	cp "$PUBLIC_DIR/android-mode/systemd/surface-android-control.socket" "$stage/systemd/"
	cp "$PUBLIC_DIR/android-mode/systemd/waydroid-control.conf" "$stage/systemd/"
	cp "$PUBLIC_DIR/android-mode/systemd/greetd.service.d.conf" "$stage/systemd/"
	cp "$PUBLIC_DIR/android-mode/systemd/getty-tty1.service.d.conf" "$stage/systemd/"
	cp "$PUBLIC_DIR/android-mode/tmpfiles.d/surface-android-control.conf" "$stage/tmpfiles.d/"
	cp "$PUBLIC_DIR/android-mode/bin/surface-android-session" "$stage/usr/bin/"
	cp "$PUBLIC_DIR/android-mode/bin/surface-android-control" "$stage/usr/libexec/"
	cp "$PUBLIC_DIR/android-mode/waydroid/surface-control.conf" "$stage/waydroid/"
	cp "$PUBLIC_DIR/android-mode/install-android-mode.sh" "$stage/"
	chmod 0755 "$stage/usr/bin/surface-android-session" "$stage/usr/libexec/surface-android-control" \
		"$stage/install-android-mode.sh"
	build_surface_controls_apk
	verify_android_stage
	printf '%s\n' "Android Mode staged at $stage"
}

verify_android_stage() {
	local stage="$ANDROID_MODE_OUT" forbidden name_scan_status=1
	[[ -s "$stage/boot/surface-laptop-13-android.efi" ]] || die "Android UKI was not staged"
	[[ -s "$stage/android/SurfaceControls.apk" ]] || die "Surface Controls APK was not staged"
	grep -Eq '(^|[[:space:]])surface\.mode=android([[:space:]]|$)' "$ANDROID_CMDLINE" \
		|| die "Android command line is missing surface.mode=android"
	forbidden=$(forbidden_name)
	if command -v rg >/dev/null 2>&1; then
		rg -a -ni --hidden --glob '!.git' "$forbidden" "$stage" >/dev/null 2>&1 || name_scan_status=$?
	else
		grep -Rai -- "$forbidden" "$stage" >/dev/null 2>&1 || name_scan_status=$?
	fi
	if [[ "$name_scan_status" -eq 0 ]]; then
		die "forbidden distro-specific name found in Android Mode output"
	fi
	if find "$stage" -type f -printf '%f\n' | grep -Eiq '(^|[-_.])(current|fallback)([-_.]|$)'; then
		die "Android Mode output contains a current/fallback-named file"
	fi
}

build_android_mode() {
	check_android_inputs
	[[ -n "$CMDLINE_INPUT" ]] || die "Android Mode requires SURFACE_CMDLINE_FILE from the target OS"
	write_neutral_metadata
	[[ -f "$kernel_image" ]] || build_kernel
	[[ -f "$base_dtb" && -f "$bluetooth_fingerprint_dtb" ]] || build_dtb
	local krel
	krel=$(tr -d '\n' <"$kernel_release")
	[[ -f "$current_initrd" ]] || build_initramfs "$krel"
	write_android_cmdline
	build_uki "$kernel_image" "$current_initrd" "$android_uki" "$bluetooth_fingerprint_dtb" "$ANDROID_CMDLINE"
	stage_android_mode
}

write_manifest() {
	need python3
	python3 - "$CURRENT_DIR" <<'PY'
import hashlib, json, os, sys
root = os.path.abspath(sys.argv[1])
def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()
files = {}
for base, dirs, names in os.walk(root):
    dirs[:] = sorted(d for d in dirs if d not in {".git"})
    for name in sorted(names):
        if name in {"MANIFEST.json", "SHA256SUMS"}:
            continue
        path = os.path.join(base, name)
        rel = os.path.relpath(path, root)
        files[rel] = {"bytes": os.path.getsize(path), "sha256": digest(path)}
data = {
    "schema": 1,
    "project": "Surface Laptop 13 Linux Hardware Support",
    "artifact_set": "surface-laptop-13-current",
    "contains_full_os_image": False,
    "files": files,
}
with open(os.path.join(root, "MANIFEST.json"), "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
	find "$CURRENT_DIR" -type f ! -name MANIFEST.json ! -name SHA256SUMS -print0 |
		sort -z |
		xargs -0 sha256sum | sed "s#  $CURRENT_DIR/#  #" >"$CURRENT_DIR/SHA256SUMS"
}

package_artifacts() {
	log "Packaging Surface boot components"
	build_kernel
	build_dtb
	build_uki_pair
	rm -rf "$CURRENT_DIR/kernel" "$CURRENT_DIR/dtb" "$CURRENT_DIR/initramfs" "$CURRENT_DIR/firmware" "$CURRENT_DIR/uki"
	mkdir -p "$CURRENT_DIR/kernel" "$CURRENT_DIR/dtb" "$CURRENT_DIR/initramfs" "$CURRENT_DIR/firmware/qca" "$CURRENT_DIR/uki" "$CURRENT_DIR/recovery"
	cp "$kernel_image" "$CURRENT_DIR/kernel/Image"
	cp "$kernel_config" "$CURRENT_DIR/kernel/config"
	cp "$kernel_release" "$CURRENT_DIR/kernel/release"
	cp "$bluetooth_fingerprint_dtb" "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb"
	cp "$bluetooth_dtb" "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb"
	cp "$bluetooth_fingerprint_dtb" "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth-fingerprint.dtb"
	cp "$current_initrd" "$CURRENT_DIR/initramfs/surface-laptop-13-current.img"
	cp "$bluetooth_initrd" "$CURRENT_DIR/initramfs/surface-laptop-13-bluetooth.img"
	cp "$current_uki" "$CURRENT_DIR/uki/surface-laptop-13-current.efi"
	cp "$bluetooth_uki" "$CURRENT_DIR/uki/surface-laptop-13-bluetooth.efi"
	cp "$fingerprint_uki" "$CURRENT_DIR/uki/surface-laptop-13-fingerprint.efi"
	local firmware
	for firmware in "$FIRMWARE_SOURCE"/*; do
		[[ -f "$firmware" ]] || continue
		cp "$firmware" "$CURRENT_DIR/firmware/qca/"
	done
	cp "$PUBLIC_DIR/recovery/restore-components.sh" "$CURRENT_DIR/recovery/restore-components.sh"
	chmod 0755 "$CURRENT_DIR/recovery/restore-components.sh"
	cp "$PUBLIC_DIR/README.md" "$CURRENT_DIR/README.md"
	write_manifest
}

build_release() {
	package_artifacts
	need dpkg-deb
	"$PUBLIC_DIR/packaging/build-bundle-deb.sh" \
		"$CURRENT_DIR" "${SURFACE_RELEASE_DIR:-$WORK_DIR/release-assets}"
}

forbidden_name() { printf "%s" "circl""eos"; }

verify() {
	need grep; need strings; need python3; need sha256sum; need stat; need fdtget
	local forbidden
	forbidden=$(forbidden_name)
	log "Verifying public artifact boundaries"
	local scan_status=1
	if command -v rg >/dev/null 2>&1; then
		rg -a -ni --hidden --glob '!.git' "$forbidden" "$PUBLIC_DIR" "$CURRENT_DIR" >/tmp/surface-name-check.log 2>&1 || scan_status=$?
	else
		grep -Rani --exclude-dir=.git -- "$forbidden" "$PUBLIC_DIR" "$CURRENT_DIR" >/tmp/surface-name-check.log 2>&1 || scan_status=$?
	fi
	if [[ "$scan_status" -eq 0 ]]; then
		cat /tmp/surface-name-check.log >&2
		die "forbidden distro-specific name found in public output"
	fi
	local f
	for f in "$CURRENT_DIR/kernel/Image" "$CURRENT_DIR/uki"/*.efi; do
		[[ -f "$f" ]] || continue
		if strings "$f" | grep -qi "$forbidden"; then die "forbidden name found in binary: $f"; fi
	done
	# A public clone intentionally has no generated recovery set.  The checks
	# below validate SURFACE-CURRENT only when a local `package` run created it.
	if [[ ! -d "$CURRENT_DIR" ]]; then
		log "Source verification passed (no local recovery set present)"
		return 0
	fi
	[[ -f "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" ]] || die "current DTB is missing"
	[[ -f "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" ]] || die "Bluetooth DTB is missing"
	[[ -f "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth-fingerprint.dtb" ]] || die "fingerprint DTB is missing"
	[[ -f "$CURRENT_DIR/uki/surface-laptop-13-fingerprint.efi" ]] || die "fingerprint UKI is missing"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" /soc@0/usb@a600000 dr_mode)" == host ]] || die "current DTB USB-C port 0 is not host"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" /soc@0/usb@a800000 dr_mode)" == host ]] || die "current DTB USB-C port 1 is not host"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 hid-descr-addr)" == 0 ]] || die "current DTB touchscreen HID descriptor address is not zero"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 hid-descr-addr)" == 0 ]] || die "Bluetooth DTB touchscreen HID descriptor address is not zero"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" /soc@0/geniqup@ac0000/serial@a98000 status)" == okay ]] || die "Bluetooth UART is not enabled"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" /soc@0/geniqup@ac0000/serial@a98000/bluetooth compatible)" == qcom,wcn7850-bt ]] || die "Bluetooth node is missing"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth-fingerprint.dtb" /soc@0/usb@a200000 status)" == okay ]] || die "fingerprint USB controller is disabled"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth-fingerprint.dtb" /soc@0/usb@a200000 dr_mode)" == host ]] || die "fingerprint USB controller is not host mode"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth-fingerprint.dtb" /soc@0/phy@88e0000 status)" == okay ]] || die "fingerprint eUSB2 PHY is disabled"
	[[ -f "$CURRENT_DIR/firmware/qca/hmtbtfw20.tlv" ]] || die "Bluetooth firmware is missing"
	while IFS= read -r -d '' f; do
		case "$f" in
			*/.work/*) continue ;;
			*/SURFACE-CURRENT/uki/*.efi|*/SURFACE-CURRENT/initramfs/*.img) ;;
			*) [[ $(stat -c '%s' "$f") -le 104857600 ]] || die "file exceeds 100 MiB Git limit: $f" ;;
		esac
	done < <(find "$PUBLIC_DIR" "$CURRENT_DIR" -type f -print0)
	if find "$CURRENT_DIR" -type f -name '*.img' ! -path "$CURRENT_DIR/initramfs/*" -print -quit | grep -q .; then
		die "non-initramfs disk image found in SURFACE-CURRENT"
	fi
	if [[ -f "$CURRENT_DIR/MANIFEST.json" ]]; then
		python3 -m json.tool "$CURRENT_DIR/MANIFEST.json" >/dev/null
	fi
	log "Verification passed"
}

target=${1:-check}
case "$target" in
	check) check_full_inputs ;;
	kernel) check_inputs; build_kernel ;;
	dtb) check_inputs; build_dtb ;;
	initramfs) check_full_inputs; write_neutral_metadata; [[ -f "$kernel_image" ]] || build_kernel; build_dtb; build_initramfs "$(tr -d '\n' <"$kernel_release")" ;;
	uki) check_full_inputs; build_uki_pair ;;
	bluetooth) check_full_inputs; build_bluetooth ;;
	fingerprint) check_full_inputs; build_fingerprint ;;
	sleep) check_full_inputs; build_sleep ;;
	package) check_full_inputs; package_artifacts ; verify ;;
	release) check_full_inputs; build_release ; verify ;;
	android) check_full_inputs; build_android_mode ;;
	verify) check_inputs; verify ;;
	*) die "usage: $0 {check|kernel|dtb|initramfs|uki|bluetooth|fingerprint|sleep|package|release|android|verify}" ;;
esac
