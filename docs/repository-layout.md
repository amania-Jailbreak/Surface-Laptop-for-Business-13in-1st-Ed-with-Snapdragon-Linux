# Repository layout

The repository is intentionally split into hardware source, build helpers,
and documentation. A clean checkout should contain source and manifests only;
large boot outputs are generated in the work directory or kept in a separate
recovery location.

```text
.
├── build.sh                 public build and verification entry point
├── Containerfile            reproducible build environment definition
├── device-tree/             board DTS and optional overlays
├── drivers/                 firmware/module manifests and userspace patches
├── initramfs/               early-boot hooks; no complete initramfs image
├── kernel/                  config fragments, patches, and source lock
├── android-mode/            optional Waydroid host-control integration
├── recovery/                restore helper for an external component set
├── manifests/               machine-readable hardware support metadata
└── docs/                    component behavior, porting, and test notes
```

## Where to make a change

| Goal | Change | Do not change |
| --- | --- | --- |
| Enable a kernel facility | `kernel/config/*.config` | a generated `.config` in a build directory |
| Work around a kernel bug | `kernel/patches/*.patch` | a copied kernel source tree |
| Describe board hardware | `device-tree/base/*.dts` | a generated `.dtb` |
| Add an optional device | `device-tree/overlays/*.dtso` | the default overlay chain without hardware evidence |
| Load something before root discovery | `initramfs/scripts/` | a distro-specific root filesystem |
| Add firmware support | `drivers/firmware-manifest.json` | checked-in firmware binaries |
| Change Android Mode | `android-mode/` and `docs/android-mode.md` | the normal boot entry or installed fallback UKI |

## Build data flow

```text
kernel source + config + patches ──┐
board DTS + overlays ──────────────┼─> kernel / DTB / initramfs ─> UKI
OS initramfs + firmware inputs ────┘                  │
                                                     └─> external test/recovery set
```

`build.sh` owns the composition and validation. Component directories should
remain declarative: configuration, source snippets, scripts, and manifests.
Generated files belong under `SURFACE_WORK_DIR` or an explicitly external
artifact directory.

## Naming

Use `surface-laptop-13-<feature>` for artifacts and boot entries. Use the
feature name for source files (`bluetooth.dtso`, `touchscreen.dtso`) and keep
experimental work under an explicit `experimental/` directory. A file named
`current` or `fallback` in this repository must never imply permission to
overwrite an installed boot component.
