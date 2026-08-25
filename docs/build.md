# Build model

The public build has four independent inputs:

| Input | Source | Result |
| --- | --- | --- |
| Kernel | Linux source plus the neutral config | `Image`, modules, release |
| Device tree | standalone board DTS plus overlay | base or Bluetooth DTB |
| Initramfs | OS-provided initramfs plus early Surface hooks | boot initramfs |
| UKI metadata | neutral `os-release` and caller cmdline | EFI UKI |

`build.sh package` runs these stages and writes a local recovery set. It never
creates a partition table, mounts an ESP, writes a block device, builds a root
filesystem, or starts a package manager.

The command line contains `root=UUID=CHANGE-ME` as a safe placeholder. A
distribution integration must replace it with the UUID or label of its own
root filesystem before deployment.

Set `KERNEL_SOURCE`, `KERNEL_CONFIG`, `BASE_DTS`, `INITRD_BASE`,
`FIRMWARE_SOURCE`, and `UKI_STUB` to port the builder to another host.

`KERNEL_SOURCE`, `INITRD_BASE` and `FIRMWARE_SOURCE` have no default: the
build fails fast when they are not exported. Example for an Ubuntu host that
already installed its own arm64 kernel packages:

```sh
export KERNEL_SOURCE=$HOME/src/linux
export INITRD_BASE=/boot/initrd.img-7.2.0-rc5-surface-laptop-13
export FIRMWARE_SOURCE=$HOME/firmware/qca-bluetooth
./build.sh uki
```
