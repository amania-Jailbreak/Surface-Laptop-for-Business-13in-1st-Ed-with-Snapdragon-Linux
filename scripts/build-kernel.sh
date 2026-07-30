#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 /path/to/linux [output-directory]" >&2
    exit 2
fi

kernel_dir="$(cd "$1" && pwd)"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${2:-$repo_dir/out}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
jobs="${JOBS:-$(nproc)}"
dt_name="x1p42100-microsoft-surface-laptop-13"
dt_dir="$kernel_dir/arch/arm64/boot/dts/qcom"

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

install -m 0644 \
    "$repo_dir/kernel/arch/arm64/boot/dts/qcom/$dt_name.dts" \
    "$dt_dir/$dt_name.dts"

if ! grep -qF "$dt_name.dtb" "$dt_dir/Makefile"; then
    printf 'dtb-$(CONFIG_ARCH_QCOM) += %s.dtb\n' "$dt_name" \
        >> "$dt_dir/Makefile"
fi

cd "$kernel_dir"

make ARCH=arm64 CROSS_COMPILE="$cross_compile" defconfig
scripts/kconfig/merge_config.sh -m .config "$repo_dir/configs/kernel.fragment"
make ARCH=arm64 CROSS_COMPILE="$cross_compile" olddefconfig

make -j"$jobs" \
    ARCH=arm64 \
    CROSS_COMPILE="$cross_compile" \
    KCFLAGS=-pipe \
    Image "qcom/$dt_name.dtb"

install -m 0644 arch/arm64/boot/Image "$output_dir/Image"
install -m 0644 "$dt_dir/$dt_name.dtb" \
    "$output_dir/surface-laptop-13.dtb"

echo "Built:"
ls -lh "$output_dir/Image" "$output_dir/surface-laptop-13.dtb"
