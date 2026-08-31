#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INPUT_ISO=${INPUT_ISO:-$ROOT_DIR/proxmox-ve_9.2-1-arm64.iso}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/build}
OUTPUT_ISO=${OUTPUT_ISO:-$OUTPUT_DIR/proxmox-ve_9.2-1-arm64-surface.iso}
WORK_DIR=${WORK_DIR:-$OUTPUT_DIR/.work}
KERNEL_SOURCE=${KERNEL_SOURCE:-/root/linux}
KERNEL_IMAGE=${KERNEL_IMAGE:-$WORK_DIR/kernel/Image}
DTB_FILE=${DTB_FILE:-$WORK_DIR/dtb/surface-laptop-13-current.dtb}
DTB_NAME=${DTB_NAME:-surface-laptop-13-current.dtb}
INITRD_FILE=${INITRD_FILE:-}
KERNEL_APPLY_PATCHES=${KERNEL_APPLY_PATCHES:-1}
BUILD_MISSING=1
INCLUDE_MODULES=1

DEFAULT_OUTPUT_ISO=$OUTPUT_ISO
DEFAULT_WORK_DIR=$WORK_DIR
DEFAULT_KERNEL_IMAGE=$KERNEL_IMAGE
DEFAULT_DTB_FILE=$DTB_FILE

STAGE_DIR=

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

log() {
	printf '\n==> %s\n' "$*"
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
Usage: ./build-proxmox-iso.sh [options]

Patch an existing Proxmox VE ARM64 ISO with the Surface kernel and DTB.
The patched ISO is written below ./build by default.

Options:
  --iso FILE          Input Proxmox ARM64 ISO.
  --output FILE       Output ISO (default: ./build/proxmox-ve_9.2-1-arm64-surface.iso).
  --kernel DIR        Linux source tree used when the kernel image is absent.
  --kernel-image FILE Use an existing ARM64 kernel Image instead of building one.
  --dtb FILE          Use an existing Surface DTB instead of building one.
  --dtb-name NAME     Name of the DTB inside /boot (default: current DTB name).
  --initrd FILE       Replace the ISO initrd with this archive.
  --no-initrd-modules Keep the selected initrd without adding built modules.
  --work DIR          Scratch directory (default: ./build/.work).
  --no-build           Fail if --kernel-image or --dtb is missing.
  -h, --help          Show this help.

The original Proxmox installer initrd is preserved unless --initrd is given.
The selected initrd is augmented with the built kernel modules by default. The
ISO's GRUB entries are changed to load the Surface DTB. The output kernel is
an unsigned development artifact; Secure Boot may need to be disabled or the
kernel signed before booting it.
EOF
}

parse_args() {
	while (($#)); do
		case "$1" in
			--iso)
				shift
				(($#)) || die "--iso needs a file"
				INPUT_ISO=$1
				;;
			--output)
				shift
				(($#)) || die "--output needs a file"
				OUTPUT_ISO=$1
				;;
			--kernel)
				shift
				(($#)) || die "--kernel needs a directory"
				KERNEL_SOURCE=$1
				;;
			--kernel-image)
				shift
				(($#)) || die "--kernel-image needs a file"
				KERNEL_IMAGE=$1
				;;
			--dtb)
				shift
				(($#)) || die "--dtb needs a file"
				DTB_FILE=$1
				;;
			--dtb-name)
				shift
				(($#)) || die "--dtb-name needs a name"
				DTB_NAME=$1
				;;
			--initrd)
				shift
				(($#)) || die "--initrd needs a file"
				INITRD_FILE=$1
				;;
			--no-initrd-modules)
				INCLUDE_MODULES=0
				;;
			--work)
				shift
				(($#)) || die "--work needs a directory"
				WORK_DIR=$1
				;;
			--no-build)
				BUILD_MISSING=0
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

cleanup() {
	if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
		rm -rf -- "$STAGE_DIR"
	fi
}

trap cleanup EXIT

build_missing_components() {
	local build_wrapper="$ROOT_DIR/build-debian.sh"
	[[ -x "$build_wrapper" ]] || die "build wrapper is not executable: $build_wrapper"

	if [[ ! -f "$KERNEL_IMAGE" ]]; then
		[[ "$BUILD_MISSING" -eq 1 ]] || die "kernel image not found: $KERNEL_IMAGE"
		log "Building Surface ARM64 kernel"
		KERNEL_SOURCE="$KERNEL_SOURCE" \
		KERNEL_APPLY_PATCHES="$KERNEL_APPLY_PATCHES" \
		SURFACE_OUTPUT_DIR="$OUTPUT_DIR" \
		SURFACE_WORK_DIR="$WORK_DIR" \
			"$build_wrapper" kernel
	fi

	if [[ ! -f "$DTB_FILE" ]]; then
		[[ "$BUILD_MISSING" -eq 1 ]] || die "DTB not found: $DTB_FILE"
		log "Building Surface DTB"
		KERNEL_SOURCE="$KERNEL_SOURCE" \
		KERNEL_APPLY_PATCHES="$KERNEL_APPLY_PATCHES" \
		SURFACE_OUTPUT_DIR="$OUTPUT_DIR" \
		SURFACE_WORK_DIR="$WORK_DIR" \
			"$build_wrapper" dtb
	fi
}

patch_grub_config() {
	local grub_cfg="$1"
	local dtb_path="$2"
	python3 - "$grub_cfg" "$dtb_path" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
dtb_path = sys.argv[2]
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)
result = []
patched = 0
for line in lines:
    result.append(line)
    if re.match(r"^\s*linux\s+/boot/linux26(?:\s|$)", line):
        newline = "\n" if line.endswith("\n") else ""
        indent = re.match(r"^\s*", line).group(0)
        result.append(f"{indent}devicetree /boot/{dtb_path}{newline}")
        patched += 1

if patched == 0:
    raise SystemExit(f"no Proxmox linux /boot/linux26 entries found in {path}")

path.write_text("".join(result), encoding="utf-8")
print(f"patched GRUB entries: {patched}")
PY
}

augment_initrd_with_modules() {
	local initrd="$1"
	local module_base="$WORK_DIR/modules/lib/modules"
	local module_dir release
	local base_initrd augmented manifest compressed
	shopt -s nullglob
	local module_dirs=("$module_base"/*)
	shopt -u nullglob
	(( ${#module_dirs[@]} == 1 )) || die "expected one built module release below $module_base"
	module_dir=${module_dirs[0]}
	release=$(basename "$module_dir")

	base_initrd=$(mktemp "$WORK_DIR/proxmox-initrd-base.XXXXXX.img")
	augmented=$(mktemp "$WORK_DIR/proxmox-initrd-augmented.XXXXXX.img")
	manifest=$(mktemp "$WORK_DIR/proxmox-initrd-modules.XXXXXX.manifest")
	compressed=$(mktemp "$WORK_DIR/proxmox-initrd-compressed.XXXXXX.img")
	# mktemp creates the output names; the helper intentionally opens its target
	# with O_EXCL, so remove only these task-specific temporary files first.
	rm -f -- "$base_initrd" "$augmented" "$compressed"

	log "Adding Surface kernel modules to Proxmox initrd"
	if zstd -t "$initrd" >/dev/null 2>&1; then
		zstd -q -dc "$initrd" | gzip -n -9 >"$base_initrd"
	elif gzip -t "$initrd" >/dev/null 2>&1; then
		gzip -dc "$initrd" | gzip -n -9 >"$base_initrd"
	else
		die "unsupported initrd compression: $initrd (expected zstd or gzip)"
	fi

	: >"$manifest"
	while IFS= read -r -d '' module; do
		local relative=${module#"$module_dir"/}
		printf 'lib/modules/%s/%s %s 0644\n' "$release" "$relative" "$module" >>"$manifest"
	done < <(find "$module_dir" -type f -print0 | sort -z)
	python3 "$ROOT_DIR/initramfs/scripts/augment-newc-initramfs.py" \
		"$base_initrd" "$augmented" "$manifest"
	# The augmentation helper emits gzip-compressed newc. Recompress the cpio
	# payload itself so the result has exactly one initramfs compressor.
	gzip -dc "$augmented" | zstd -q -T0 -19 -f -o "$compressed"
	mv -- "$compressed" "$initrd"
	zstd -q -dc "$initrd" | cpio -it --quiet >/dev/null
	rm -f -- "$base_initrd" "$augmented" "$manifest"
}

rebuild_iso() {
	local input_iso=$1
	local output_iso=$2
	local stage=$3
	local volume_id
	volume_id=$(xorriso -indev "$input_iso" -pvd_info 2>/dev/null |
		sed -n 's/^Volume id[[:space:]]*:[[:space:]]*//p' | head -n 1)
	[[ -n "$volume_id" ]] || volume_id=PVE

	log "Rebuilding bootable ISO"
	xorriso -as mkisofs \
		-V "$volume_id" \
		--protective-msdos-label \
		-partition_cyl_align off \
		-G "$input_iso" \
		-c /boot/boot.cat \
		-e /efi.img \
		-no-emul-boot \
		-boot-load-size 16384 \
		-o "$output_iso" \
		"$stage"
}

verify_iso() {
	local output_iso=$1
	local dtb_path=$2
	local listing
	[[ -s "$output_iso" ]] || die "output ISO was not created: $output_iso"
	listing=$(mktemp "$WORK_DIR/iso-list.XXXXXX")
	7z l -slt "$output_iso" >"$listing"
	grep -Fq "Path = boot/linux26" "$listing" || die "patched kernel is missing from output ISO"
	grep -Fq "Path = boot/initrd.img" "$listing" || die "installer initrd is missing from output ISO"
	grep -Fq "Path = boot/$dtb_path" "$listing" || die "Surface DTB is missing from output ISO"
	xorriso -indev "$output_iso" -report_el_torito as_mkisofs >/dev/null
	rm -f -- "$listing"
}

main() {
	parse_args "$@"
	need xorriso
	need 7z
	need cpio
	need python3
	need sed
	need grep
	need file

	if [[ "$WORK_DIR" == "$DEFAULT_WORK_DIR" ]]; then
		WORK_DIR="$OUTPUT_DIR/.work"
	fi
	if [[ "$KERNEL_IMAGE" == "$DEFAULT_KERNEL_IMAGE" ]]; then
		KERNEL_IMAGE="$WORK_DIR/kernel/Image"
	fi
	if [[ "$DTB_FILE" == "$DEFAULT_DTB_FILE" ]]; then
		DTB_FILE="$WORK_DIR/dtb/surface-laptop-13-current.dtb"
	fi
	if [[ "$OUTPUT_ISO" == "$DEFAULT_OUTPUT_ISO" ]]; then
		OUTPUT_ISO="$OUTPUT_DIR/proxmox-ve_9.2-1-arm64-surface.iso"
	fi

	INPUT_ISO=$(absolute_path "$INPUT_ISO")
	OUTPUT_ISO=$(absolute_path "$OUTPUT_ISO")
	OUTPUT_DIR=$(absolute_path "$OUTPUT_DIR")
	WORK_DIR=$(absolute_path "$WORK_DIR")
	KERNEL_SOURCE=$(absolute_path "$KERNEL_SOURCE")
	KERNEL_IMAGE=$(absolute_path "$KERNEL_IMAGE")
	DTB_FILE=$(absolute_path "$DTB_FILE")
	if [[ -n "$INITRD_FILE" ]]; then
		INITRD_FILE=$(absolute_path "$INITRD_FILE")
	fi

	[[ -f "$INPUT_ISO" ]] || die "input ISO not found: $INPUT_ISO"
	[[ "$INPUT_ISO" != "$OUTPUT_ISO" ]] || die "input and output ISO must be different files"
	[[ "$DTB_NAME" != */* && "$DTB_NAME" != "" ]] || die "--dtb-name must be a file name without '/': $DTB_NAME"
	if [[ -n "$INITRD_FILE" ]]; then
		[[ -f "$INITRD_FILE" ]] || die "initrd not found: $INITRD_FILE"
	fi

	mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
	build_missing_components
	[[ -f "$KERNEL_IMAGE" ]] || die "kernel image not found after build: $KERNEL_IMAGE"
	[[ -f "$DTB_FILE" ]] || die "DTB not found after build: $DTB_FILE"
	file "$KERNEL_IMAGE" | grep -Eiq 'ARM|aarch64' || die "kernel does not look like an ARM64 image: $KERNEL_IMAGE"

	STAGE_DIR=$(mktemp -d "$WORK_DIR/proxmox-iso.XXXXXX")
	log "Extracting Proxmox ISO"
	xorriso -osirrox on -indev "$INPUT_ISO" -extract / "$STAGE_DIR"
	[[ -f "$STAGE_DIR/boot/grub/grub.cfg" ]] || die "Proxmox GRUB config not found in extracted ISO"
	[[ -f "$STAGE_DIR/efi.img" ]] || die "EFI boot image not found in extracted ISO"

	log "Installing Surface kernel and DTB into ISO"
	cp --preserve=mode,timestamps "$KERNEL_IMAGE" "$STAGE_DIR/boot/linux26"
	cp --preserve=mode,timestamps "$DTB_FILE" "$STAGE_DIR/boot/$DTB_NAME"
	if [[ -n "$INITRD_FILE" ]]; then
		cp --preserve=mode,timestamps "$INITRD_FILE" "$STAGE_DIR/boot/initrd.img"
	fi
	if [[ "$INCLUDE_MODULES" -eq 1 ]]; then
		augment_initrd_with_modules "$STAGE_DIR/boot/initrd.img"
	fi
	patch_grub_config "$STAGE_DIR/boot/grub/grub.cfg" "$DTB_NAME"

	rm -f -- "$OUTPUT_ISO"
	rebuild_iso "$INPUT_ISO" "$OUTPUT_ISO" "$STAGE_DIR"
	verify_iso "$OUTPUT_ISO" "$DTB_NAME"
	printf '\nPatched ISO: %s\n' "$OUTPUT_ISO"
	file "$OUTPUT_ISO"
}

main "$@"
