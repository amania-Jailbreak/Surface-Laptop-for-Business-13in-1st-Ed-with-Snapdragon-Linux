# Initramfs processing

The initramfs helper understands gzip-compressed `newc` archives and replaces
or adds regular files without unpacking a desktop root filesystem. The
Bluetooth target adds:

- `ecc`, `kpp`, and `ecdh_generic` crypto modules;
- the Bluetooth core, QCA/BCM helpers, and HCI UART driver;
- WCN7850 firmware;
- an early init-premount hook that loads the modules before root discovery.

The module paths are generated from the neutral kernel release, so the hook
does not depend on the release name used by the host distribution.

The same initramfs also preloads the bridge, veth, connection-tracking, NAT,
and legacy iptables modules used by Waydroid. This is intentional: those
modules must match the UKI kernel even when the installed root filesystem has
no module tree for that kernel.

The builder removes every `usr/lib/modules/` entry from the supplied base
archive before adding the new tree. It carries forward the base archive's boot
module set by relative path, resolves its dependencies with the new
`modules.dep`, and adds the Surface storage, USB/Type-C PHY, I2C-HID,
fingerprint, Bluetooth, CIFS, and WireGuard dependencies. Consequently a
kernel cannot accidentally load a module built for an older release during
early boot.

The rebuilt archive also carries the new kernel's `modules.builtin`,
`modules.builtin.modinfo`, and `modules.order` before running `depmod`. Without
those files, kmod cannot distinguish a deliberately built-in driver such as
UAS from a missing module.

`surface-hardware-init-premount` uses the generated dependency metadata to
load the USB-attached system disk, both Type-C PHY paths, the touchscreen HID
stack, and the optional desktop modules before root discovery. The Bluetooth
and Waydroid hooks remain separate and are included in both standard UKI
variants.

The builder registers all three hooks in the base archive's
`scripts/init-premount/ORDER`. Adding a script to that directory alone does
not make initramfs-tools execute it; keeping the registration in the generated
archive is required for the USB-root boot path.

The DWC3 wrapper, xHCI, USB mass-storage/UAS, QMP combo PHY, AUX bridge, and
the primary eUSB2 PHY are built into the kernel. The premount hook still
requests them for compatibility with older integration kernels, then asks
udev to settle, but a current build does not depend on that hook to discover
the USB system disk.

CIFS, WireGuard, and the additional desktop filesystems are built as optional
modules by the desktop configuration fragment. CIFS and WireGuard are included
in this Surface boot set because the persistent system is USB-attached and the
target OS may not yet have a matching module tree after `switch_root`. Other
desktop filesystems remain available through the normal kernel module package.
