# Recovery

Keep the known-good boot component set on removable storage before testing a
new DTB or UKI. Recovery requires only replacing the kernel, DTB, initramfs,
or UKI selected by the boot manager; no root filesystem is part of this set.

The generated `MANIFEST.json` and `SHA256SUMS` identify every component. Use a
visible terminal for any privileged copy to an ESP and verify the destination
with `cmp` and `sync` before rebooting.
