# Initramfs processing

The initramfs helper understands gzip-compressed `newc` archives and replaces
or adds regular files without unpacking a desktop root filesystem. The
Bluetooth target adds:

- `ecc`, `kpp`, and `ecdh_generic` crypto modules;
- the Bluetooth core, QCA/BCM helpers, and HCI UART driver;
- WCN7850 firmware;
- an early init-premount hook that loads the modules before root discovery.

The WCN7850 Wi-Fi firmware is a separate required input. The ath12k driver is
built into the Surface kernel, but the PCI device still needs the complete
`ath12k/WCN7850/hw2.0` tree before it can probe. A direct `build.sh` invocation
must set `WCN7850_FIRMWARE_SOURCE` to that directory. The Debian wrapper finds
it automatically below `/lib/firmware` or a mounted target root; use
`--wcn7850-firmware DIR` to override it.

For an initramfs-tools target, install the repository hook
`initramfs/hooks/wcn7850-firmware` below `/etc/initramfs-tools/hooks/`, then
run `update-initramfs`. It copies the same complete firmware tree into the
generated initramfs, including the `ncm865` subdirectory.

The module paths are generated from the neutral kernel release, so the hook
does not depend on the release name used by the host distribution.

CIFS, WireGuard, and the additional desktop filesystems are built as optional
modules by the desktop configuration fragment. They are not forced into the
Bluetooth initramfs because most systems load them after `switch_root`. A
distribution that uses a network filesystem or VPN before the real root is
available must add the matching modules and their dependencies to its own
initramfs.
