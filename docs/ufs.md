# Internal UFS storage

The Surface board description already contained the Qualcomm UFS PHY at
`0x01d80000` and the UFS host controller at `0x01d84000`. Both nodes had been
left disabled in the public Type-C DTS.

The hardware-tested `proxmox` branch enabled exactly those two existing nodes;
it did not invent a different UFS register map or copy a DT from another
Snapdragon device. The public DTS now carries the same change in its base
tree, so the normal, Bluetooth, touchscreen, and fingerprint-derived DTBs all
retain the UFS description.

## Kernel and initramfs requirements

UFS storage is exposed through the SCSI UFS host stack. It is not enabled by
`CONFIG_UFS_FS`, which is a separate Unix File System filesystem option. The
relevant hardware symbols are:

```text
CONFIG_SCSI_UFSHCD
CONFIG_SCSI_UFSHCD_PLATFORM
CONFIG_SCSI_UFS_QCOM
CONFIG_PHY_QCOM_QMP_UFS
```

The default hardware configuration keeps the generic host pieces built in and
allows the Qualcomm host and QMP PHY to be modules, matching the tested branch.
`build.sh initramfs` explicitly seeds these module paths:

```text
kernel/drivers/phy/qualcomm/phy-qcom-qmp-ufs.ko
kernel/drivers/ufs/core/ufshcd-core.ko
kernel/drivers/ufs/host/ufshcd-pltfrm.ko
kernel/drivers/ufs/host/ufs-qcom.ko
```

The module selector follows the new kernel's `modules.dep`, so dependencies
such as Qualcomm ICE are taken from the same build. The early hardware hook
requests the matching module names before root discovery. If a distribution
builds one of these components in, the initramfs verifier accepts the entry in
`modules.builtin` instead.

## Build and test

Build the public components with the same external inputs used for the other
Surface features:

```sh
./build.sh dtb
./build.sh kernel
./build.sh initramfs
./build.sh uki
./build.sh verify
```

Before booting, verify the generated DTB and matching kernel configuration:

```sh
fdtget /tmp/surface-laptop-13-build/dtb/surface-laptop-13-current.dtb \
  /soc@0/phy@1d80000 status
fdtget /tmp/surface-laptop-13-build/dtb/surface-laptop-13-current.dtb \
  /soc@0/ufshc@1d84000 status
grep -E '^CONFIG_(SCSI_UFSHCD|SCSI_UFSHCD_PLATFORM|SCSI_UFS_QCOM|PHY_QCOM_QMP_UFS)=' \
  /tmp/surface-laptop-13-build/kernel/config
```

On the target, use the existing recovery entry first and install a new UKI as
a separate systemd-boot entry. Do not replace `current.efi` or `fallback.efi`
for the first UFS test. With the machine booted, compare the storage list and
kernel log before and after choosing the UFS-enabled entry:

```sh
lsblk -o NAME,TRAN,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
dmesg | grep -Ei 'ufs|ufshc|qmp.*ufs|scsi|sd[a-z]'
find /sys/class/scsi_host -maxdepth 1 -type l -printf '%f\n'
```

If the root filesystem is moved from USB-C to internal UFS, the deployment
must use the internal filesystem's own UUID or label in the OS-specific kernel
command line. The neutral public builder never guesses a root device.

The Windows MSI review does not add UFS firmware: its relevant storage-related
evidence is for USB4/SuperSpeed and Qualcomm USB filters. UFS remains a Linux
DT and kernel-driver path, while the MSI evidence is recorded separately in
`docs/windows-power-analysis.md`.
