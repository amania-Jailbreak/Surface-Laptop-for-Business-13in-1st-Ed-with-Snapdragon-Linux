# Build model

The public build has four independent inputs:

| Input | Source | Result |
| --- | --- | --- |
| Kernel | Linux source plus the neutral config | `Image`, modules, release |
| Device tree | measured Type-C DTB when supplied, otherwise the checked-in DTS, plus touchscreen/Bluetooth/fingerprint overlays | touchscreen, touchscreen+Bluetooth, and experimental fingerprint DTBs |
| Initramfs | OS-provided initramfs plus early Surface hooks | boot initramfs |
| UKI metadata | neutral `os-release` and caller cmdline | EFI UKI |

`build.sh package` runs these stages and writes a local recovery set. It never
creates a partition table, mounts an ESP, writes a block device, builds a root
filesystem, or starts a package manager.

The command line contains `root=UUID=CHANGE-ME` as a safe placeholder. A
distribution integration must replace it with the UUID or label of its own
root filesystem before deployment.

Set `KERNEL_SOURCE`, `KERNEL_CONFIG`, `KERNEL_CONFIG_FRAGMENT`, `BASE_DTS`,
`BASE_DTB_INPUT`, `INITRD_BASE`, `FIRMWARE_SOURCE`, and `UKI_STUB` to port the
builder to another host. `UKIFY` can point to a non-standard `ukify` executable;
the builder also detects the Debian paths `/usr/lib/systemd/ukify` and
`/lib/systemd/ukify`.

The measured base DTB is not tracked in this source-only repository. If
`BASE_DTB_INPUT` is absent, the builder compiles `BASE_DTS` automatically;
`REBUILD_BASE_DTB=1` forces that source rebuild even when a measured DTB is
available.

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

## Patching a Proxmox VE ARM64 ISO

When `proxmox-ve_9.2-1-arm64.iso` is in the repository root, the dedicated
wrapper builds the Surface ARM64 kernel, builds the current Surface DTB, adds
the matching kernel modules to the Proxmox installer initramfs, and writes a
new bootable ISO under `build/`:

```sh
apt-get install -y xorriso p7zip-full zstd cpio
./build-proxmox-iso.sh
```

The default output is
`build/proxmox-ve_9.2-1-arm64-surface.iso`. Use `--iso FILE`, `--output FILE`,
`--kernel-image FILE`, or `--dtb FILE` to override individual inputs. The
result contains an unsigned development kernel, so Secure Boot must be
disabled or the kernel must be signed before booting it.
