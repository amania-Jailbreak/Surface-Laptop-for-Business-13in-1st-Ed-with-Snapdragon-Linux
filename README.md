# Surface Laptop 13 Linux

Linux support for the Surface Laptop for Business 13" (1st edition,
Snapdragon X1P42100), built by testing on real hardware. Everything here is
distro-neutral: kernel config and patches, device tree, firmware lists,
initramfs hooks, and the inputs needed to assemble a bootable UKI.

There is no root filesystem, desktop, or disk image in this repository. Your
distribution provides those; this repo provides the hardware-specific parts.


## What works

Tested on the actual machine:

- Boot via UKI (systemd-boot) from external USB storage
- Both USB-C ports in host mode (SSD, hub, display adapter)
- Bluetooth (WCN7850 over UART)
- Touchscreen (HID-over-I2C, `1FD2:4001`)
- Fingerprint reader in the power button (`04f3:0c9e`): enrollment and
  matching work through fprintd with a small libfprint patch

Known limitations: suspend reboots instead of resuming, the internal speaker
works but the 3.5mm jack needs more DT work before it is safe to enable, and
the internal microphone has never worked.


## Building

You need a kernel checkout and an AArch64 cross compiler. Then:

```sh
./build.sh check      # verify inputs exist
./build.sh dtb        # device trees (works standalone)
./build.sh kernel
./build.sh initramfs
./build.sh uki
./build.sh package
./build.sh verify
```

`Containerfile` builds the same thing in Docker/Podman if you prefer a
container. The kernel build is the slow part; everything else takes seconds.


## Boot files

The build produces three UKIs from one kernel:

- `surface-laptop-13-current.efi` - USB-C host + touchscreen, the baseline
- `surface-laptop-13-bluetooth.efi` - same + WCN7850 UART node and early BT
  modules/firmware in the initramfs
- `surface-laptop-13-fingerprint.efi` - bluetooth baseline + internal USB host
  for the fingerprint reader

Kernel version string: `7.2.0-rc5-surface-laptop-13`.


## KVM / EL2 boot

The Snapdragon X firmware normally enters Linux in EL1, so enabling
`CONFIG_KVM` alone is not sufficient. The KVM path uses the checked-in X1 EL2
overlay, a separate GRUB entry, and a Secure Launch EFI image built by
`tools/build-surface-kvm-efi.sh`. The supplied Microsoft `tcblaunch.exe` is
required by that Secure Launch step; Secure Boot must be disabled unless the
custom launcher is signed.

The normal firmware path must remain the original Proxmox shim. Only the
explicit EL2/KVM GRUB entry may chainload `surface-kvm-entry.efi`; putting the
Secure Launch launcher in the default `BOOTAA64.EFI` path causes the hook to be
installed twice and can hang at `Loading initial ramdisk`.

Build the EFI launcher from a normal Proxmox EFI image and add the optional
EL2 entry to a patched installer ISO as follows:

```sh
export KERNEL_SOURCE=/root/linux
export KERNEL_APPLY_PATCHES=1
export SURFACE_OUTPUT_DIR=build
export SURFACE_WORK_DIR=build/.work
./build.sh kernel
./build.sh dtb

./tools/build-surface-kvm-efi.sh \
  --base-efi build/surface-normal-efi.img \
  --output build/surface-kvm-efi.img \
  --tcb attachments/tcblaunch.exe \
  --slbounce-source /path/to/slbounce \
  --el2-dtb build/.work/dtb/surface-laptop-13-el2.dtb

GRUB_MODULE_DIR=/usr/lib/grub/arm64-efi \
./build-proxmox-iso.sh \
  --iso proxmox-ve_9.2-1-arm64.iso \
  --output build/proxmox-ve_9.2-1-arm64-surface-kvm.iso \
  --kernel-image build/.work/kernel/Image \
  --dtb build/.work/dtb/surface-laptop-13-current.dtb \
  --el2-dtb build/.work/dtb/surface-laptop-13-el2.dtb \
  --efi-image build/surface-kvm-efi.img
```

`--qebspil`/`--qebspil-source` can add the optional Qualcomm DSP pre-boot
loader, and `--firmware-tree` copies an additional firmware tree into the EFI
image. The normal EL1 DTB remains separate so non-KVM boots and hardware
variants can continue to use their own menu entries. The ISO KVM entries
chainload a Secure Launch bridge on the ISO filesystem, then boot the selected
EL2 DTB and installer initramfs; they do not rely on a writable GRUB
environment.


## Using on your own install

1. Build or reuse a kernel from `kernel/config/base.config` (source revision
   locked in `kernel/source.lock`).
2. Take your distro initramfs, add the early-firmware hook from
   `initramfs/scripts/` if you boot from USB-C storage.
3. Point the kernel cmdline at your root (`LABEL=`, `UUID=`, whatever your
   distro uses).
4. Assemble the UKI, check its sections/hashes, copy it to the ESP.

If booting from USB, make sure `uas` loads before root mount - build it in or
add it to initramfs modules.

Both USB-C controllers run fixed host mode (no role switching). The Bluetooth
overlay adds a `qcom,wcn7850-bt` serdev child on GENI UART `a98000` plus its
enable GPIO/regulators; touchscreen sits on I2C at `a80000`, address `0x34`,
HID descriptor register 0 (from Windows ACPI).


## Checking it works

After boot, useful commands:

```sh
bluetoothctl list          # should show a controller
rfkill list                # nothing hard-blocked
lsusb                      # 04f3:3317 keyboard/touchpad, 04f3:0c9e fingerprint
cat /proc/asound/cards     # sound card present
dmesg | grep -Ei 'dwc3|xhci|wcn7850|i2c_hid'
```

Fingerprint userspace setup (libfprint patch, fprintd) is documented in
`docs/fingerprint-userspace.md`.


## Docs

- `docs/build.md` - build system details
- `docs/boot.md` - UKI layout, systemd-boot entries
- `docs/device-tree.md` - what each overlay changes and why
- `docs/bluetooth.md`, `docs/touchscreen.md`, `docs/fingerprint.md` -
  per-device notes with ACPI references and failure signatures
- `docs/porting.md` - adapting to another distribution
- `docs/recovery.md` - SURFACE-CURRENT recovery set


## Firmware note

Qualcomm firmware files are listed with SHA256 hashes in
`drivers/firmware-manifest.json`. This repo does not ship them - check your
redistribution rights before publishing binaries.
