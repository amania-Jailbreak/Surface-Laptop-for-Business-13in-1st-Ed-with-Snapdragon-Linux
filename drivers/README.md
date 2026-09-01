# Driver and firmware inputs

This directory records what the hardware support needs; it is not a second
kernel source tree.

- `kernel-config.md` explains the relevant Kconfig symbols.
- `module-manifest.txt` lists modules that may be needed before or after root
  discovery.
- `firmware-manifest.json` records firmware names and hashes.
- `firmware/` is a local, ignored input directory. Obtain firmware separately
  and check redistribution terms before using it.
- `libfprint-*.patch` is a userspace driver patch for the ELAN fingerprint
  reader, not a kernel driver.
