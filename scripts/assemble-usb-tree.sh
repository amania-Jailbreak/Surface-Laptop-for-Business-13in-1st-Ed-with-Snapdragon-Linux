#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 Image board.dtb initramfs.cpio.gz BOOTAA64.EFI output-directory" >&2
    exit 2
fi

output="$5"
mkdir -p "$output/EFI/BOOT" "$output/boot"

install -m 0644 "$1" "$output/boot/Image"
install -m 0644 "$2" "$output/boot/surface-laptop-13.dtb"
install -m 0644 "$3" "$output/boot/initramfs.cpio.gz"
install -m 0644 "$4" "$output/EFI/BOOT/BOOTAA64.EFI"

echo "USB tree:"
find "$output" -type f -print
