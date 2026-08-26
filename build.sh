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
BASE_DTS=${BASE_DTS:-$PUBLIC_DIR/device-tree/base/surface-laptop-13-typec.dts}
BASE_DTB_INPUT=${BASE_DTB_INPUT:-$PUBLIC_DIR/device-tree/base/surface-laptop-13-typec.dtb}
UKI_STUB=${UKI_STUB:-/usr/lib/systemd/boot/efi/linuxaa64.efi.stub}
KERNEL_JOBS=${KERNEL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

KERNEL_OUT="$WORK_DIR/kernel"
KERNEL_WORK_SOURCE="$WORK_DIR/kernel-source"
MODULE_OUT="$WORK_DIR/modules"
DTB_OUT="$WORK_DIR/dtb"
INITRD_OUT="$WORK_DIR/initramfs"
UKI_OUT="$WORK_DIR/uki"
OS_RELEASE="$WORK_DIR/os-release"
CMDLINE="$WORK_DIR/cmdline"

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
	# The UUID is intentionally supplied by the consumer.  A label or UUID may
	# be appended by an OS-specific wrapper without rebuilding the UKI.
	cat >"$CMDLINE" <<'EOF'
root=UUID=CHANGE-ME rootfstype=ext4 rootwait rw quiet splash cma=128M
EOF
}

check_inputs() {
	local f
	need bash; need find; need dtc; need fdtoverlay; need fdtget
	for f in "$KERNEL_CONFIG" "$BASE_DTS" "$BASE_DTB_INPUT"; do
		[[ -f "$f" ]] || die "input not found: $f"
	done
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
	need make; need ukify; need python3; need sha256sum; need strings; need rg
	local f
	for f in "$KERNEL_SOURCE/Makefile" "$INITRD_BASE" "$UKI_STUB"; do
		[[ -f "$f" ]] || die "input not found: $f"
	done
	[[ -d "$FIRMWARE_SOURCE" ]] || die "firmware directory not found: $FIRMWARE_SOURCE"
}

apply_public_patches() {
	[[ "${KERNEL_APPLY_PATCHES:-0}" == 1 ]] || return 0
	need patch
	local patch_file
	for patch_file in "$PUBLIC_DIR"/kernel/patches/*.patch; do
		[[ -f "$patch_file" ]] || continue
		if patch --dry-run --batch --silent -d "$KERNEL_WORK_SOURCE" -p1 <"$patch_file" >/dev/null 2>&1; then
			patch --batch --silent -d "$KERNEL_WORK_SOURCE" -p1 <"$patch_file"
		elif patch --dry-run --batch --silent -R -d "$KERNEL_WORK_SOURCE" -p1 <"$patch_file" >/dev/null 2>&1; then
			printf 'patch already present: %s\n' "$(basename "$patch_file")"
		else
			die "kernel patch does not apply cleanly: $patch_file"
		fi
	done
}

build_kernel() {
	need make; need aarch64-linux-gnu-gcc
	[[ -f "$KERNEL_SOURCE/Makefile" ]] || die "kernel source directory not found: $KERNEL_SOURCE"
	mkdirs
	if [[ ! -f "$KERNEL_SOURCE/.config" && ! -d "$KERNEL_SOURCE/include/config" && ! -d "$KERNEL_SOURCE/arch/arm64/include/generated" ]]; then
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
	rm -rf "$KERNEL_OUT" "$MODULE_OUT"
	mkdir -p "$KERNEL_OUT" "$MODULE_OUT"
	cp "$KERNEL_CONFIG" "$KERNEL_OUT/.config"
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
	make -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$MODULE_OUT" modules_install
	local krel
	krel=$(make -s -C "$KERNEL_WORK_SOURCE" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)
	cp "$KERNEL_OUT/arch/arm64/boot/Image" "$kernel_image"
	cp "$KERNEL_OUT/.config" "$kernel_config"
	printf '%s\n' "$krel" >"$kernel_release"
	[[ "$krel" == *surface-laptop-13* ]] || die "kernel release is not neutral: $krel"
	printf 'kernel release: %s\n' "$krel"
}

build_dtb() {
	need dtc; need fdtoverlay; need fdtget
	mkdirs
	log "Building Type-C, touchscreen, Bluetooth, and fingerprint device trees"
	local raw_base_dtb="$DTB_OUT/surface-laptop-13-typec-base.dtb"
	# Prefer the measured Type-C baseline DTB. The standalone DTS is retained
	# for inspection and can be selected explicitly when rebuilding it.
	if [[ "${REBUILD_BASE_DTB:-0}" == 1 ]]; then
		dtc -@ -I dts -O dtb -o "$raw_base_dtb" "$BASE_DTS" >"$DTB_OUT/base-dtc.log" 2>&1
	else
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
	for candidate in "$base_dtb" "$bluetooth_dtb"; do
		[[ -s "$candidate" ]] || die "empty DTB: $candidate"
		[[ "$(fdtget "$candidate" /soc@0/usb@a600000 dr_mode)" == host ]] || die "USB-C port 0 is not host in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/usb@a800000 dr_mode)" == host ]] || die "USB-C port 1 is not host in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/geniqup@ac0000/i2c@a80000 status)" == okay ]] || die "touchscreen I2C controller is disabled in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 compatible)" == hid-over-i2c ]] || die "touchscreen node is missing in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 hid-descr-addr)" == 0 ]] || die "touchscreen HID descriptor address is not zero in $candidate"
	done
	[[ "$(fdtget "$bluetooth_dtb" /soc@0/geniqup@ac0000/serial@a98000 status)" == okay ]] || die "Bluetooth UART is disabled"
	[[ "$(fdtget "$bluetooth_dtb" /soc@0/geniqup@ac0000/serial@a98000/bluetooth compatible)" == qcom,wcn7850-bt ]] || die "Bluetooth compatible is unexpected"
	[[ "$(fdtget "$bluetooth_dtb" /soc@0/geniqup@ac0000/serial@a98000/bluetooth max-speed)" == 3200000 ]] || die "Bluetooth UART speed is unexpected"
	for candidate in "$fingerprint_dtb" "$bluetooth_fingerprint_dtb"; do
		[[ "$(fdtget "$candidate" /soc@0/usb@a200000 status)" == okay ]] || die "fingerprint USB controller is disabled in $candidate"
		[[ "$(fdtget "$candidate" /soc@0/usb@a200000 dr_mode)" == host ]] || die "fingerprint USB controller is not host mode in $candidate"
	done
}

build_initramfs() {
	need python3
	[[ -f "$INITRD_BASE" ]] || die "initramfs input not found: $INITRD_BASE"
	[[ -d "$FIRMWARE_SOURCE" ]] || die "firmware directory not found: $FIRMWARE_SOURCE"
	mkdirs
	log "Preparing OS-neutral initramfs inputs"
	cp "$INITRD_BASE" "$current_initrd"
	# The base initramfs is a boot component only.  It is deliberately not
	# rebuilt from a desktop root filesystem here.
	local krel="$1"
	local manifest="$WORK_DIR/bluetooth-files.manifest"
	: >"$manifest"
	local module
	for module in \
		kernel/crypto/ecc.ko \
		kernel/crypto/kpp.ko \
		kernel/crypto/ecdh_generic.ko \
		kernel/net/bluetooth/bluetooth.ko \
		kernel/drivers/bluetooth/btbcm.ko \
		kernel/drivers/bluetooth/btqca.ko \
		kernel/drivers/bluetooth/hci_uart.ko; do
		[[ -f "$MODULE_OUT/lib/modules/$krel/$module" ]] || die "Bluetooth module missing: $module"
		printf 'usr/lib/modules/%s/%s %s 0644\n' "$krel" "$module" "$MODULE_OUT/lib/modules/$krel/$module" >>"$manifest"
	done
	local firmware
	for firmware in "$FIRMWARE_SOURCE"/*; do
		[[ -f "$firmware" ]] || continue
		printf 'usr/lib/firmware/qca/%s %s 0644\n' "$(basename "$firmware")" "$firmware" >>"$manifest"
	done
	printf '%s\n' "scripts/init-premount/surface-bluetooth" \
		"$PUBLIC_DIR/initramfs/scripts/surface-bluetooth-init-premount.sh" "0755" >>"$manifest"
	python3 "$PUBLIC_DIR/initramfs/scripts/augment-newc-initramfs.py" "$current_initrd" "$bluetooth_initrd" "$manifest"
}

build_uki() {
	need ukify; need file
	local image="$1" initrd="$2" output="$3" dtb="$4"
	[[ -f "$image" && -f "$initrd" && -f "$dtb" ]] || die "UKI input missing"
	[[ -f "$UKI_STUB" ]] || die "UKI stub not found: $UKI_STUB"
	mkdir -p "$(dirname "$output")"
	ukify build --stub="$UKI_STUB" --linux="$image" --initrd="$initrd" \
		--devicetree="$dtb" --cmdline="@$CMDLINE" --os-release="@$OS_RELEASE" \
		--output="$output"
	file "$output" | grep -Eq 'PE32\\+.*(Aarch64|ARM64|ARM aarch64)' || die "not an ARM64 UKI: $output"
}

build_uki_pair() {
	write_neutral_metadata
	[[ -f "$kernel_image" ]] || build_kernel
	[[ -f "$base_dtb" && -f "$bluetooth_dtb" ]] || build_dtb
	local krel
	krel=$(tr -d '\n' <"$kernel_release")
	[[ -f "$current_initrd" ]] || build_initramfs "$krel"
	[[ -f "$bluetooth_initrd" ]] || build_initramfs "$krel"
	log "Building neutral UKIs"
	build_uki "$kernel_image" "$current_initrd" "$current_uki" "$base_dtb"
	build_uki "$kernel_image" "$bluetooth_initrd" "$bluetooth_uki" "$bluetooth_dtb"
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
	cp "$base_dtb" "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb"
	cp "$bluetooth_dtb" "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb"
	cp "$current_initrd" "$CURRENT_DIR/initramfs/surface-laptop-13-current.img"
	cp "$bluetooth_initrd" "$CURRENT_DIR/initramfs/surface-laptop-13-bluetooth.img"
	cp "$current_uki" "$CURRENT_DIR/uki/surface-laptop-13-current.efi"
	cp "$bluetooth_uki" "$CURRENT_DIR/uki/surface-laptop-13-bluetooth.efi"
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

forbidden_name() { printf "%s" "circl""eos"; }

verify() {
	need rg; need strings; need python3; need sha256sum; need stat; need fdtget
	local forbidden
	forbidden=$(forbidden_name)
	log "Verifying public artifact boundaries"
	if rg -a -ni "$forbidden" "$PUBLIC_DIR" "$CURRENT_DIR" >/tmp/surface-name-check.log 2>&1; then
		cat /tmp/surface-name-check.log >&2
		die "forbidden distro-specific name found in public output"
	fi
	local f
	for f in "$CURRENT_DIR/kernel/Image" "$CURRENT_DIR/uki"/*.efi; do
		[[ -f "$f" ]] || continue
		if strings "$f" | grep -qi "$forbidden"; then die "forbidden name found in binary: $f"; fi
	done
	[[ -f "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" ]] || die "current DTB is missing"
	[[ -f "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" ]] || die "Bluetooth DTB is missing"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" /soc@0/usb@a600000 dr_mode)" == host ]] || die "current DTB USB-C port 0 is not host"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" /soc@0/usb@a800000 dr_mode)" == host ]] || die "current DTB USB-C port 1 is not host"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-current.dtb" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 hid-descr-addr)" == 0 ]] || die "current DTB touchscreen HID descriptor address is not zero"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34 hid-descr-addr)" == 0 ]] || die "Bluetooth DTB touchscreen HID descriptor address is not zero"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" /soc@0/geniqup@ac0000/serial@a98000 status)" == okay ]] || die "Bluetooth UART is not enabled"
	[[ "$(fdtget "$CURRENT_DIR/dtb/surface-laptop-13-bluetooth.dtb" /soc@0/geniqup@ac0000/serial@a98000/bluetooth compatible)" == qcom,wcn7850-bt ]] || die "Bluetooth node is missing"
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
	package) check_full_inputs; package_artifacts ; verify ;;
	verify) check_inputs; verify ;;
	*) die "usage: $0 {check|kernel|dtb|initramfs|uki|bluetooth|fingerprint|package|verify}" ;;
esac
