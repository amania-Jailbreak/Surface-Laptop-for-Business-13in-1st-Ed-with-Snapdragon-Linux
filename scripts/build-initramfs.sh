#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 /path/to/busybox /path/to/linux output.cpio.gz" >&2
    exit 2
fi

busybox_dir="$(cd "$1" && pwd)"
kernel_dir="$(cd "$2" && pwd)"
output_parent="$(dirname "$3")"
mkdir -p "$output_parent"
output="$(cd "$output_parent" && pwd)/$(basename "$3")"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
work_dir="$(mktemp -d)"
rootfs="$work_dir/rootfs"

cleanup()
{
    rm -rf "$work_dir"
}
trap cleanup EXIT

# Some BusyBox releases install applet links before their parent directory
# target has run. Pre-create the complete directory skeleton to keep install
# deterministic even when MAKEFLAGS enables parallel builds.
mkdir -p \
    "$rootfs"/{bin,sbin,dev,proc,sys,run,tmp,mnt} \
    "$rootfs"/usr/{bin,sbin} \
    "$rootfs"/sys/kernel/debug

make -C "$busybox_dir" \
    ARCH=arm64 \
    CROSS_COMPILE="$cross_compile" \
    CONFIG_PREFIX="$rootfs" \
    install

install -m 0755 "$repo_dir/initramfs/init" "$rootfs/init"
install -m 0755 "$repo_dir/initramfs/gpu-diag.sh" "$rootfs/gpu-diag.sh"

make -s -C "$kernel_dir" \
    ARCH=arm64 \
    INSTALL_HDR_PATH="$work_dir/kernel-headers" \
    headers_install

"${cross_compile}gcc" \
    -O2 -static \
    -I"$work_dir/kernel-headers/include" \
    "$repo_dir/initramfs/gpu-smoke.c" \
    -o "$rootfs/gpu-smoke"

if [[ -n "${FIRMWARE_ROOT:-}" ]]; then
    firmware_dest="$rootfs/lib/firmware"
    mkdir -p "$firmware_dest"
    cp -a "$FIRMWARE_ROOT"/. "$firmware_dest"/
else
    echo "FIRMWARE_ROOT is unset; building without GPU firmware." >&2
fi

(
    cd "$kernel_dir"
    ./usr/gen_initramfs.sh \
        -u squash \
        -g squash \
        "$rootfs" \
        "$repo_dir/initramfs/devnodes.list"
) | gzip -9 > "$output"

echo "Built $output"
ls -lh "$output"
