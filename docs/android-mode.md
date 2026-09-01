# Android Mode

Android Mode is a separate systemd-boot entry for running the existing Waydroid
instance fullscreen inside Cage. It does not replace the normal desktop entry,
`current.efi`, or `fallback.efi`.

The Android container is not given the Wi-Fi, Bluetooth, DRM, PCI, or USB
devices. Linux keeps ownership of those devices. `Surface Controls` talks to a
small allow-listed service through one Unix socket mounted into the container.
The service accepts only volume, brightness, NetworkManager, and BlueZ
operations; it never executes a command supplied by Android. Magisk is not
required: Android talks to the host through the mounted socket, while Linux
continues to own the real Wi-Fi, Bluetooth, audio, and backlight devices.

## Build

The normal hardware inputs are reused. The Android target adds
`surface.mode=android` to the supplied command line and stages everything under
`$SURFACE_WORK_DIR/android-mode`:

```sh
cat /proc/cmdline > /tmp/surface-cmdline
export SURFACE_CMDLINE_FILE=/tmp/surface-cmdline
./build.sh android
```

The command line file must contain the root selector used by the target OS,
such as `root=UUID=…` or `root=LABEL=…`. The Android target refuses the
placeholder root used by generic UKI builds.

The APK builder is deliberately Gradle-free. It needs an Android SDK platform
and build-tools installation. The UI uses the platform Material theme and a
Material 3-style color/layout system so it can be built without downloading
AndroidX dependencies. The quick-settings tile API is supplied as a
compile-only stub when the selected `android.jar` predates API 24; the stub is
never packaged into the APK.

```sh
export ANDROID_JAR=/opt/android-sdk/platforms/android-35/android.jar
export ANDROID_FRAMEWORK_RES_APK=/opt/android-sdk/platforms/android-35/framework-res.apk
export AAPT2=/opt/android-sdk/build-tools/35.0.0/aapt2
export D8=/opt/android-sdk/build-tools/35.0.0/d8
export APKSIGNER=/opt/android-sdk/build-tools/35.0.0/apksigner
export ZIPALIGN=/opt/android-sdk/build-tools/35.0.0/zipalign
./build.sh android
```

Alternatively, set `SURFACE_CONTROLS_APK` to an already signed APK. The build
does not include a root filesystem or Waydroid images.

## Install

Install Cage using the package provided by the target distribution, then run
the installer from the staged output as root:

```sh
sudo apt install cage
sudo "$SURFACE_WORK_DIR/android-mode/install-android-mode.sh"
```

When using the staged output, run the installer from that output directory:

```sh
sudo ./install-android-mode.sh
```

The installer checks that the ESP is mounted, checks free space, refuses an
existing Android UKI or entry, and never writes an existing UKI. It installs
`surface-laptop-13-android.efi` and `surface-android.conf` only. If the
Waydroid container is not ready for APK installation, it leaves the APK at
`/usr/share/surface-laptop-13/SurfaceControls.apk` and prints the retry command.

The Waydroid configuration is updated with an idempotent include for the
control socket. Restart the container before testing if it was already
running. Existing Waydroid data and GApps remain in place.

## Boot behavior

The Android entry starts a system service as `amania` on tty1. That service
starts Cage and runs the official Waydroid fullscreen command. In Android Mode,
greetd and `getty@tty1` are conditioned out. In normal boots those units and
the desktop configuration are unchanged.

If Cage or Waydroid exits, the service leaves a shell on the Android Mode TTY
instead of restarting the machine. Use the systemd-boot menu to select the
normal entry for recovery.

## Host control protocol

Requests are one JSON object per line on `/run/surface-control.sock` inside
Waydroid. The service currently exposes these operations:

```text
ping
volume.get, volume.set, volume.mute, volume.mute.toggle
audio.sinks, audio.default
brightness.get, brightness.set, brightness.step
wifi.status, wifi.radio, wifi.list, wifi.scan, wifi.connect, wifi.disconnect, wifi.toggle
bluetooth.status, bluetooth.devices, bluetooth.scan, bluetooth.power
bluetooth.pair, bluetooth.connect, bluetooth.disconnect
```

SSID and password values are base64-encoded UTF-8 strings. Bluetooth addresses
must be six-octet colon-separated addresses. No arbitrary path, executable, or
shell argument is accepted.

## Test checklist

After selecting Android Mode, verify:

```sh
systemctl is-active surface-android-control.socket
test -S /run/surface-android-control/control.sock
systemctl is-active greetd.service && echo 'unexpected in Android Mode'
bluetoothctl list
nmcli device status
```

Then use `Surface Controls` to change volume/brightness, scan Wi-Fi, and scan
or pair Bluetooth. The Wi-Fi, Bluetooth, and audio output lists are returned
as structured data and rendered as selectable rows. A Bluetooth audio sink is
still selected by Linux; Android does not receive a raw Bluetooth adapter.

The APK also declares five Android SystemUI quick-settings tiles. Add
`Surface Controls`, `Wi‑Fi (Linux host)`, `Bluetooth (Linux host)`, `音声
(Linux host)`, and `明るさ (Linux host)` from Android's tile editor. The tiles
operate the same allow-listed host service as the main screen.

The APK observes Android's media volume, screen brightness, `wifi_on`, and
`bluetooth_on` settings. With the optional `WRITE_SECURE_SETTINGS` grant, the
Linux host state is mirrored into Android SystemUI as well. Without that grant,
the dedicated host tiles and the main screen still work; Android's built-in
Wi-Fi/Bluetooth switches cannot control hardware that is intentionally not
passed through to the container.
