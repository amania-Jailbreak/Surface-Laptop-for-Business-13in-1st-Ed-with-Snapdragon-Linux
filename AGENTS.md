# Working guide

This repository contains Linux hardware support for the Surface Laptop for
Business 13-inch (1st Edition), not a complete operating system. Start with
the root `README.md`, then read `docs/repository-layout.md` before changing a
component.

## Source of truth

- `kernel/config/` contains the base Kconfig and the additive desktop
  fragment.
- `kernel/patches/` contains small, board-specific kernel patches.
- `device-tree/base/` contains the board DTS. `device-tree/overlays/` contains
  optional hardware additions; `experimental/` is never selected implicitly.
- `initramfs/scripts/` contains distribution-independent early-boot hooks.
  The target OS supplies the base initramfs.
- `drivers/` contains firmware manifests, module requirements, and userspace
  driver notes. Firmware binaries are local inputs and must not be committed.
- `android-mode/` is optional userspace integration for Waydroid; it is not
  required for the normal hardware boot path.
- `build.sh` is the public entry point. It writes scratch data outside the
  repository by default (`/tmp/surface-laptop-13-build`).

## Safe change rules

- Never replace or modify an installed `current.efi` or `fallback.efi` from
  this repository. Test artifacts must have a distinct filename and boot entry.
- Do not add OS images, root filesystems, disk images, ACPI dumps, passwords,
  machine-specific UUIDs, or generated kernel trees.
- Keep USB-C root boot features built in unless a change has been tested with
  the system disk attached through USB-C.
- Keep experimental overlays out of the default build targets.
- When changing kernel configuration, update the relevant manifest or docs and
  run `./build.sh kernel` far enough to execute the feature checks.
- When changing a DT overlay, run `./build.sh dtb` and inspect the resulting
  node with `fdtget` before considering the change complete.

## Verification

Run the narrowest relevant check first, then:

```sh
./build.sh check
./build.sh dtb
./build.sh verify
```

Full kernel and UKI builds require externally supplied `KERNEL_SOURCE`,
`INITRD_BASE`, `FIRMWARE_SOURCE`, and an appropriate AArch64 toolchain. Never
assume those private inputs exist in a clean checkout.
