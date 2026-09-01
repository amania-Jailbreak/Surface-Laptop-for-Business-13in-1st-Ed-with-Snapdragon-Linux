# Kernel inputs

- `config/base.config` is the starting configuration.
- `config/desktop.config` is an additive fragment for CIFS, WireGuard,
  Waydroid, and ordinary desktop support.
- `patches/` contains only board-specific patches that are not already present
  in the selected kernel source.
- `source.lock` records the expected source revision and toolchain assumptions.

Do not edit the generated `.config` in the work directory. Change a fragment,
then let `build.sh` merge it and run `olddefconfig`. USB storage, xHCI, DWC3,
the required PHY path, SCSI, and the root filesystem support must remain built
in when booting the system from USB-C.
