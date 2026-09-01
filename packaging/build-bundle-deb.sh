#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BUNDLE=${1:-$ROOT_DIR/SURFACE-CURRENT}
OUTPUT_DIR=${2:-${SURFACE_RELEASE_DIR:-$ROOT_DIR/out/packages}}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

need dpkg-deb
need sha256sum
need strings

[[ -d "$BUNDLE" ]] || die "component set not found: $BUNDLE"
[[ -f "$BUNDLE/kernel/Image" ]] || die "kernel Image is missing"
[[ -f "$BUNDLE/kernel/config" ]] || die "kernel config is missing"
[[ -s "$BUNDLE/kernel/release" ]] || die "kernel release is missing"
[[ -f "$BUNDLE/dtb/surface-laptop-13-current.dtb" ]] || die "current DTB is missing"
[[ -f "$BUNDLE/initramfs/surface-laptop-13-current.img" ]] || die "current initramfs is missing"
[[ -f "$BUNDLE/uki/surface-laptop-13-current.efi" ]] || die "current UKI is missing"
[[ -f "$BUNDLE/MANIFEST.json" ]] || die "component manifest is missing"
[[ -f "$BUNDLE/SHA256SUMS" ]] || die "component checksums are missing"

release=$(tr -d '[:space:]' <"$BUNDLE/kernel/release")
case "$release" in
	[0-9]*) ;;
	*) die "kernel release is not a valid package version: $release" ;;
esac
case "$release" in
	*[!A-Za-z0-9.+~-]*) die "kernel release contains unsafe package characters: $release" ;;
esac

if strings "$BUNDLE/uki/surface-laptop-13-current.efi" | grep -Fq 'CHANGE-ME'; then
	die "UKI contains the placeholder root command line"
fi

mkdir -p "$OUTPUT_DIR"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
package_name=surface-laptop-13-hardware-support
package_root="$stage/usr/lib/surface-laptop-13/$release"
doc_root="$stage/usr/share/doc/$package_name"
mkdir -p "$stage/DEBIAN" "$package_root" "$doc_root"

cp -a "$BUNDLE/kernel" "$BUNDLE/dtb" "$BUNDLE/initramfs" \
	"$BUNDLE/firmware" "$BUNDLE/uki" "$BUNDLE/recovery" "$package_root/"
cp "$BUNDLE/MANIFEST.json" "$BUNDLE/SHA256SUMS" "$doc_root/"
if [[ -f "$BUNDLE/README.md" ]]; then
	cp "$BUNDLE/README.md" "$doc_root/README.surface-support"
fi

cat >"$stage/DEBIAN/control" <<EOF
Package: $package_name
Version: $release
Section: kernel
Priority: optional
Architecture: arm64
Maintainer: Surface Laptop 13 Linux Hardware Support maintainers
Description: Surface Laptop 13 Linux hardware boot components
 Hardware-specific kernel, device tree, initramfs, firmware manifest, and UKI
 components for the Surface Laptop 13. This package does not contain a root
 filesystem or a complete operating system.
EOF

destination="$OUTPUT_DIR/${package_name}_${release}_arm64.deb"
[[ ! -e "$destination" ]] || die "refusing to overwrite existing package: $destination"
dpkg-deb --build --root-owner-group "$stage" "$destination" >/dev/null
sha256sum "$destination" | tee "$destination.sha256"
printf 'Built %s\n' "$destination"
