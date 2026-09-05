#!/usr/bin/env bash
# Apply only the EL2 overlay to the DTB actually used by the installed Ready entry.
set -Eeuo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# == 2 ]] || { echo "Usage: $0 READY.dtb OUTPUT.dtb" >&2; exit 1; }
input=$1 output=$2
mkdir -p "$(dirname -- "$output")"
work=$(mktemp -d "$(dirname -- "$output")/el2-dtb.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
cp -- "$input" "$work/ready.dtb"
# Older installed DTBs lack these upstream labels. Add only symbol metadata;
# fdtoverlay then resolves the existing nodes and phandles in this exact DTB.
while read -r label path; do
    fdtget -p "$work/ready.dtb" "$path" >/dev/null
    fdtput -p -t s "$work/ready.dtb" /__symbols__ "$label" "$path"
done <<'NODES'
gpu_zap_shader /soc@0/gpu@3d00000/zap-shader
iris /soc@0/video-codec@aa00000
pcie_smmu /soc@0/iommu@15400000
pcie3 /soc@0/pcie@1bd0000
pcie6a /soc@0/pci@1bf8000
pcie5 /soc@0/pci@1c00000
pcie4 /soc@0/pci@1c08000
gic_its /soc@0/interrupt-controller@17000000/msi-controller@17040000
remoteproc_adsp /soc@0/remoteproc@6800000
remoteproc_cdsp /soc@0/remoteproc@32300000
apps_smmu /soc@0/iommu@15000000
apss_watchdog /soc@0/watchdog@17410000
sbsa_watchdog /soc@0/watchdog@1c840000
NODES
# An overlay target needs a phandle as well as a symbol. Preserve existing
# values, assigning unused values only to nodes that did not have one.
python3 - "$work/ready.dtb" <<'PY'
import re, subprocess, sys
dtb = sys.argv[1]
source = subprocess.run(['dtc', '-I', 'dtb', '-O', 'dts', dtb],
                        check=True, capture_output=True, text=True).stdout
next_id = max([0] + [int(x, 16) for x in re.findall(r'\bphandle = <0x([0-9a-f]+)>;', source)]) + 1
labels = subprocess.check_output(['fdtget', '-p', dtb, '/__symbols__'], text=True).split()
for label in labels:
    path = subprocess.check_output(['fdtget', dtb, '/__symbols__', label], text=True).strip()
    result = subprocess.run(['fdtget', dtb, path, 'phandle'], capture_output=True)
    if result.returncode:
        subprocess.run(['fdtput', '-t', 'x', dtb, path, 'phandle', f'{next_id:x}'], check=True)
        next_id += 1
PY
dtc -@ -I dts -O dtb -o "$work/el2.dtbo" "$ROOT_DIR/device-tree/overlays/x1e-el2.dtso"
fdtoverlay -i "$work/ready.dtb" -o "$output" "$work/el2.dtbo"
[[ $(fdtget "$output" /chosen dtbhack-el2-overlay) == x1p42100-el2 ]]
[[ $(fdtget "$output" /soc@0/gpu@3d00000/zap-shader status) == disabled ]]
[[ $(fdtget "$output" /soc@0/watchdog@1c840000 status) == disabled ]]
sha256sum "$input" "$output"
