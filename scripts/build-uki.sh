#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "Usage: $0 UKIFY LINUXAA64_STUB IMAGE DTB INITRAMFS OUTPUT_EFI" >&2
    exit 2
fi

UKIFY=$1
STUB=$2
IMAGE=$3
DTB=$4
INITRAMFS=$5
OUTPUT=$6

for input in "$UKIFY" "$STUB" "$IMAGE" "$DTB" "$INITRAMFS"; do
    if [[ ! -e "$input" ]]; then
        echo "Missing input: $input" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "$OUTPUT")"

CMDLINE=${CMDLINE:-"console=tty0 keep_bootcon loglevel=7 log_buf_len=8M rdinit=/init root=LABEL=UBUNTU_ROOT rootfstype=ext4 rootwait rw sbsa_gwdt.timeout=1800 panic=0 clk_ignore_unused pd_ignore_unused regulator_ignore_unused"}
KERNEL_VERSION=${KERNEL_VERSION:-}

args=(
    build
    "--stub=$STUB"
    "--linux=$IMAGE"
    "--initrd=$INITRAMFS"
    "--devicetree=$DTB"
    "--cmdline=$CMDLINE"
    "--os-release=ID=ubuntu"
    "--output=$OUTPUT"
)

if [[ -n "$KERNEL_VERSION" ]]; then
    args+=("--uname=$KERNEL_VERSION")
fi

"$UKIFY" "${args[@]}"

file "$OUTPUT"
