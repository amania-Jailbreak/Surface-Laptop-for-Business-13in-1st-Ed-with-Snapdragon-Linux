# Initramfs integration

The OS supplies the base initramfs. The scripts here add only the early
hardware actions needed by this board, especially when the root filesystem is
on USB-C storage.

The scripts are intentionally separated by concern:

- `surface-hardware-init-premount.sh` prepares storage, USB, input, and PHY
  dependencies;
- `surface-bluetooth-init-premount.sh` optionally brings up the WCN7850 UART;
- `surface-waydroid-network-init-premount.sh` prepares networking modules for
  Waydroid;
- the Python helpers add files and matching modules to a `newc` archive.

Keep these hooks distribution-neutral. Do not put a complete distro initramfs,
root filesystem, or private firmware dump in this directory.
