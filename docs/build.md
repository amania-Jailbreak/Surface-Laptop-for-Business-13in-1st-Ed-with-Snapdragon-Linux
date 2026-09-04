# Build model

The public build has four independent inputs:

| Input | Source | Result |
| --- | --- | --- |
| Kernel | Linux source plus the neutral config | `Image`, modules, release |
| Device tree | measured Type-C DTB plus UFS nodes and touchscreen/Bluetooth/fingerprint overlays | touchscreen, touchscreen+Bluetooth, and experimental fingerprint DTBs with UFS enabled |
| Initramfs | OS-provided initramfs plus early Surface storage hooks | boot initramfs with USB-C and UFS module paths |
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

Kernel output is incremental by default. Keep the same `SURFACE_WORK_DIR`
for subsequent builds so the out-of-tree objects and generated module tree can
be reused:

```sh
./build.sh kernel
./build.sh sleep
```

Use `KERNEL_REUSE_OUTPUT=0 ./build.sh kernel` for a deliberate clean build.
Use `KERNEL_FORCE_MODULE_INSTALL=1 ./build.sh kernel` to force module
deployment when the installed module tree must be refreshed.

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

## Test suspend with USB-root boot

The target currently exposes both `s2idle` and `deep`, but `deep` is the
default selected by the running kernel. Since the system disk is attached
through USB-C, build a separate test UKI that selects `s2idle`:

```sh
export SURFACE_CMDLINE_FILE=/path/to/target-cmdline
./build.sh sleep
packaging/install-s2idle.sh --dry-run /tmp/surface-laptop-13-build/uki/surface-laptop-13-s2idle.efi
sudo packaging/install-s2idle.sh /tmp/surface-laptop-13-build/uki/surface-laptop-13-s2idle.efi
```

This creates only `surface-laptop-13-s2idle.efi` and a matching boot entry;
it never replaces `current.efi` or `fallback.efi`. The result still requires
hardware testing, especially resume of the USB-C system disk.

The sleep test also adds `usbcore.autosuspend=-1` and marks the two Type-C
host wrappers with `qcom,keep-host-on-suspend`. This keeps the USB-root bridge
out of runtime autosuspend and leaves the Qualcomm host wrappers active across
s2idle. It is intentionally a sleep-test policy and is not applied to the
normal UKIs.

The generated module tree contains the optional CIFS and WireGuard modules in
addition to the Surface drivers. Install that module tree into the target OS
with the distribution's normal module-packaging tools. Only modules needed
before root discovery belong in the initramfs; CIFS and WireGuard can remain in
the installed module tree for ordinary post-boot use. The internal UFS path has
the same early-boot requirement: its QMP UFS PHY and Qualcomm host modules are
seeded into the matching initramfs when they are modular.
