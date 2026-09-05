#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT=${OUTPUT:-$ROOT_DIR/build/surface-kvm-efi.img}
BASE_EFI=${BASE_EFI:-$ROOT_DIR/build/surface-normal-efi.img}
TCBLAUNCH=${TCBLAUNCH:-$ROOT_DIR/attachments/tcblaunch.exe}
SLBOUNCE_EFI=${SLBOUNCE_EFI:-$ROOT_DIR/build/slbounceaa64.efi}
SLBOUNCE_SOURCE=${SLBOUNCE_SOURCE:-}
SLBOUNCE_PATCH=${SLBOUNCE_PATCH:-$ROOT_DIR/tools/slbounce-x1p42100-safe-ebs.patch}
QEBSPIL_EFI=${QEBSPIL_EFI:-}
QEBSPIL_SOURCE=${QEBSPIL_SOURCE:-}
LOAD_QEBSPIL=${LOAD_QEBSPIL:-0}
ALLOW_UNTESTED_TCB=${ALLOW_UNTESTED_TCB:-0}
FIRMWARE_TREE=${FIRMWARE_TREE:-}
EL2_DTB=${EL2_DTB:-}
SHELL_EFI=${SHELL_EFI:-}
GNUEFI_DIR=${GNUEFI_DIR:-}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/build/.work/kvm-efi}
IMAGE_SIZE=${IMAGE_SIZE:-32M}
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}

# This is the TCB build validated on the X1P42100 Surface platform.  Newer
# Windows builds have removed the error-return path used by slbounce and can
# leave the machine hung after the Secure Launch handoff.  Keep accepting an
# explicit override for other Qualcomm platforms, but never select an
# unverified TCB accidentally for this target.
KNOWN_GOOD_TCB_VERSION=10.0.26100.1742
KNOWN_GOOD_TCB_SHA256=5dfcd0253b6ee99499ab33cac221e8a9cea47f3fdf6d4e11de9a9f3c4770d03d

EXTRACT_DIR=

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
Usage: ./tools/build-surface-kvm-efi.sh [options]

Build a FAT EFI image which enters Qualcomm Secure Launch before starting
the original Proxmox ARM64 shim.  The image is separate from the normal EFI
image and is suitable for the EL2/KVM GRUB entries.

Options:
  --base-efi FILE       Original EFI image to copy (default: build/surface-normal-efi.img).
  --output FILE         Output FAT EFI image (default: build/surface-kvm-efi.img).
  --tcb FILE            Microsoft tcblaunch.exe to place at the FAT root.
  --slbounce FILE       Prebuilt slbounceaa64.efi.
  --slbounce-source DIR Build slbounce from this source tree, automatically
                        applying the X1P42100 safe ExitBootServices patch.
  --slbounce-patch FILE Override the X1P42100 slbounce patch.
  --qebspil FILE        Package an optional prebuilt qebspilaa64.efi.
  --qebspil-source DIR Build optional qebspil from this source tree when needed.
  --load-qebspil        Start qebspil before Secure Launch (experimental).
  --allow-untested-tcb  Permit a TCB other than the X1P42100 validated build.
  --firmware-tree DIR   Optional firmware tree copied below /firmware.
  --el2-dtb FILE        Copy an EL2 DTB and build a chainloadable KVM launcher.
  --shell FILE          Add an AArch64 UEFI Shell and startup.nsh KVM path.
  --work DIR            Build scratch directory.
  --size SIZE           FAT image size accepted by truncate (default: 32M).
  -h, --help            Show this help.

GNUEFI_DIR and CROSS_COMPILE may also be supplied through the environment.
EOF
}

parse_args() {
	while (($#)); do
		case "$1" in
			--base-efi)
				shift; (($#)) || die "--base-efi needs a file"; BASE_EFI=$1
				;;
			--output)
				shift; (($#)) || die "--output needs a file"; OUTPUT=$1
				;;
			--tcb)
				shift; (($#)) || die "--tcb needs a file"; TCBLAUNCH=$1
				;;
			--slbounce)
				shift; (($#)) || die "--slbounce needs a file"; SLBOUNCE_EFI=$1
				;;
			--slbounce-source)
				shift; (($#)) || die "--slbounce-source needs a directory"; SLBOUNCE_SOURCE=$1
				;;
			--slbounce-patch)
				shift; (($#)) || die "--slbounce-patch needs a file"; SLBOUNCE_PATCH=$1
				;;
			--qebspil)
				shift; (($#)) || die "--qebspil needs a file"; QEBSPIL_EFI=$1
				;;
			--qebspil-source)
				shift; (($#)) || die "--qebspil-source needs a directory"; QEBSPIL_SOURCE=$1
				;;
			--load-qebspil)
				LOAD_QEBSPIL=1
				;;
			--allow-untested-tcb)
				ALLOW_UNTESTED_TCB=1
				;;
			--firmware-tree)
				shift; (($#)) || die "--firmware-tree needs a directory"; FIRMWARE_TREE=$1
				;;
			--el2-dtb)
				shift; (($#)) || die "--el2-dtb needs a file"; EL2_DTB=$1
				;;
			--shell)
				shift; (($#)) || die "--shell needs a file"; SHELL_EFI=$1
				;;
			--work)
				shift; (($#)) || die "--work needs a directory"; WORK_DIR=$1
				;;
			--size)
				shift; (($#)) || die "--size needs a value"; IMAGE_SIZE=$1
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
	if [[ -n "$EXTRACT_DIR" && -d "$EXTRACT_DIR" ]]; then
		rm -rf -- "$EXTRACT_DIR"
	fi
}

trap cleanup EXIT

build_slbounce_if_needed() {
	if [[ -n "$SLBOUNCE_SOURCE" ]]; then
		local patched_source
		SLBOUNCE_SOURCE=$(absolute_path "$SLBOUNCE_SOURCE")
		SLBOUNCE_PATCH=$(absolute_path "$SLBOUNCE_PATCH")
		[[ -d "$SLBOUNCE_SOURCE" ]] || die "slbounce source directory not found: $SLBOUNCE_SOURCE"
		[[ -f "$SLBOUNCE_PATCH" ]] || die "slbounce X1P42100 patch not found: $SLBOUNCE_PATCH"
		patched_source="$WORK_DIR/slbounce-x1p42100"
		rm -rf -- "$patched_source"
		mkdir -p "$patched_source"
		cp -a "$SLBOUNCE_SOURCE/." "$patched_source/"

		log "Applying X1P42100 safe ExitBootServices fix to slbounce"
		if patch --dry-run --forward --batch -s -d "$patched_source" -p1 <"$SLBOUNCE_PATCH" >/dev/null 2>&1; then
			patch --forward --batch -s -d "$patched_source" -p1 <"$SLBOUNCE_PATCH"
		elif patch --dry-run --reverse --batch -s -d "$patched_source" -p1 <"$SLBOUNCE_PATCH" >/dev/null 2>&1; then
			log "slbounce source already contains the X1P42100 fix"
		else
			die "slbounce patch does not apply cleanly to $SLBOUNCE_SOURCE"
		fi

		# Never let an old build/slbounceaa64.efi silently win over an explicit
		# source tree.  That previously made source fixes appear to have no effect.
		rm -rf -- "$patched_source/out"
		log "Building X1P42100-safe slbounce"
		make -C "$patched_source" CROSS_COMPILE="$CROSS_COMPILE" ARCH=aarch64 DEBUG=1 all
		SLBOUNCE_EFI="$patched_source/out/slbounce.efi"
		if [[ -z "$GNUEFI_DIR" ]]; then
			GNUEFI_DIR="$patched_source/external/gnu-efi"
		fi
	fi
	SLBOUNCE_EFI=$(absolute_path "$SLBOUNCE_EFI")
	[[ -f "$SLBOUNCE_EFI" ]] || die "slbounce EFI binary not found: $SLBOUNCE_EFI"
	strings -el "$SLBOUNCE_EFI" | grep -Fq 'surface-x1p: safe ExitBootServices cache mode' ||
		die "slbounce is not X1P42100-safe (build it with --slbounce-source)"
}

build_qebspil_if_needed() {
	[[ -z "$QEBSPIL_SOURCE" ]] || QEBSPIL_SOURCE=$(absolute_path "$QEBSPIL_SOURCE")
	if [[ -n "$QEBSPIL_SOURCE" ]]; then
		[[ -d "$QEBSPIL_SOURCE" ]] || die "qebspil source directory not found: $QEBSPIL_SOURCE"
		if [[ -z "$QEBSPIL_EFI" || ! -f "$QEBSPIL_EFI" ]]; then
			log "Building optional qebspil"
			make -C "$QEBSPIL_SOURCE" CROSS_COMPILE="$CROSS_COMPILE" ARCH=aarch64
			QEBSPIL_EFI="$QEBSPIL_SOURCE/out/qebspilaa64.efi"
		fi
	fi
	if [[ -n "$QEBSPIL_EFI" ]]; then
		QEBSPIL_EFI=$(absolute_path "$QEBSPIL_EFI")
		[[ -f "$QEBSPIL_EFI" ]] || die "qebspil EFI binary not found: $QEBSPIL_EFI"
	fi
}

check_tcb() {
	local hash
	hash=$(sha256sum "$TCBLAUNCH" | cut -d ' ' -f1)
	if [[ "$hash" == "$KNOWN_GOOD_TCB_SHA256" ]]; then
		printf 'TCB: %s (%s, validated X1P42100 build)\n' "$TCBLAUNCH" "$KNOWN_GOOD_TCB_VERSION"
		return 0
	fi

	if [[ "$ALLOW_UNTESTED_TCB" -ne 1 ]]; then
		die "unvalidated tcblaunch.exe ($hash); use Windows 11 ARM64 24H2 build $KNOWN_GOOD_TCB_VERSION with SHA256 $KNOWN_GOOD_TCB_SHA256, or pass --allow-untested-tcb for another platform"
	fi
	printf 'WARNING: using unvalidated tcblaunch.exe (%s); X1P42100 may hang or reset\n' "$hash" >&2
}

build_loader_variant() {
	local variant=$1 loader_efi=$2 dtb_define=${3:-}
	local cc objcopy gnuefi_out crt0 loader_o loader_so
	if [[ -z "$GNUEFI_DIR" && -n "$SLBOUNCE_SOURCE" ]]; then
		GNUEFI_DIR="$SLBOUNCE_SOURCE/external/gnu-efi"
	fi
	[[ -n "$GNUEFI_DIR" ]] || die "GNUEFI_DIR is not set (or pass --slbounce-source)"
	GNUEFI_DIR=$(absolute_path "$GNUEFI_DIR")
	[[ -d "$GNUEFI_DIR" ]] || die "gnu-efi directory not found: $GNUEFI_DIR"

	cc="${CROSS_COMPILE}gcc"
	objcopy="${CROSS_COMPILE}objcopy"
	need "$cc"
	need "$objcopy"
	log "Building Surface KVM EFI launcher"
	make -C "$GNUEFI_DIR" CROSS_COMPILE="$CROSS_COMPILE" ARCH=aarch64 lib gnuefi
	gnuefi_out="$GNUEFI_DIR/aarch64"
	crt0="$gnuefi_out/gnuefi/crt0-efi-aarch64.o"
	[[ -f "$crt0" ]] || die "gnu-efi crt0 not found: $crt0"

	loader_o="$WORK_DIR/surface-kvm-loader-$variant.o"
	loader_so="$WORK_DIR/surface-kvm-loader-$variant.so"
	mkdir -p "$WORK_DIR"
	local cflags=(
		-I"$GNUEFI_DIR/inc"
		-I"$GNUEFI_DIR/inc/aarch64"
		-I"$GNUEFI_DIR/inc/protocol"
		-fpic -fshort-wchar -fno-stack-protector -ffreestanding
		-DCONFIG_aarch64 -D__MAKEWITH_GNUEFI -DGNU_EFI_USE_MS_ABI
	)
	if [[ "$LOAD_QEBSPIL" -eq 1 ]]; then
		cflags+=(-DSURFACE_KVM_LOAD_QEBSPIL)
	fi
	if [[ -n "$dtb_define" ]]; then
		cflags+=("$dtb_define")
	fi
	"$cc" "${cflags[@]}" -c "$ROOT_DIR/tools/surface-kvm-loader.c" -o "$loader_o"
	"$cc" \
		-Wl,--no-wchar-size-warning \
		-e efi_main -s -Wl,-Bsymbolic -nostdlib -shared \
		-L "$gnuefi_out/lib" -L "$gnuefi_out/gnuefi" \
		"$crt0" "$loader_o" -o "$loader_so" \
		-lefi -lgnuefi -T "$GNUEFI_DIR/gnuefi/elf_aarch64_efi.lds" \
		-Wl,--defsym=EFI_SUBSYSTEM=10
	"$objcopy" -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
		-j .rel* -j .rela* -j .reloc -j .eh_frame -O binary \
		"$loader_so" "$loader_efi"
	printf '%s\n' "$loader_efi"
}

build_loader() {
	build_loader_variant normal "$WORK_DIR/bootaa64.efi"
}

build_el2_loader() {
	build_loader_variant el2 "$WORK_DIR/surface-kvm-entry.efi" -DSURFACE_KVM_INSTALL_DTB
}

build_shell_bridge() {
	build_loader_variant shell "$WORK_DIR/surface-kvm-shell-bridge.efi" -DSURFACE_KVM_START_SHELL
}

find_base_file() {
	local name=$1
	find "$EXTRACT_DIR" -type f -iname "$name" -print -quit
}

copy_efi_file() {
	local source=$1 target=$2
	[[ -f "$source" ]] || die "EFI source file not found: $source"
	mcopy -i "$OUTPUT" -o "$source" "::$target" >/dev/null
}

copy_firmware_tree() {
	local dir relative file target
	[[ -n "$FIRMWARE_TREE" ]] || return 0
	FIRMWARE_TREE=$(absolute_path "$FIRMWARE_TREE")
	[[ -d "$FIRMWARE_TREE" ]] || die "firmware tree not found: $FIRMWARE_TREE"
	log "Copying optional firmware tree"
	# Create the parent before adding nested paths.  mmd does not create
	# missing ancestors, and the loop below intentionally starts at depth 1.
	mmd -i "$OUTPUT" ::/firmware >/dev/null
	while IFS= read -r -d '' dir; do
		relative=${dir#"$FIRMWARE_TREE"/}
		[[ "$relative" == "$dir" ]] && continue
		mmd -i "$OUTPUT" "::/firmware/$relative" >/dev/null 2>&1 || true
	done < <(find "$FIRMWARE_TREE" -mindepth 1 -type d -print0 | sort -z)
	while IFS= read -r -d '' file; do
		relative=${file#"$FIRMWARE_TREE"/}
		target="/firmware/$relative"
		copy_efi_file "$file" "$target"
	done < <(find "$FIRMWARE_TREE" -type f -print0 | sort -z)
}

emit_shell_payload_check() {
	local volume=$1 action=$2 indent= file
	local -a required=('EFI\BOOT\slbounceaa64.efi' 'tcblaunch.exe')
	[[ -z "$EL2_DTB" ]] || required+=('surface-laptop-13-el2.dtb')
	[[ "$LOAD_QEBSPIL" -ne 1 ]] || required+=('EFI\BOOT\qebspilaa64.efi')
	for file in "${required[@]}"; do
		printf '%sif exist %s\\%s then\n' "$indent" "$volume" "$file"
		indent+='  '
	done
	printf '%sif exist %s\\EFI\\BOOT\\surface-kvm-grubaa64.efi then\n' "$indent" "$volume"
	printf '%s\n' "$action"
	printf '%selse\n' "$indent"
	printf '%s  if exist %s\\EFI\\BOOT\\shimaa64.efi then\n' "$indent" "$volume"
	printf '%s    if exist %s\\EFI\\BOOT\\grubaa64.efi then\n' "$indent" "$volume"
	printf '%s\n' "$action"
	printf '%s    endif\n%s  endif\n%sendif\n' "$indent" "$indent" "$indent"
	for file in "${required[@]}"; do
		indent=${indent%  }
		printf '%sendif\n' "$indent"
	done
}

install_shell_path() {
	local startup="$WORK_DIR/surface-kvm-startup.nsh"
	local fs_index action

	[[ -n "$SHELL_EFI" ]] || return 0
	cat >"$startup" <<'EOF'
@echo -off
map -r
EOF
	# The bridge starts Shell from the selected payload volume. Prefer that
	# current filesystem; remapped FS numbers are never a persistent identity.
	emit_shell_payload_check '' 'goto surface_kvm_launch' >>"$startup"
	printf 'set -v surface_kvm_found 0\n' >>"$startup"

	# Some Surface firmware exposes many partition aliases before the ESP.
	# Generate enough explicit Shell syntax to find the payload regardless of
	# which FS alias the firmware assigned; this is more portable than relying
	# on Shell loop syntax, which differs between Shell implementations.
	for ((fs_index = 0; fs_index < 256; fs_index++)); do
		printf -v action 'if %%surface_kvm_found%% == 1 then\n  goto surface_kvm_ambiguous\nendif\nset -v surface_kvm_found 1\nset -v surface_kvm_volume fs%d:' "$fs_index"
		emit_shell_payload_check "fs${fs_index}:" "$action" >>"$startup"
	done

	cat >>"$startup" <<'EOF'

if %surface_kvm_found% == 1 then
  %surface_kvm_volume%
  goto surface_kvm_launch
endif
echo surface-kvm: EFI Shell could not find a complete KVM payload volume
pause
exit

:surface_kvm_ambiguous
echo surface-kvm: multiple complete KVM payload volumes; start the intended ESP directly
pause
exit

:surface_kvm_launch
EOF
	if [[ "$LOAD_QEBSPIL" -eq 1 ]]; then
		cat >>"$startup" <<'EOF'
echo surface-kvm: loading qebspil from EFI Shell
load \EFI\BOOT\qebspilaa64.efi
if not %lasterror% == 0 then
  goto surface_kvm_failed
endif
EOF
	fi
	cat >>"$startup" <<'EOF'
echo surface-kvm: loading slbounce from EFI Shell
load \EFI\BOOT\slbounceaa64.efi
if not %lasterror% == 0 then
  goto surface_kvm_failed
endif
if exist \EFI\BOOT\surface-kvm-grubaa64.efi then
  echo surface-kvm: starting installed KVM GRUB
  \EFI\BOOT\surface-kvm-grubaa64.efi
  goto surface_kvm_failed
endif
echo surface-kvm: starting normal Proxmox shim/GRUB
\EFI\BOOT\shimaa64.efi

:surface_kvm_failed
echo surface-kvm: boot stage returned; restart through the Ready fallback
pause
exit
EOF

	copy_efi_file "$SHELL_EFI" /EFI/BOOT/surface-kvm-shell.efi
	copy_efi_file "$startup" /startup.nsh
}

main() {
	parse_args "$@"
	need 7z
	need mformat
	need mmd
	need mcopy
	need truncate
	need find
	need sort
	need patch
	need strings
	need sha256sum

	BASE_EFI=$(absolute_path "$BASE_EFI")
	OUTPUT=$(absolute_path "$OUTPUT")
	TCBLAUNCH=$(absolute_path "$TCBLAUNCH")
	WORK_DIR=$(absolute_path "$WORK_DIR")
	if [[ -n "$EL2_DTB" ]]; then
		EL2_DTB=$(absolute_path "$EL2_DTB")
		[[ -f "$EL2_DTB" ]] || die "EL2 DTB not found: $EL2_DTB"
	fi
	if [[ -n "$SHELL_EFI" ]]; then
		SHELL_EFI=$(absolute_path "$SHELL_EFI")
		[[ -f "$SHELL_EFI" ]] || die "UEFI Shell binary not found: $SHELL_EFI"
	fi
	[[ -f "$BASE_EFI" ]] || die "base EFI image not found: $BASE_EFI"
	[[ -f "$TCBLAUNCH" ]] || die "tcblaunch.exe not found: $TCBLAUNCH"
	check_tcb

	build_slbounce_if_needed
	build_qebspil_if_needed
	case "$LOAD_QEBSPIL" in
		0) ;;
		1) [[ -n "$QEBSPIL_EFI" ]] || die "--load-qebspil requires --qebspil or --qebspil-source" ;;
		*) die "LOAD_QEBSPIL must be 0 or 1" ;;
	esac
	local loader_efi
	loader_efi=$(build_loader | tail -n 1)
	[[ -f "$loader_efi" ]] || die "EFI launcher was not built: $loader_efi"
	local el2_loader_efi=
	if [[ -n "$EL2_DTB" ]]; then
		el2_loader_efi=$(build_el2_loader | tail -n 1)
		[[ -f "$el2_loader_efi" ]] || die "EL2 EFI launcher was not built: $el2_loader_efi"
	fi
	local shell_bridge_efi=
	if [[ -n "$SHELL_EFI" ]]; then
		shell_bridge_efi=$(build_shell_bridge | tail -n 1)
		[[ -f "$shell_bridge_efi" ]] || die "EFI Shell bridge was not built: $shell_bridge_efi"
	fi

	mkdir -p "$WORK_DIR" "$(dirname -- "$OUTPUT")"
	EXTRACT_DIR=$(mktemp -d "$WORK_DIR/base-efi.XXXXXX")
	log "Extracting base EFI image"
	7z x -y -o"$EXTRACT_DIR" "$BASE_EFI" >/dev/null
	local grub cfg shim
	grub=$(find_base_file grubaa64.efi)
	cfg=$(find_base_file grub.cfg)
	shim=$(find_base_file bootaa64.efi)
	[[ -n "$grub" && -n "$cfg" && -n "$shim" ]] || die "base EFI image lacks grubaa64.efi, grub.cfg, or bootaa64.efi"

	log "Creating $IMAGE_SIZE FAT EFI image"
	rm -f -- "$OUTPUT"
	truncate -s "$IMAGE_SIZE" "$OUTPUT"
	# Let mtools choose FAT12/FAT16 for small EFI images.  Forcing FAT32 on
	# a 32 MiB image fails because FAT32 requires a larger cluster count.
	MTOOLS_SKIP_CHECK=1 mformat -i "$OUTPUT" -v SURFACEKVM :: >/dev/null
	mmd -i "$OUTPUT" ::/EFI >/dev/null
	mmd -i "$OUTPUT" ::/EFI/BOOT >/dev/null
	if [[ -n "$EL2_DTB" ]]; then
		mmd -i "$OUTPUT" ::/EFI/PROXMOX >/dev/null
	fi
	copy_efi_file "$grub" /EFI/BOOT/grubaa64.efi
	copy_efi_file "$cfg" /EFI/BOOT/grub.cfg
	copy_efi_file "$shim" /EFI/BOOT/shimaa64.efi
	if [[ -n "$EL2_DTB" ]]; then
		# When a Shell payload is present, make the firmware's normal FAT boot
		# path enter the bridge first.  Starting the Shell from an ISO9660 file
		# gives it only BLK handles on some firmware, so the GRUB menu entry is
		# not a valid first stage for this workaround.
		if [[ -n "$shell_bridge_efi" ]]; then
			copy_efi_file "$shell_bridge_efi" /EFI/BOOT/BOOTAA64.EFI
		else
			# Without the Shell workaround, keep the normal shim as the default
			# firmware path and use the explicit KVM launcher entry instead.
			copy_efi_file "$shim" /EFI/BOOT/BOOTAA64.EFI
		fi
	else
		copy_efi_file "$loader_efi" /EFI/BOOT/BOOTAA64.EFI
	fi
	copy_efi_file "$SLBOUNCE_EFI" /EFI/BOOT/slbounceaa64.efi
	if [[ -n "$EL2_DTB" ]]; then
		copy_efi_file "$el2_loader_efi" /EFI/BOOT/surface-kvm-entry.efi
		copy_efi_file "$el2_loader_efi" /EFI/PROXMOX/surface-kvm-entry.efi
		# The installed standalone GRUB variant may use $cmdpath and load
		# the payload next to itself.  Keep the EL2 DTB there as well as at
		# the FAT root used by the launcher and qebspil.
		copy_efi_file "$EL2_DTB" /surface-laptop-13-el2.dtb
		copy_efi_file "$EL2_DTB" /EFI/BOOT/surface-laptop-13-el2.dtb
	fi
	copy_efi_file "$TCBLAUNCH" /tcblaunch.exe
	if [[ -n "$QEBSPIL_EFI" ]]; then
		copy_efi_file "$QEBSPIL_EFI" /EFI/BOOT/qebspilaa64.efi
	fi
	copy_firmware_tree
	install_shell_path
	if [[ -n "$shell_bridge_efi" ]]; then
		copy_efi_file "$shell_bridge_efi" /EFI/BOOT/surface-kvm-shell-bridge.efi
	fi

	printf '\nSurface KVM EFI image: %s\n' "$OUTPUT"
	file "$OUTPUT"
	sha256sum "$OUTPUT"
	7z l "$OUTPUT" | grep -E 'tcblaunch|BOOTAA64|surface-kvm-entry|surface-kvm-shell|startup.nsh|surface-laptop-13-el2|slbounce|qebspil|grub|shim|firmware' || true
}

main "$@"
