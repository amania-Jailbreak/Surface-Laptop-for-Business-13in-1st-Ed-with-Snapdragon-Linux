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
repository intentionally provides no automatic privileged installer. The
`recovery/` helper only prints and verifies component paths; an OS integrator
must decide where its boot entries belong.
