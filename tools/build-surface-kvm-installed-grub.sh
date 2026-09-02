#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT=${OUTPUT:-$ROOT_DIR/build/surface-kvm-grub-installed.efi}
GRUB_MODULE_DIR=${GRUB_MODULE_DIR:-/usr/lib/grub/arm64-efi}
ROOT_UUID=${ROOT_UUID:-f621d247-7647-4244-aad3-1fffe95afe92}
ESP_UUID=${ESP_UUID:-584B-B4D4}
KERNEL_PATH=${KERNEL_PATH:-/boot/vmlinuz-7.2.0-rc5-surface-laptop-13-kvm}
DTB_PATH=${DTB_PATH:-/boot/surface-laptop-13-el2.dtb}
INITRD_PATH=${INITRD_PATH:-/boot/initrd.img-7.2.0-rc5-surface-laptop-13-kvm}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/build/.work/installed-kvm-grub}
PAYLOAD_MODE=root

CONFIG=

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

absolute_path() {
	local path=$1
	if [[ "$path" == /* ]]; then
		printf '%s\n' "$path"
	else
		printf '%s/%s\n' "$ROOT_DIR" "$path"
	fi
}

usage() {
	cat <<'EOF'
Usage: ./tools/build-surface-kvm-installed-grub.sh [options]

Build a standalone GRUB which directly boots the installed Surface EL2/KVM
kernel after the Secure Launch hook has been installed.

Options:
  --output FILE       Output EFI application (default: build/surface-kvm-grub-installed.efi).
  --grub-dir DIR      ARM64 GRUB module directory.
  --root-uuid UUID    Installed root filesystem UUID.
  --esp-uuid UUID     EFI system partition UUID.
  --kernel PATH       Kernel path as seen by GRUB.
  --dtb PATH          EL2 DTB path as seen by GRUB.
  --initrd PATH       initramfs path as seen by GRUB.
  --payload-from-esp  Load kernel, DTB and initramfs from the ESP's
                      /EFI/BOOT directory selected by --esp-uuid.
  --payload-from-cmdpath
                      Load the payload beside the standalone GRUB image
                      without scanning disks or filesystem UUIDs.
  --work DIR          Temporary work directory.
  -h, --help          Show this help.

The paths are embedded in the GRUB configuration and normally begin with
/boot; they do not need to exist on the build host.
EOF
}

parse_args() {
	while (($#)); do
		case "$1" in
			--output)
				shift; (($#)) || die "--output needs a file"; OUTPUT=$1
				;;
			--grub-dir)
				shift; (($#)) || die "--grub-dir needs a directory"; GRUB_MODULE_DIR=$1
				;;
			--root-uuid)
				shift; (($#)) || die "--root-uuid needs a UUID"; ROOT_UUID=$1
				;;
			--esp-uuid)
				shift; (($#)) || die "--esp-uuid needs a UUID"; ESP_UUID=$1
				;;
			--kernel)
				shift; (($#)) || die "--kernel needs a path"; KERNEL_PATH=$1
				;;
			--dtb)
				shift; (($#)) || die "--dtb needs a path"; DTB_PATH=$1
				;;
			--initrd)
				shift; (($#)) || die "--initrd needs a path"; INITRD_PATH=$1
				;;
			--work)
				shift; (($#)) || die "--work needs a directory"; WORK_DIR=$1
				;;
			--payload-from-esp)
				PAYLOAD_MODE=esp
				;;
			--payload-from-cmdpath)
				PAYLOAD_MODE=cmdpath
				;;
			-h|--help)
				usage
				exit 0
				;;
			*) die "unknown argument: $1 (use --help)" ;;
		esac
		shift
	done
}

cleanup() {
	if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
		rm -f -- "$CONFIG"
	fi
}

trap cleanup EXIT

main() {
	parse_args "$@"
	need grub-mkstandalone
	need file
	need sha256sum

	OUTPUT=$(absolute_path "$OUTPUT")
	GRUB_MODULE_DIR=$(absolute_path "$GRUB_MODULE_DIR")
	WORK_DIR=$(absolute_path "$WORK_DIR")
	[[ -f "$GRUB_MODULE_DIR/kernel.img" ]] ||
		die "GRUB kernel.img not found: $GRUB_MODULE_DIR/kernel.img"

	mkdir -p "$WORK_DIR" "$(dirname -- "$OUTPUT")"
	CONFIG=$(mktemp "$WORK_DIR/installed-kvm-grub.XXXXXX.cfg")
	case "$PAYLOAD_MODE" in
	cmdpath)
		cat >"$CONFIG" <<EOF
set timeout=0
echo 'surface-kvm: starting installed KVM GRUB'
echo "surface-kvm: cmdpath=\$cmdpath"
echo 'surface-kvm: loading kernel'
linux \$cmdpath/surface-kvm-linux root=UUID=$ROOT_UUID rootfstype=ext4 rootwait rw id_aa64mmfr0.ecv=1
echo 'surface-kvm: kernel loaded'
echo 'surface-kvm: loading EL2 DTB'
devicetree \$cmdpath/surface-laptop-13-el2.dtb
echo 'surface-kvm: EL2 DTB loaded'
echo 'surface-kvm: loading initramfs'
initrd \$cmdpath/surface-kvm-initrd.img
echo 'surface-kvm: initramfs loaded; booting'
boot
EOF
		modules='part_gpt fat linux fdt'
		;;
	esp)
		cat >"$CONFIG" <<EOF
set timeout=0
echo 'surface-kvm: starting installed KVM GRUB'
echo 'surface-kvm: selecting installed ESP'
insmod part_gpt
insmod fat
insmod search_fs_uuid
search --no-floppy --fs-uuid --set=root $ESP_UUID
insmod linux
insmod fdt
linux /EFI/BOOT/surface-kvm-linux root=UUID=$ROOT_UUID rootfstype=ext4 rootwait rw id_aa64mmfr0.ecv=1
devicetree /EFI/BOOT/surface-laptop-13-el2.dtb
initrd /EFI/BOOT/surface-kvm-initrd.img
boot
EOF
		modules='part_gpt fat search_fs_uuid linux fdt'
		;;
	root)
		cat >"$CONFIG" <<EOF
set timeout=0
insmod part_gpt
insmod ext2
insmod search_fs_uuid
insmod linux
insmod fdt
search --no-floppy --fs-uuid --set=root $ROOT_UUID
linux $KERNEL_PATH root=UUID=$ROOT_UUID rootfstype=ext4 rootwait rw id_aa64mmfr0.ecv=1
devicetree $DTB_PATH
initrd $INITRD_PATH
boot
EOF
		modules='part_gpt ext2 search_fs_uuid linux fdt'
		;;
	esac

	grub-mkstandalone \
		-d "$GRUB_MODULE_DIR" \
		-O arm64-efi \
		--disable-shim-lock \
		--modules="$modules" \
		-o "$OUTPUT" \
		"/boot/grub/grub.cfg=$CONFIG" >/dev/null

	printf 'Installed KVM GRUB: %s\n' "$OUTPUT"
	file "$OUTPUT"
	sha256sum "$OUTPUT"
}

main "$@"
