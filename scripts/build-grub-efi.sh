#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/grub/arm64-efi output/BOOTAA64.EFI" >&2
    exit 2
fi

module_dir="$(cd "$1" && pwd)"
mkdir -p "$(dirname "$2")"
output_dir="$(cd "$(dirname "$2")" && pwd)"
output="$output_dir/$(basename "$2")"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"

grub-mkstandalone \
    --format=arm64-efi \
    --directory="$module_dir" \
    --output="$output" \
    --modules="part_gpt part_msdos fat normal linux fdt search search_fs_file echo configfile all_video efi_gop" \
    "boot/grub/grub.cfg=$repo_dir/boot/grub.cfg"

file "$output"
