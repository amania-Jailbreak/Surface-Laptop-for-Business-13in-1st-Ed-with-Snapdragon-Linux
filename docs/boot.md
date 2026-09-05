# Boot layout

The generated UKI contains:

- the ARM64 Linux `Image`;
- an OS-provided or augmented initramfs;
- one Surface DTB;
- a neutral `.osrel` section;
- a caller-supplied `.cmdline` section.

The current UKI uses the base DTB. The Bluetooth UKI uses the DTB produced by
applying `device-tree/overlays/bluetooth.dtso` to the same base.

Install a UKI only after checking the ESP mount point and free space. The
`recovery/` helper only prints and verifies component paths. For the installed
Surface Proxmox system, `tools/install-surface-kvm-bundle.py` installs a
manifest-verified KVM bundle while preserving Ready and backing up overwritten
files. It neither reboots nor changes the default boot entry. See
[the installed KVM investigation](kvm-boot-diagnosis.md) for its scope and the
current hardware-test status.
