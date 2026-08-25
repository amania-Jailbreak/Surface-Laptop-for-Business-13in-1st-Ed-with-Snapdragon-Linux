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
