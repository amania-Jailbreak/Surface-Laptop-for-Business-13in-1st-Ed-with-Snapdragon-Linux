# Distribution

This project is distributed in two layers:

1. the Git repository, which contains the hardware source and build logic;
2. a GitHub Release asset, which contains the boot components produced from a
   known kernel, initramfs, firmware input, and root command line.

The release asset is a Debian package for convenient installation on Debian-
family systems. It contains only Surface boot components under
`/usr/lib/surface-laptop-13/`; it does not contain a root filesystem, desktop,
installer image, or disk image.

## Build a release package

First create the local recovery set with a real target command line:

```sh
export SURFACE_CMDLINE_FILE=/path/to/target-cmdline
./build.sh package
packaging/build-bundle-deb.sh SURFACE-CURRENT /path/to/release-assets
```

The command line must contain the root selector for the target installation.
The public placeholder `root=UUID=CHANGE-ME` is intentionally rejected for a
bootable release package.

The package builder reads the kernel release from
`SURFACE-CURRENT/kernel/release` and produces an ARM64 package named like:
`surface-laptop-13-hardware-support_7.2.0-rc5-surface-laptop-13_arm64.deb`.

## Install a boot component

Installing the package only copies data into `/usr/lib`; it does not change
the boot manager. To add a separate systemd-boot entry, run the bundled
installer explicitly as root:

```sh
sudo packaging/install-uki.sh SURFACE-CURRENT
```

The installer requires a mounted ESP and an existing
`/boot/efi/loader/entries` directory. It creates a versioned
`surface-laptop-13-*.efi` and matching entry, refuses an existing destination,
and never writes `current.efi` or `fallback.efi`. Use `--dry-run` to inspect
the paths before copying.

For distributions that do not use Debian packages, use the same
`SURFACE-CURRENT` directory as a release tarball and run the installer from
the extracted directory.

To test suspend without changing the normal boot files, build the separate
s2idle UKI with `./build.sh sleep` and install it with:

```sh
sudo packaging/install-s2idle.sh /tmp/surface-laptop-13-build/uki/surface-laptop-13-s2idle.efi
```

This installer creates only `surface-laptop-13-s2idle.efi` and its matching
entry, and refuses to overwrite an existing file.

## Release checklist

- build with the intended root command line and matching initramfs;
- run `./build.sh verify`;
- run the package builder and record its SHA256;
- state the kernel source revision and firmware source/hash manifest;
- list tested hardware in `docs/support-matrix.md`;
- attach source and binary license notices;
- do not attach a full OS image or raw disk image.
