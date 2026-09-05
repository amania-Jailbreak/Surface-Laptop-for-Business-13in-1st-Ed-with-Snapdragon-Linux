#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TARGET_ROOT=${TARGET_ROOT:-/mnt/target}
TARGET_IMAGE=${TARGET_IMAGE:-}
KERNEL_SOURCE=${KERNEL_SOURCE:-/root/linux}
INITRD_BASE=${INITRD_BASE:-}
FIRMWARE_SOURCE=${FIRMWARE_SOURCE:-}
WCN7850_FIRMWARE_SOURCE=${WCN7850_FIRMWARE_SOURCE:-}
UKI_STUB=${UKI_STUB:-}
UKIFY=${UKIFY:-}
SURFACE_OUTPUT_DIR=${SURFACE_OUTPUT_DIR:-$ROOT_DIR/build}
SURFACE_WORK_DIR=${SURFACE_WORK_DIR:-$SURFACE_OUTPUT_DIR/.work}
KERNEL_APPLY_PATCHES=${KERNEL_APPLY_PATCHES:-1}

INSTALL_DEPS=0
DOWNLOAD_STUB=1
BUILD_TARGET=package
TARGET_MOUNTED=0

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

log() {
	printf '\n==> %s\n' "$*"
}

usage() {
	cat <<'EOF'
Usage: ./build-debian.sh [options] [check|kernel|dtb|initramfs|uki|package]

This wrapper prepares a Debian cross-build and then invokes ./build.sh.
It does not create an operating-system root filesystem or invent an initramfs
or Qualcomm firmware. Those inputs must come from the target ARM64 system.

Options:
  --install-deps       Install Debian build dependencies with apt-get.
  --target-root DIR    Mounted target root filesystem (default: /mnt/target).
  --target-image FILE  Mount an existing root filesystem image read-only.
  --kernel DIR         Linux source tree (default: /root/linux).
  --initrd FILE        Existing target initramfs archive.
  --firmware DIR       Directory containing qca firmware files.
  --wcn7850-firmware DIR
                       Directory containing ath12k/WCN7850 Wi-Fi firmware.
  --stub FILE          ARM64 linuxaa64.efi.stub file.
  --output DIR         Final artifact directory (default: ./build).
  --no-download-stub   Do not download systemd-boot-efi:arm64 when needed.
  -h, --help           Show this help.

Environment variables with the same names are also accepted:
  TARGET_ROOT TARGET_IMAGE KERNEL_SOURCE INITRD_BASE FIRMWARE_SOURCE
  WCN7850_FIRMWARE_SOURCE UKI_STUB UKIFY
  SURFACE_OUTPUT_DIR SURFACE_WORK_DIR KERNEL_APPLY_PATCHES

Examples:
  ./build-debian.sh --install-deps dtb
  ./build-debian.sh --target-root /mnt/target package
  ./build-debian.sh --target-image /path/to/existing-arm64-rootfs.img package
  INITRD_BASE=/mnt/target/boot/initrd.img-6.x \
    FIRMWARE_SOURCE=/mnt/target/lib/firmware/qca \
    WCN7850_FIRMWARE_SOURCE=/mnt/target/lib/firmware/ath12k/WCN7850/hw2.0 \
    ./build-debian.sh package
EOF
}

require_root_for_apt() {
	[[ "$(id -u)" -eq 0 ]] || die "apt setup requires root; run this script from a root shell"
}

parse_args() {
	while (($#)); do
		case "$1" in
			--install-deps)
				INSTALL_DEPS=1
				;;
			--no-download-stub)
				DOWNLOAD_STUB=0
				;;
			--target-root)
				shift
				(($#)) || die "--target-root needs a directory"
				TARGET_ROOT=$1
				;;
			--target-image)
				shift
				(($#)) || die "--target-image needs a file"
				TARGET_IMAGE=$1
				;;
			--kernel)
				shift
				(($#)) || die "--kernel needs a directory"
				KERNEL_SOURCE=$1
				;;
			--initrd)
				shift
				(($#)) || die "--initrd needs a file"
				INITRD_BASE=$1
				;;
			--firmware)
				shift
				(($#)) || die "--firmware needs a directory"
				FIRMWARE_SOURCE=$1
				;;
			--wcn7850-firmware)
				shift
				(($#)) || die "--wcn7850-firmware needs a directory"
				WCN7850_FIRMWARE_SOURCE=$1
				;;
			--stub)
				shift
				(($#)) || die "--stub needs a file"
				UKI_STUB=$1
				;;
			--output)
				shift
				(($#)) || die "--output needs a directory"
				SURFACE_OUTPUT_DIR=$1
				if [[ -z "${SURFACE_WORK_DIR:-}" || "$SURFACE_WORK_DIR" == "$ROOT_DIR/build/.work" ]]; then
					SURFACE_WORK_DIR="$SURFACE_OUTPUT_DIR/.work"
				fi
				;;
			check|kernel|dtb|initramfs|uki|bluetooth|fingerprint|package|verify)
				BUILD_TARGET=$1
				;;
			-h|--help)
				usage
				exit 0
				;;
			*)
				die "unknown argument: $1 (use --help)"
				;;
			esac
		shift
	done
}

clear_example_inputs() {
	case "$INITRD_BASE" in
		/path/to/initramfs|/path/to/initrd|/path/to/initrd.img)
			INITRD_BASE=
			;;
	esac
	case "$FIRMWARE_SOURCE" in
		/path/to/qca-firmware|/path/to/firmware|/path/to/qca)
			FIRMWARE_SOURCE=
			;;
	esac
}

install_dependencies() {
	require_root_for_apt
	command -v apt-get >/dev/null 2>&1 || die "apt-get not found"
	log "Installing Debian build dependencies"
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		bc binutils-aarch64-linux-gnu bison build-essential ca-certificates \
		cpio device-tree-compiler file flex gcc-aarch64-linux-gnu git gzip \
		kmod libelf-dev libssl-dev python3 ripgrep systemd
}

cleanup_target_image() {
	if [[ "$TARGET_MOUNTED" -eq 1 ]]; then
		umount "$TARGET_ROOT" || printf 'WARNING: could not unmount %s\n' "$TARGET_ROOT" >&2
	fi
}

mount_target_image() {
	[[ -z "$TARGET_IMAGE" ]] && return 0
	require_root_for_apt
	command -v mount >/dev/null 2>&1 || die "mount not found"
	command -v umount >/dev/null 2>&1 || die "umount not found"
	[[ -f "$TARGET_IMAGE" ]] || die "target image not found: $TARGET_IMAGE (this option does not create an image)"
	[[ ! -e "$TARGET_ROOT" ]] && mkdir -p "$TARGET_ROOT"
	if command -v findmnt >/dev/null 2>&1 && findmnt -rn -T "$TARGET_ROOT" >/dev/null 2>&1; then
		die "target root is already mounted: $TARGET_ROOT"
	fi
	if [[ -n "$(find "$TARGET_ROOT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
		die "target root must be an empty mountpoint for --target-image: $TARGET_ROOT"
	fi
	log "Mounting target image read-only"
	if ! mount -o loop,ro "$TARGET_IMAGE" "$TARGET_ROOT"; then
		die "could not mount $TARGET_IMAGE; use a filesystem image, not a whole-disk image with partitions"
	fi
	TARGET_MOUNTED=1
}

find_initramfs() {
	[[ -n "$INITRD_BASE" ]] && return 0
	shopt -s nullglob
	local search_root candidate
	for search_root in "$TARGET_ROOT" /; do
		for candidate in \
			"$search_root"/boot/initrd.img-* \
			"$search_root"/boot/initramfs-* \
			"$search_root"/boot/initramfs*.img; do
			if [[ -f "$candidate" ]]; then
				INITRD_BASE=$candidate
			fi
		done
		[[ -n "$INITRD_BASE" ]] && break
	done
	shopt -u nullglob
}

find_firmware_dir() {
	[[ -n "$FIRMWARE_SOURCE" ]] && return 0
	local candidate
	for candidate in \
		"$TARGET_ROOT/lib/firmware/qca" \
		"$TARGET_ROOT/usr/lib/firmware/qca" \
		/lib/firmware/qca \
		/usr/lib/firmware/qca; do
		if [[ -d "$candidate" ]]; then
			FIRMWARE_SOURCE=$candidate
			return 0
		fi
	done
}

find_wcn7850_firmware_dir() {
	[[ -n "$WCN7850_FIRMWARE_SOURCE" ]] && return 0
	local candidate
	for candidate in \
		"$TARGET_ROOT/lib/firmware/ath12k/WCN7850/hw2.0" \
		"$TARGET_ROOT/usr/lib/firmware/ath12k/WCN7850/hw2.0" \
		/lib/firmware/ath12k/WCN7850/hw2.0 \
		/usr/lib/firmware/ath12k/WCN7850/hw2.0; do
		if [[ -d "$candidate" ]]; then
			WCN7850_FIRMWARE_SOURCE=$candidate
			return 0
		fi
	done
}

find_ukify() {
	if [[ -n "$UKIFY" ]]; then
		[[ -x "$UKIFY" ]] || die "ukify executable not found: $UKIFY"
		return 0
	fi
	UKIFY=$(command -v ukify 2>/dev/null || true)
	if [[ -z "$UKIFY" ]]; then
		local candidate
		for candidate in /usr/lib/systemd/ukify /lib/systemd/ukify; do
			if [[ -x "$candidate" ]]; then
				UKIFY=$candidate
				break
			fi
		done
	fi
	[[ -n "$UKIFY" ]] || die "ukify not found; Debian provides it from systemd, not systemd-ukify"
}

find_ukistub() {
	[[ -n "$UKI_STUB" ]] && return 0
	local candidate
	for candidate in \
		"$TARGET_ROOT/usr/lib/systemd/boot/efi/linuxaa64.efi.stub" \
		"$TARGET_ROOT/lib/systemd/boot/efi/linuxaa64.efi.stub" \
		/usr/lib/systemd/boot/efi/linuxaa64.efi.stub \
		/lib/systemd/boot/efi/linuxaa64.efi.stub; do
		if [[ -f "$candidate" ]]; then
			UKI_STUB=$candidate
			return 0
		fi
	done
}

download_ukistub() {
	[[ "$DOWNLOAD_STUB" -eq 1 ]] || die "ARM64 EFI stub not found; pass --stub FILE"
	require_root_for_apt
	command -v apt >/dev/null 2>&1 || die "apt not found"
	command -v dpkg >/dev/null 2>&1 || die "dpkg not found"
	command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found"

	if ! dpkg --print-foreign-architectures | grep -qx arm64; then
		log "Enabling Debian arm64 package metadata"
		dpkg --add-architecture arm64
		apt-get update
	fi

	local download_dir="$SURFACE_WORK_DIR/dependencies/arm64-stub/deb"
	local extract_dir="$SURFACE_WORK_DIR/dependencies/arm64-stub/root"
	mkdir -p "$download_dir" "$extract_dir"
	log "Downloading ARM64 EFI stub"
	(
		cd "$download_dir"
		apt download systemd-boot-efi:arm64
	)
	local stub_deb
	stub_deb=$(find "$download_dir" -maxdepth 1 -type f \
		-name 'systemd-boot-efi_*_arm64.deb' -printf '%T@ %p\n' |
		sort -nr | head -1 | cut -d' ' -f2-)
	[[ -n "$stub_deb" && -f "$stub_deb" ]] || die "downloaded ARM64 systemd-boot package not found"
	dpkg-deb -x "$stub_deb" "$extract_dir"
	UKI_STUB="$extract_dir/usr/lib/systemd/boot/efi/linuxaa64.efi.stub"
}

validate_required_inputs() {
	[[ -f "$KERNEL_SOURCE/Makefile" ]] || die "kernel source not found: $KERNEL_SOURCE"
	[[ -f "$INITRD_BASE" ]] || die "ARM64 initramfs not found: ${INITRD_BASE:-<unset>} (supply an existing initramfs; mount $TARGET_ROOT or pass --initrd FILE)"
	[[ -d "$FIRMWARE_SOURCE" ]] || die "QCA firmware directory not found: ${FIRMWARE_SOURCE:-<unset>} (supply existing firmware; pass --firmware DIR)"
	[[ -f "$FIRMWARE_SOURCE/hmtbtfw20.tlv" ]] ||
		die "Bluetooth firmware missing: $FIRMWARE_SOURCE/hmtbtfw20.tlv"
	shopt -s nullglob
	local nv_files=("$FIRMWARE_SOURCE"/hmtnv20.*)
	shopt -u nullglob
	((${#nv_files[@]} > 0)) || die "Bluetooth calibration firmware missing: $FIRMWARE_SOURCE/hmtnv20.*"
	[[ -d "$WCN7850_FIRMWARE_SOURCE" ]] ||
		die "WCN7850 firmware directory not found: ${WCN7850_FIRMWARE_SOURCE:-<unset>} (pass --wcn7850-firmware DIR)"
	local wifi_firmware
	for wifi_firmware in amss.bin m3.bin board-2.bin; do
		[[ -f "$WCN7850_FIRMWARE_SOURCE/$wifi_firmware" ]] ||
			die "WCN7850 firmware missing: $WCN7850_FIRMWARE_SOURCE/$wifi_firmware"
	done

	command -v python3 >/dev/null 2>&1 || die "python3 not found"
	python3 - "$INITRD_BASE" <<'PY'
import gzip
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = gzip.decompress(path.read_bytes())
except Exception as exc:
    raise SystemExit(f"initramfs is not gzip-compressed: {path}: {exc}")
if not (data.startswith(b"070701") or data.startswith(b"070702")):
    raise SystemExit(f"initramfs is not a newc archive: {path}")
if b"TRAILER!!!" not in data:
    raise SystemExit(f"initramfs has no newc trailer: {path}")
PY
}

validate_inputs() {
	validate_required_inputs
	[[ -f "$UKI_STUB" ]] || die "ARM64 EFI stub not found: ${UKI_STUB:-<unset>}"
}

prepare_full_inputs() {
	find_initramfs
	find_firmware_dir
	find_wcn7850_firmware_dir
	validate_required_inputs
	find_ukify
	find_ukistub
	[[ -n "$UKI_STUB" ]] || download_ukistub
	validate_inputs
}

run_build() {
	export KERNEL_SOURCE INITRD_BASE FIRMWARE_SOURCE WCN7850_FIRMWARE_SOURCE UKI_STUB UKIFY
	export SURFACE_OUTPUT_DIR SURFACE_WORK_DIR KERNEL_APPLY_PATCHES
	export KERNEL_CONFIG="$ROOT_DIR/kernel/config/base.config"
	export KERNEL_CONFIG_FRAGMENT="$ROOT_DIR/kernel/config/desktop.config"

	log "Build configuration"
	printf 'target: %s\n' "$BUILD_TARGET"
	printf 'kernel source: %s\n' "$KERNEL_SOURCE"
	printf 'output: %s\n' "$SURFACE_OUTPUT_DIR"
	[[ "$BUILD_TARGET" == dtb || "$BUILD_TARGET" == verify ]] || {
		printf 'initramfs: %s\n' "$INITRD_BASE"
		printf 'firmware: %s\n' "$FIRMWARE_SOURCE"
		printf 'WCN7850 Wi-Fi firmware: %s\n' "$WCN7850_FIRMWARE_SOURCE"
		printf 'ukify: %s\n' "$UKIFY"
		printf 'EFI stub: %s\n' "$UKI_STUB"
	}

	cd "$ROOT_DIR"
	./build.sh "$BUILD_TARGET"
}

main() {
	parse_args "$@"
	clear_example_inputs
	trap cleanup_target_image EXIT
	if [[ "$INSTALL_DEPS" -eq 1 ]]; then
		install_dependencies
	fi
	mount_target_image

	case "$BUILD_TARGET" in
		dtb|verify)
			;;
		kernel)
			[[ -f "$KERNEL_SOURCE/Makefile" ]] || die "kernel source not found: $KERNEL_SOURCE"
			;;
		*)
			prepare_full_inputs
			;;
	esac
	run_build
}

main "$@"
