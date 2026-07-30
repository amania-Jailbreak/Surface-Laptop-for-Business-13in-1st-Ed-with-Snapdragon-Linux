#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 ubuntu-26.04-desktop-arm64.iso output/ubuntu-rootfs.tar" >&2
    exit 2
fi

iso="$1"
output="$2"

command -v 7z >/dev/null || {
    echo "7z is required to read the ISO" >&2
    exit 1
}
command -v unsquashfs >/dev/null || {
    echo "unsquashfs is required; install squashfs-tools" >&2
    exit 1
}
command -v fakeroot >/dev/null || {
    echo "fakeroot is required to preserve root ownership in the tar archive" >&2
    exit 1
}
command -v rsync >/dev/null || {
    echo "rsync is required to merge the ISO layers" >&2
    exit 1
}

iso="$(cd "$(dirname "$iso")" && pwd)/$(basename "$iso")"
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_base="${WORK_DIR:-$repo_dir/.work}"
mkdir -p "$work_base"
work_dir="$(mktemp -d "$work_base/ubuntu-rootfs.XXXXXX")"

cleanup()
{
    rm -rf "$work_dir"
}
trap cleanup EXIT

echo "Extracting Ubuntu casper layers from $iso"
for layer in minimal minimal.standard minimal.standard.live; do
    7z x -so "$iso" "casper/$layer.squashfs" > "$work_dir/$layer.squashfs"
done

echo "Unpacking Ubuntu rootfs and creating $output"
fakeroot bash -c '
    set -e
    unsquashfs -quiet -d "$1/rootfs" "$1/minimal.squashfs"
    unsquashfs -quiet -d "$1/standard" "$1/minimal.standard.squashfs"
    unsquashfs -quiet -d "$1/live" "$1/minimal.standard.live.squashfs"

    overlay_merge()
    {
        src="$1"
        dst="$2"

        # SquashFS layers can replace a file/symlink with a directory (or
        # vice versa). Remove only those type-conflicting paths before rsync.
        (cd "$src" && find . -mindepth 1 -type d -print0) |
        while IFS= read -r -d "" path; do
            rel="${path#./}"
            target="$dst/$rel"
            if { [ -e "$target" ] || [ -L "$target" ]; } &&
               { [ ! -d "$target" ] || [ -L "$target" ]; }; then
                rm -rf "$target"
            fi
        done

        (cd "$src" && find . -mindepth 1 ! -type d -print0) |
        while IFS= read -r -d "" path; do
            rel="${path#./}"
            target="$dst/$rel"
            if [ -d "$target" ] && [ ! -L "$target" ]; then
                rm -rf "$target"
            fi
        done

        rsync -aH --numeric-ids "$src/." "$dst/"
    }

    overlay_merge "$1/standard" "$1/rootfs"
    overlay_merge "$1/live" "$1/rootfs"
    tar --numeric-owner --xattrs --acls -cpf "$2" -C "$1/rootfs" .
' sh "$work_dir" "$output"

echo "Created $output"
ls -lh "$output"
