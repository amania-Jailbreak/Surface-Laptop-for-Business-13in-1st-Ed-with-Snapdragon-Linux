# Build model

The public build has four independent inputs:

| Input | Source | Result |
| --- | --- | --- |
| Kernel | Linux source plus the neutral config | `Image`, modules, release |
| Device tree | measured Type-C DTB plus touchscreen/Bluetooth/fingerprint overlays | touchscreen, touchscreen+Bluetooth, and experimental fingerprint DTBs |
| Initramfs | OS-provided initramfs plus early Surface hooks | boot initramfs |
| UKI metadata | neutral `os-release` and caller cmdline | EFI UKI |

`build.sh package` runs these stages and writes a local recovery set. It never
creates a partition table, mounts an ESP, writes a block device, builds a root
filesystem, or starts a package manager.

`build.sh release` performs the same build, then creates a versioned ARM64
Debian package under `SURFACE_RELEASE_DIR` (or the work directory's
`release-assets/`). The package is a release transport format only; the
separate `packaging/install-uki.sh` command is required to add a boot entry.

The command line contains `root=UUID=CHANGE-ME` as a safe placeholder. A
distribution integration must replace it with the UUID or label of its own
root filesystem before deployment.

Set `KERNEL_SOURCE`, `KERNEL_CONFIG`, `KERNEL_CONFIG_FRAGMENT`, `BASE_DTS`,
`INITRD_BASE`, `FIRMWARE_SOURCE`, and `UKI_STUB` to port the builder to another
host. The base DTB is compiled from `BASE_DTS` by default, so a clean clone
does not require an ignored binary. Set `BASE_DTB_INPUT` together with
`REBUILD_BASE_DTB=0` only when comparing against a separately obtained,
measured DTB.

`KERNEL_SOURCE`, `INITRD_BASE` and `FIRMWARE_SOURCE` have no default: the
full kernel/UKI build fails fast when they are not exported. The DTB-only
target does not require them and can be run independently with
`./build.sh dtb`. Example for an Ubuntu host that already installed its own
arm64 kernel packages:

```sh
export KERNEL_SOURCE=$HOME/src/linux
export KERNEL_CONFIG_FRAGMENT=$PWD/kernel/config/desktop.config
export INITRD_BASE=/boot/initrd.img-7.2.0-rc5-surface-laptop-13
export FIRMWARE_SOURCE=$HOME/firmware/qca-bluetooth
./build.sh uki
```

The generated module tree contains the optional CIFS and WireGuard modules in
addition to the Surface drivers. Install that module tree into the target OS
with the distribution's normal module-packaging tools. Only modules needed
before root discovery belong in the initramfs; CIFS and WireGuard can remain in
the installed module tree for ordinary post-boot use.
