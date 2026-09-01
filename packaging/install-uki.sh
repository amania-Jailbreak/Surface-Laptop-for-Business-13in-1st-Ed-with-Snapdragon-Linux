#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=0
ESP=${ESP:-/boot/efi}
BUNDLE=

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
	cat >&2 <<'EOF'
Usage: install-uki.sh [--dry-run] [--esp PATH] COMPONENT-DIR

Installs a new, versioned Surface UKI and systemd-boot entry. Existing
current.efi and fallback.efi are never modified.
EOF
	exit 2
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--esp)
			[[ $# -ge 2 ]] || usage
			ESP=$2
			shift 2
			;;
		-*) usage ;;
		*)
			[[ -z "$BUNDLE" ]] || usage
			BUNDLE=$1
			shift
			;;
	esac
	done
[[ -n "$BUNDLE" ]] || usage
[[ "$BUNDLE" = /* ]] || BUNDLE="$ROOT_DIR/$BUNDLE"
[[ "$ESP" = /* ]] || die "ESP path must be absolute: $ESP"
[[ -d "$BUNDLE" ]] || die "component set not found: $BUNDLE"
[[ -d "$ESP" ]] || die "ESP path does not exist: $ESP"
[[ -d "$ESP/loader/entries" ]] || die "systemd-boot entry directory is missing: $ESP/loader/entries"
[[ -f "$BUNDLE/kernel/release" ]] || die "kernel release is missing"

if command -v findmnt >/dev/null 2>&1 && ! findmnt -rn --mountpoint "$ESP" >/dev/null; then
	die "ESP is not mounted: $ESP"
fi

release=$(tr -d '[:space:]' <"$BUNDLE/kernel/release")
case "$release" in
	''|*[!A-Za-z0-9._+-]*) die "unsafe kernel release: $release" ;;
esac
uki="$BUNDLE/uki/surface-laptop-13-current.efi"
[[ -s "$uki" ]] || die "current UKI is missing: $uki"

efi_name="surface-laptop-13-$release.efi"
efi_dest="$ESP/EFI/Linux/$efi_name"
entry_dest="$ESP/loader/entries/surface-laptop-13-$release.conf"
case "$efi_dest:$entry_dest" in
	*current.efi*|*fallback.efi*) die "refusing a current/fallback destination" ;;
esac
[[ ! -e "$efi_dest" ]] || die "refusing to overwrite existing UKI: $efi_dest"
[[ ! -e "$entry_dest" ]] || die "refusing to overwrite existing entry: $entry_dest"

required_bytes=$(stat -c '%s' "$uki")
available_bytes=$(df -PB1 "$ESP" | awk 'NR==2 {print $4}')
[[ "$available_bytes" =~ ^[0-9]+$ ]] || die "cannot determine free ESP space"
(( available_bytes > required_bytes + 67108864 )) || die "not enough free ESP space (UKI plus 64 MiB safety margin required)"

printf 'UKI:   %s\nEntry: %s\n' "$efi_dest" "$entry_dest"
if (( DRY_RUN )); then
	printf '%s\n' 'Dry run: no files were changed.'
	exit 0
fi
[[ $EUID -eq 0 ]] || die 'run the installer as root'

install -D -o root -g root -m 0755 "$uki" "$efi_dest"
install -D -o root -g root -m 0644 /dev/stdin "$entry_dest" <<EOF
title Surface Laptop 13 Linux ($release)
efi /EFI/Linux/$efi_name
EOF
sync
printf '%s\n' 'Installed a separate systemd-boot entry. Existing current/fallback UKIs were not modified.'
