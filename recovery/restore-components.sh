#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
current="$root/SURFACE-CURRENT"

printf 'Recovery component set: %s\n' "$current"
for file in \
	"$current/kernel/Image" \
	"$current/dtb/surface-laptop-13-current.dtb" \
	"$current/dtb/surface-laptop-13-bluetooth.dtb" \
	"$current/initramfs/surface-laptop-13-current.img" \
	"$current/uki/surface-laptop-13-current.efi"; do
	if [[ -f "$file" ]]; then
		sha256sum "$file"
	else
		printf 'missing: %s\n' "$file" >&2
	fi
done
printf '\nNo ESP or block-device operation was performed.\n'
