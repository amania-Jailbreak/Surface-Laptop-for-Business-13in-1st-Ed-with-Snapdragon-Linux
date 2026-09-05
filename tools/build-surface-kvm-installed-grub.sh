#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT=${OUTPUT:-$ROOT_DIR/build/surface-kvm-grub-installed.efi}
GRUB_MODULE_DIR=${GRUB_MODULE_DIR:-/usr/lib/grub/arm64-efi}
ROOT_UUID=${ROOT_UUID:-f621d247-7647-4244-aad3-1fffe95afe92}
ESP_UUID=${ESP_UUID:-584B-B4D4}
KERNEL_PATH=${KERNEL_PATH:-}
DTB_PATH=${DTB_PATH:-}
INITRD_PATH=${INITRD_PATH:-}
# X1P42100 EL2 boots must leave firmware-owned clocks and power domains on.
# Without these two arguments the kernel may disable a resource still needed
# by the EL2 transition and reset before the first userspace message.
KERNEL_EXTRA_ARGS=${KERNEL_EXTRA_ARGS-"clk_ignore_unused pd_ignore_unused console=tty0 usbcore.autosuspend=-1 id_aa64mmfr0.ecv=1 loglevel=7 ignore_loglevel panic=-1"}
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
  --kernel PATH       Kernel path on the selected filesystem.
  --dtb PATH          EL2 DTB path on the selected filesystem.
  --initrd PATH       initramfs path on the selected filesystem.
  --kernel-extra-args ARGS
                      Additional kernel arguments (default: preserve X1P EL2
                      clocks/power domains, console/USB safety, ECV override,
                      verbose logging, and no automatic reboot after a panic).
  --payload-from-esp  Load kernel, DTB and initramfs from the ESP's
                      filesystem selected by --esp-uuid; default paths are
                      /EFI/BOOT/surface-kvm-linux, surface-laptop-13-el2.dtb,
                      and surface-kvm-initrd.img. Explicit paths override them.
  --payload-from-cmdpath
                      Load the payload beside the standalone GRUB image
                      without scanning disks or filesystem UUIDs. Relative
                      paths are relative to cmdpath; absolute paths use the
                      same device. Every file and load result is checked.
  --work DIR          Temporary work directory.
  -h, --help          Show this help.

Without a payload option, paths refer to /boot on --root-uuid. They do not
need to exist on the build host. A copy of the embedded configuration is
written alongside the EFI output, with a .cfg extension. Before entering
this GRUB, the outer menu must save next_entry=surface-el1-ready; errors
reboot to that entry because the Secure Launch hook is already installed.
EOF
}

resolve_payload_paths() {
	case "$PAYLOAD_MODE" in
		root)
			KERNEL_PATH=${KERNEL_PATH:-/boot/vmlinuz-7.2.0-rc5-surface-laptop-13}
			DTB_PATH=${DTB_PATH:-/boot/surface-laptop-13-el2.dtb}
			INITRD_PATH=${INITRD_PATH:-/boot/initrd.img-7.2.0-rc5-surface-laptop-13}
			;;
		esp)
			KERNEL_PATH=${KERNEL_PATH:-/EFI/BOOT/surface-kvm-linux}
			DTB_PATH=${DTB_PATH:-/EFI/BOOT/surface-laptop-13-el2.dtb}
			INITRD_PATH=${INITRD_PATH:-/EFI/BOOT/surface-kvm-initrd.img}
			;;
		cmdpath)
			KERNEL_PATH=${KERNEL_PATH:-surface-kvm-linux}
			DTB_PATH=${DTB_PATH:-surface-laptop-13-el2.dtb}
			INITRD_PATH=${INITRD_PATH:-surface-kvm-initrd.img}
			;;
	esac
	local uuid path
	for uuid in "$ROOT_UUID" "$ESP_UUID"; do
		[[ "$uuid" =~ ^[[:xdigit:]-]+$ ]] || die "invalid filesystem UUID: $uuid"
	done
	for path in "$KERNEL_PATH" "$DTB_PATH" "$INITRD_PATH"; do
		[[ "$path" =~ ^[[:alnum:]_./+-]+$ ]] || die "unsupported payload path: $path"
		[[ "$PAYLOAD_MODE" == cmdpath || "$path" == /* ]] ||
			die "payload path must be absolute in $PAYLOAD_MODE mode: $path"
	done
}

emit_payload_path() {
	local name=$1 path=$2
	if [[ "$PAYLOAD_MODE" == cmdpath && "$path" != /* ]]; then
		printf '    set %s="${cmdpath}/%s"\n' "$name" "$path"
	else
		printf '    set %s="${surface_device}%s"\n' "$name" "$path"
	fi
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
			--kernel-extra-args)
				shift; (($#)) || die "--kernel-extra-args needs a value"; KERNEL_EXTRA_ARGS=$1
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
	resolve_payload_paths
	need grub-mkstandalone
	need grub-script-check
	need file
	need sha256sum

	OUTPUT=$(absolute_path "$OUTPUT")
	GRUB_MODULE_DIR=$(absolute_path "$GRUB_MODULE_DIR")
	WORK_DIR=$(absolute_path "$WORK_DIR")
	[[ -f "$GRUB_MODULE_DIR/kernel.img" ]] ||
		die "GRUB kernel.img not found: $GRUB_MODULE_DIR/kernel.img"

	mkdir -p "$WORK_DIR" "$(dirname -- "$OUTPUT")"
	CONFIG=$(mktemp "$WORK_DIR/installed-kvm-grub.XXXXXX.cfg")
	cat >"$CONFIG" <<EOF
set timeout=0
echo 'surface-kvm: starting installed KVM GRUB (verified payload loads)'
echo "surface-kvm: prefix=\$prefix cmdpath=\$cmdpath"

function surface_kvm_boot {
    echo "surface-kvm: kernel=\$surface_kernel"
    echo "surface-kvm: EL2 DTB=\$surface_dtb"
    echo "surface-kvm: initramfs=\$surface_initrd"
    if ! [ -s "\$surface_kernel" ]; then
        echo 'surface-kvm: kernel missing or empty'
        return
    fi
    if ! [ -s "\$surface_dtb" ]; then
        echo 'surface-kvm: EL2 DTB missing or empty'
        return
    fi
    if ! [ -s "\$surface_initrd" ]; then
        echo 'surface-kvm: initramfs missing or empty'
        return
    fi
    if linux "\$surface_kernel" root=UUID=$ROOT_UUID rootfstype=ext4 rootwait rw $KERNEL_EXTRA_ARGS; then
        echo 'surface-kvm: kernel loaded'
    else
        echo 'surface-kvm: kernel load failed'
        return
    fi
    if devicetree "\$surface_dtb"; then
        echo 'surface-kvm: EL2 DTB loaded'
    else
        echo 'surface-kvm: EL2 DTB load failed'
        return
    fi
    if initrd "\$surface_initrd"; then
        echo 'surface-kvm: initramfs loaded; booting'
    else
        echo 'surface-kvm: initramfs load failed'
        return
    fi
    boot
    echo 'surface-kvm: boot returned without starting Linux'
}

EOF
	local modules='part_gpt linux fdt test reboot sleep halt'
	case "$PAYLOAD_MODE" in
	cmdpath)
		cat >>"$CONFIG" <<'EOF'
if regexp --set=1:surface_device '^(\([^)]*\))' "$cmdpath"; then
EOF
		modules+=' fat regexp'
		;;
	esp)
		cat >>"$CONFIG" <<EOF
echo 'surface-kvm: locating ESP UUID $ESP_UUID'
if search --no-floppy --fs-uuid --set=surface_fs $ESP_UUID; then
    set surface_device="(\$surface_fs)"
EOF
		modules+=' fat search search_fs_uuid'
		;;
	root)
		cat >>"$CONFIG" <<EOF
echo 'surface-kvm: locating root UUID $ROOT_UUID'
if search --no-floppy --fs-uuid --set=surface_fs $ROOT_UUID; then
    set surface_device="(\$surface_fs)"
EOF
		modules+=' ext2 search search_fs_uuid'
		;;
	esac
	emit_payload_path surface_kernel "$KERNEL_PATH" >>"$CONFIG"
	emit_payload_path surface_dtb "$DTB_PATH" >>"$CONFIG"
	emit_payload_path surface_initrd "$INITRD_PATH" >>"$CONFIG"
	cat >>"$CONFIG" <<'EOF'
    surface_kvm_boot
else
    echo 'surface-kvm: payload device unavailable'
fi

# Do not boot Ready in this EFI session: slbounce still owns ExitBootServices.
echo 'surface-kvm: failed; rebooting to the saved Ready entry in 10 seconds'
sleep 10
reboot
halt
EOF
	grub-script-check "$CONFIG"

	grub-mkstandalone \
		-d "$GRUB_MODULE_DIR" \
		-O arm64-efi \
		--disable-shim-lock \
		--modules="$modules" \
		-o "$OUTPUT" \
		"/boot/grub/grub.cfg=$CONFIG" >/dev/null
	cp -- "$CONFIG" "${OUTPUT%.efi}.cfg"

	printf 'Installed KVM GRUB: %s\n' "$OUTPUT"
	printf 'Embedded configuration: %s\n' "${OUTPUT%.efi}.cfg"
	file "$OUTPUT"
	sha256sum "$OUTPUT"
}

main "$@"
