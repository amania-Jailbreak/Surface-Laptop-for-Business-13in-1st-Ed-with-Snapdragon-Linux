# Linux hardware support for Surface Laptop for Business 13in 1st Ed with Snapdragon

This repository contains the Linux hardware support for the **Surface Laptop
for Business 13-inch (1st Edition)** with the Qualcomm Snapdragon X1P42100.
It is for people who want to run their own Linux distribution on this laptop
and need the board-specific pieces that the distribution does not provide.

This is not a Linux distribution. There is no root filesystem, desktop
environment, installer, disk image, or complete operating system here. The
repository contains the source and build helpers for:

- the board device tree and optional hardware overlays;
- kernel configuration and small board-specific patches;
- early-boot initramfs hooks for USB-C root storage;
- firmware and kernel-module manifests;
- optional Waydroid/Android Mode host integration;
- UKI assembly, verification, packaging, and recovery helpers.

The operating system remains the responsibility of the user. Ubuntu, Debian,
Arch, and other distributions can provide their own kernel packaging,
initramfs generator, userspace, and package format.

## Hardware status

These results are from the target laptop. A driver being enabled in the
configuration is not treated as proof that the hardware works.

| Component | Status | Notes |
| --- | --- | --- |
| USB-C host mode | Working | Both USB-C controllers have been used with external storage, hubs, and a display adapter. |
| Boot from USB-C storage | Working | USB, PHY, DWC3, xHCI, SCSI, UAS, and root filesystem support must be available before the root mount. |
| Internal USB-A and keyboard/touchpad | Working | The internal HID devices enumerate through xHCI. |
| Touchscreen | Working | HID-over-I2C at `0x34`; the HID descriptor address is `0`. |
| Wi-Fi | Working | Qualcomm WCN7850; firmware is supplied by the target OS. |
| Bluetooth | Working | WCN7850 Bluetooth over the Qualcomm GENI UART. |
| Fingerprint reader | Working with userspace support | ELAN `04f3:0c9e`; requires the documented libfprint/fprintd setup. |
| CIFS/SMB | Enabled | Optional kernel module in the desktop configuration. |
| WireGuard | Enabled | Optional kernel module with policy-routing support. |
| Waydroid kernel primitives | Enabled | Binder, binderfs, PSI, memfd, bridge, VETH, and firewall support are included. |
| Internal speaker | Partial | Depends on the Qualcomm DSP, codec, firmware, and distribution audio setup. |
| Internal microphone | Not working | The VA capture codec path is still unresolved. |
| 3.5 mm jack | Experimental | Kept out of the default build because testing caused unstable audio/USB behavior. |
| Suspend/resume | Unsupported | The machine may reboot or lose USB devices on resume. |

See [`docs/support-matrix.md`](docs/support-matrix.md) for the detailed test
notes and the distinction between tested, enabled, and experimental features.

## Repository layout

```text
build.sh                     build and verification entry point
Containerfile                container build environment
device-tree/base/            board DTS source
device-tree/overlays/        touchscreen, Bluetooth, fingerprint, and optional overlays
drivers/                     module and firmware manifests; userspace notes
initramfs/scripts/           distribution-independent early-boot hooks
kernel/config/               base and desktop Kconfig fragments
kernel/patches/              small board-specific kernel patches
android-mode/                optional Waydroid session and host-control integration
packaging/                   release package and safe UKI installer
recovery/                    recovery-component helper
manifests/                   machine-readable hardware metadata
docs/                        build, boot, device, and porting documentation
```

Generated files are not source. A clean checkout should not contain a kernel
build tree, firmware binaries, a complete initramfs, or a full OS image.
`SURFACE-CURRENT/` is an ignored local recovery directory created by the
package target; it is not intended to be committed.

Start with [`docs/repository-layout.md`](docs/repository-layout.md) when
deciding where a change belongs.


## Building

The device-tree target can be run independently from a clean checkout:

```sh
./build.sh dtb
```

Kernel, initramfs, UKI, and package targets need a kernel source checkout, the
target OS initramfs, firmware inputs, and an AArch64 toolchain. These are
provided through the environment and are not copied into this repository:

```sh
export KERNEL_SOURCE=/path/to/linux
export KERNEL_CONFIG=$PWD/kernel/config/base.config
export KERNEL_CONFIG_FRAGMENT=$PWD/kernel/config/desktop.config
export INITRD_BASE=/path/to/target/initramfs.img
export FIRMWARE_SOURCE=/path/to/firmware
export UKI_STUB=/usr/lib/systemd/boot/efi/linuxaa64.efi.stub

./build.sh check
./build.sh kernel
./build.sh dtb
./build.sh initramfs
./build.sh uki
```

For a bootable UKI, provide the command line used by the target installation.
Without it, the public build uses the intentionally invalid placeholder
`root=UUID=CHANGE-ME` so an artifact cannot boot the wrong filesystem:

```sh
export SURFACE_CMDLINE_FILE=/path/to/target-cmdline
./build.sh uki
```

The available targets are:

```sh
./build.sh check       # check the complete local build inputs
./build.sh kernel      # build Image, modules, and config
./build.sh dtb         # compile the base DTB and public overlays
./build.sh initramfs   # add the Surface early-boot hooks
./build.sh uki         # assemble the normal UKI variants
./build.sh bluetooth   # build the Bluetooth test UKI
./build.sh fingerprint # build the fingerprint test UKI
./build.sh android     # stage the optional Waydroid Android Mode
./build.sh package     # create a local component/recovery set
./build.sh release     # create the versioned ARM64 release package
./build.sh verify      # check names, DT nodes, boundaries, and file sizes
```

`Containerfile` describes a container environment for the tools. The kernel
source, initramfs, firmware, and target command line remain external inputs;
the container does not download or package a full operating system.


## Boot files

The build can produce several UKIs from the same kernel and initramfs. The
artifact filenames use the shorter `surface-laptop-13` identifier for
practical filesystem and boot-entry naming; they all target the device named
above:

```text
surface-laptop-13-current.efi       USB-C host, touchscreen, and base audio
surface-laptop-13-bluetooth.efi     base hardware plus the WCN7850 UART
surface-laptop-13-fingerprint.efi   Bluetooth hardware plus the fingerprint USB host
surface-laptop-13-android.efi       optional Waydroid Android Mode
```

The normal `current` artifact uses the all-feature DTB selected by the public
build. The Bluetooth and fingerprint variants are kept separate so that a
new or experimental controller can be tested without replacing a known-good
boot entry.

Install a test UKI as a separate systemd-boot entry. Do not replace an
existing `current.efi` or `fallback.efi` while testing a new device tree,
kernel, or initramfs. `packaging/install-uki.sh` refuses those destinations
and checks the ESP free space before copying anything.

When the system disk is connected through USB-C, the early boot path is the
critical part. USB host mode, the Qualcomm USB PHY, DWC3, xHCI, USB storage,
UAS, SCSI, and root filesystem support must be built in or included in the
initramfs before the root filesystem is discovered. CIFS and WireGuard usually
belong in the installed module tree and do not need to be in the initramfs.

The overlays are board-specific. The touchscreen HID descriptor address and
the Bluetooth UART wiring must not be copied from another Snapdragon Surface
model without hardware evidence.


## Initramfs and firmware

The target distribution supplies the base initramfs. The scripts in
`initramfs/scripts/` add only the early actions needed by this board, such as
preparing USB-C storage dependencies and optionally loading Bluetooth support.
They do not replace the distribution's init system or root filesystem.

Firmware binaries are intentionally not stored here. See
[`drivers/firmware-manifest.json`](drivers/firmware-manifest.json) for the
required names and hashes, then obtain the firmware from a source whose
redistribution terms permit its use.

## Android Mode

`android-mode/` is optional. It provides a separate Waydroid session and a
small `Surface Controls` application that can request selected host-side
operations through a Unix socket. Linux remains responsible for the real
Wi-Fi, Bluetooth, audio, and brightness devices; this mode does not pass the
hardware through to Android.

The normal desktop boot path is left unchanged. Android Mode requires a real
target command line and an existing Waydroid installation. See
[`docs/android-mode.md`](docs/android-mode.md) before enabling it.

## Verification after boot

Use the commands appropriate for the features being tested:

```sh
uname -r
lsusb
rfkill list
bluetoothctl list
cat /proc/asound/cards
dmesg | grep -Ei 'dwc3|xhci|qmp|wcn7850|serdev|i2c_hid|hid-multitouch'
```

For a USB-C root boot, confirm that the external disk remains present after
the root filesystem is mounted. For Bluetooth, confirm both the UART/firmware
messages and an adapter in `bluetoothctl`. For the touchscreen and fingerprint
reader, use the device-specific checks in the documentation rather than
assuming that a successful kernel build means the device works.

## Porting to another distribution

The smallest integration consists of four parts:

1. start with the kernel configuration and source revision recorded in
   `kernel/`;
2. compile the base DTS and apply only the overlays supported by the target
   hardware;
3. keep the distribution's own initramfs generator and add the relevant early
   hooks and modules;
4. assemble a UKI using the distribution's root selector, initramfs, and boot
   entry conventions.

Replace the example root UUID or label with the value used by the target
installation. Keep firmware outside the repository unless its license permits
redistribution. The complete checklist is in
[`docs/porting.md`](docs/porting.md).

## Contributing

For a hardware change, include the kernel source revision, configuration delta,
DTB/overlay selection, firmware requirements, and the result of testing on
this exact laptop. Keep experiments under an explicitly named directory and
do not add them to the default build without a real hardware test.

Before submitting a change, run at least:

```sh
./build.sh check
./build.sh dtb
./build.sh verify
```

Do not commit generated UKIs, kernel images, initramfs images, firmware
binaries, OS images, raw disks, private ACPI dumps, credentials, or a copied
kernel source tree. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full
checklist.

## Documentation index

- [`docs/repository-layout.md`](docs/repository-layout.md) — source map and boundaries
- [`docs/support-matrix.md`](docs/support-matrix.md) — tested and experimental hardware
- [`docs/build.md`](docs/build.md) — inputs and build data flow
- [`docs/boot.md`](docs/boot.md) — UKI contents and boot entries
- [`docs/device-tree.md`](docs/device-tree.md) — base tree and overlays
- [`docs/bluetooth.md`](docs/bluetooth.md) — WCN7850 UART and firmware
- [`docs/touchscreen.md`](docs/touchscreen.md) — HID-over-I2C details
- [`docs/fingerprint.md`](docs/fingerprint.md) — reader and DT requirements
- [`docs/fingerprint-userspace.md`](docs/fingerprint-userspace.md) — libfprint/fprintd setup
- [`docs/initramfs.md`](docs/initramfs.md) — early-boot hooks
- [`docs/android-mode.md`](docs/android-mode.md) — optional Waydroid session
- [`docs/recovery.md`](docs/recovery.md) — external recovery components
