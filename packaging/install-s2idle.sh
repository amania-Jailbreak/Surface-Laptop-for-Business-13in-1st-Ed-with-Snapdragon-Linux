#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=0
ESP=${ESP:-/boot/efi}
UKI=

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
	cat >&2 <<'EOF'
Usage: install-s2idle.sh [--dry-run] [--esp PATH] UKI

Installs the separate s2idle test UKI and a systemd-boot entry. Existing
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
			[[ -z "$UKI" ]] || usage
			UKI=$1
			shift
			;;
	esac
done

[[ -n "$UKI" ]] || usage
[[ "$UKI" = /* ]] || UKI="$(pwd)/$UKI"
[[ -s "$UKI" ]] || die "UKI not found: $UKI"
[[ "$ESP" = /* ]] || die "ESP path must be absolute: $ESP"
[[ -d "$ESP/loader/entries" ]] || die "systemd-boot entry directory is missing: $ESP/loader/entries"
if command -v findmnt >/dev/null 2>&1 && ! findmnt -rn --mountpoint "$ESP" >/dev/null; then
	die "ESP is not mounted: $ESP"
fi

efi_dest="$ESP/EFI/Linux/surface-laptop-13-s2idle.efi"
entry_dest="$ESP/loader/entries/surface-laptop-13-s2idle.conf"
[[ ! -e "$efi_dest" ]] || die "refusing to overwrite existing UKI: $efi_dest"
[[ ! -e "$entry_dest" ]] || die "refusing to overwrite existing entry: $entry_dest"

required_bytes=$(stat -c '%s' "$UKI")
available_bytes=$(df -PB1 "$ESP" | awk 'NR==2 {print $4}')
[[ "$available_bytes" =~ ^[0-9]+$ ]] || die "cannot determine free ESP space"
(( available_bytes > required_bytes + 67108864 )) || die "not enough free ESP space (UKI plus 64 MiB safety margin required)"

printf 'UKI:   %s\nEntry: %s\n' "$efi_dest" "$entry_dest"
if (( DRY_RUN )); then
	printf '%s\n' 'Dry run: no files were changed.'
	exit 0
fi
[[ $EUID -eq 0 ]] || die 'run the installer as root'

install -D -o root -g root -m 0755 "$UKI" "$efi_dest"
install -D -o root -g root -m 0644 /dev/stdin "$entry_dest" <<'EOF'
title Surface Laptop for Business 13 (s2idle sleep test)
efi /EFI/Linux/surface-laptop-13-s2idle.efi
EOF
sync
printf '%s\n' 'Installed a separate s2idle systemd-boot entry. Existing current/fallback UKIs were not modified.'
