# Surface Laptop 13 Linux Hardware Support

This repository contains board support for the Microsoft Surface Laptop for
Business 13-inch (1st Edition) with Qualcomm X1P42100. It is intentionally
independent of any Linux distribution. The repository describes the kernel,
device tree, firmware, driver requirements, initramfs hooks, and bootable UKI
assembly inputs.

It does not contain a root filesystem, desktop, installer, disk image, or
package repository. An operating system supplies those pieces and passes its
own root identifier and initramfs policy to the UKI build.

## Quick start

The native builder uses an existing Linux kernel checkout when one is present:

```sh
./build.sh check
./build.sh dtb
./build.sh kernel
./build.sh initramfs
./build.sh uki
./build.sh bluetooth
./build.sh package
./build.sh verify
```

The kernel build needs an AArch64 cross compiler. Device-tree and UKI assembly
can be run independently. A reproducible builder image is provided in
`Containerfile`; run it with Docker or Podman from a checkout that has the
kernel source and private boot-component inputs mounted or copied into the
build context.

## Outputs

`SURFACE-CURRENT/` is a local recovery set containing only Surface boot
components. It has no full operating-system image. The generated UKIs and
initramfs files are ignored by default because they can exceed the normal
100 MiB repository-file limit; `MANIFEST.json` and `SHA256SUMS` remain useful
for transfer and recovery.

The two UKIs both include the hardware-tested touchscreen configuration:

- `surface-laptop-13-current.efi`: Type-C host and touchscreen DTB with the
  base initramfs.
- `surface-laptop-13-bluetooth.efi`: the same Type-C/touchscreen baseline with the
  WCN7850 UART child and early Bluetooth modules/firmware.

The kernel release is deliberately neutral:
`7.2.0-rc5-surface-laptop-13` for the current source snapshot.

## Porting to another distribution

1. Build or obtain a kernel using `kernel/config/base.config` and the locked
   source revision in `kernel/source.lock`.
2. Place the distribution's own initramfs in the input path and add the
   Surface early module/firmware hook from `initramfs/scripts/`.
3. Set a distribution-owned root UUID or label in the command-line input.
4. Build the DTB/overlay and UKI, then verify the generated sections and
   hashes before copying them to the target ESP.

The hardware DTB uses host mode for both USB-C controllers. The Bluetooth
overlay enables the GENI UART at `a98000`, creates a `qcom,wcn7850-bt` serdev
child, and supplies the board PMU enable GPIO and regulator references.
The touchscreen overlay enables the GENI I2C controller at `a80000` and uses
the ACPI-confirmed HID descriptor register address `0`.

## Hardware validation

On the target machine, collect:

```sh
bluetoothctl list
rfkill list
lsusb
readlink /sys/bus/i2c/devices/1-0034/driver
cat /proc/cmdline
dmesg | grep -Ei 'dwc3|xhci|bluetooth|hci|qca|wcn7850|i2c_hid|hid-multitouch'
```

### 2026-08-26 verified configuration

A kernel built from this repository (`7.2.0-rc5-surface-laptop-13`) was booted
on the target machine as a UKI together with the Bluetooth DTB above. The
Bluetooth stack (hci_uart, btqca, bluetooth) loaded from the installed module
tree in the running root filesystem; no Bluetooth modules are required inside
the initramfs when the distribution installs `kernel/net/bluetooth`,
`kernel/drivers/bluetooth`, and the QCA firmware files listed in
`drivers/firmware-manifest.json` under `/lib/firmware/qca/`.

Type-C host mode works with direct-attached storage. When booting from USB,
load the `uas` module (or build it in) so second-stage storage is detected.

The internal touchscreen was identified as HID-over-I2C `1FD2:4001` on
`1-0034`. The WCN7850 Bluetooth controller and both USB-C host controllers
were active in the same boot. See `docs/touchscreen.md` for the ACPI-derived
descriptor-register value and failure signature.

The Type-C test must still be repeated with the boot SSD and a second USB
device in separate trials on untested units. Direct-attached storage has been
less reliable than storage behind a USB 2 hub on this board family.

## Licensing and firmware

The scripts and documentation in this repository are provided under the
license in `LICENSE`. Kernel source and patches retain their upstream
licenses. Qualcomm firmware is listed with hashes in
`drivers/firmware-manifest.json`; redistribution rights must be checked before
publishing those binary files.
