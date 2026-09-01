#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ESP=${SURFACE_ESP:-/boot/efi}
WAYDROID_CONFIG_NODES=${WAYDROID_CONFIG_NODES:-/var/lib/waydroid/lxc/waydroid/config_nodes}
WAYDROID_APP_USER=${WAYDROID_APP_USER:-amania}
WAYDROID_APP_HOME=${WAYDROID_APP_HOME:-/home/amania}
ANDROID_UKI="$ESP/EFI/Linux/surface-laptop-13-android.efi"
ANDROID_ENTRY="$ESP/loader/entries/surface-android.conf"

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

[[ $EUID -eq 0 ]] || die 'run this installer as root'
[[ -d "$SOURCE_DIR/boot" ]] || die "staging directory is incomplete: $SOURCE_DIR"
[[ -f "$SOURCE_DIR/boot/surface-laptop-13-android.efi" ]] || die 'Android UKI is missing'
[[ -f "$SOURCE_DIR/loader/surface-android.conf" ]] || die 'systemd-boot entry is missing'
[[ -f "$SOURCE_DIR/android/SurfaceControls.apk" ]] || die 'Surface Controls APK is missing'
[[ -f "$WAYDROID_CONFIG_NODES" ]] || die "Waydroid config_nodes not found: $WAYDROID_CONFIG_NODES"

need df
need getent
need grep
need install
need mountpoint
need runuser
need stat
need systemctl
need systemd-tmpfiles
mountpoint -q "$ESP" || die "$ESP is not a mounted ESP"

case "$ANDROID_UKI:$ANDROID_ENTRY" in
	*current*|*fallback*) die 'refusing to touch current/fallback boot components' ;;
esac
[[ ! -e "$ANDROID_UKI" ]] || die "refusing to overwrite existing Android UKI: $ANDROID_UKI"
[[ ! -e "$ANDROID_ENTRY" ]] || die "refusing to overwrite existing Android entry: $ANDROID_ENTRY"

command -v waydroid >/dev/null 2>&1 || die 'Waydroid is not installed'
command -v cage >/dev/null 2>&1 || die 'Cage is not installed; install the distro package first'
getent passwd "$WAYDROID_APP_USER" >/dev/null || die "user not found: $WAYDROID_APP_USER"

uki_size=$(stat -c '%s' "$SOURCE_DIR/boot/surface-laptop-13-android.efi")
available_kb=$(df -Pk "$ESP" | awk 'NR == 2 { print $4 }')
[[ "$available_kb" =~ ^[0-9]+$ ]] || die "cannot determine free space on $ESP"
required_kb=$(((uki_size + 16777216 + 1023) / 1024))
(( available_kb >= required_kb )) || die "not enough space on $ESP (need at least ${required_kb} KiB, have ${available_kb} KiB)"

# The Android files use their own names. No command in this installer writes
# current.efi, fallback.efi, or any pre-existing UKI.
install -D -o root -g root -m 0755 \
	"$SOURCE_DIR/boot/surface-laptop-13-android.efi" "$ANDROID_UKI"
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/loader/surface-android.conf" "$ANDROID_ENTRY"

install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/systemd/surface-android-mode.service" \
	/etc/systemd/system/surface-android-mode.service
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/systemd/surface-android-control.service" \
	/etc/systemd/system/surface-android-control.service
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/systemd/surface-android-control.socket" \
	/etc/systemd/system/surface-android-control.socket
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/systemd/waydroid-control.conf" \
	/etc/systemd/system/waydroid-container.service.d/30-surface-android-control.conf
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/systemd/greetd.service.d.conf" \
	/etc/systemd/system/greetd.service.d/50-surface-android-mode.conf
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/systemd/getty-tty1.service.d.conf" \
	/etc/systemd/system/getty@tty1.service.d/50-surface-android-mode.conf
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/tmpfiles.d/surface-android-control.conf" \
	/etc/tmpfiles.d/surface-android-control.conf
install -D -o root -g root -m 0755 \
	"$SOURCE_DIR/usr/bin/surface-android-session" /usr/bin/surface-android-session
install -D -o root -g root -m 0755 \
	"$SOURCE_DIR/usr/libexec/surface-android-control" /usr/libexec/surface-android-control
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/waydroid/surface-control.conf" /etc/waydroid/surface-control.conf
install -D -o root -g root -m 0644 \
	"$SOURCE_DIR/android/SurfaceControls.apk" /usr/share/surface-laptop-13/SurfaceControls.apk

include_line='lxc.include = /etc/waydroid/surface-control.conf'
grep -Fqx "$include_line" "$WAYDROID_CONFIG_NODES" ||
	printf '%s\n' "$include_line" >>"$WAYDROID_CONFIG_NODES"

systemd-tmpfiles --create /etc/tmpfiles.d/surface-android-control.conf
systemctl daemon-reload
systemctl enable surface-android-control.socket surface-android-mode.service
systemctl enable --now surface-android-control.socket

printf '%s\n' 'Installing Surface Controls into the existing Waydroid instance...'
if ! runuser -u "$WAYDROID_APP_USER" -- env \
	HOME="$WAYDROID_APP_HOME" USER="$WAYDROID_APP_USER" LOGNAME="$WAYDROID_APP_USER" \
	XDG_RUNTIME_DIR=/run/user/1000 \
	waydroid app install /usr/share/surface-laptop-13/SurfaceControls.apk; then
	printf '%s\n' 'WARNING: Waydroid did not accept the APK now.' >&2
	printf 'Run after starting the Waydroid container: %s\n' \
		"runuser -u $WAYDROID_APP_USER -- env HOME=$WAYDROID_APP_HOME XDG_RUNTIME_DIR=/run/user/1000 waydroid app install /usr/share/surface-laptop-13/SurfaceControls.apk" >&2
fi

printf '%s\n' 'Android Mode installed.'
printf 'Boot entry: %s\n' "$ANDROID_ENTRY"
printf '%s\n' 'Existing current/fallback UKIs were not modified.'
