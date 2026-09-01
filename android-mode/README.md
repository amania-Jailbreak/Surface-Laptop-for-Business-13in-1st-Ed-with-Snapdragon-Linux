# Android Mode integration

This directory contains the optional Waydroid session and the `Surface
Controls` companion app. It is separate from the normal desktop boot path.

- `app/` is the small Android client and its platform stubs;
- `bin/` contains the user session wrapper and the restricted host-control
  daemon;
- `systemd/` contains the Android-mode units and drop-ins;
- `waydroid/` contains the LXC integration fragment;
- `install-android-mode.sh` installs only the Android-mode files and adds a
  separate boot entry.

The Android mode must not replace the normal boot components. It expects the
host Linux system to own Wi-Fi, Bluetooth, audio, and brightness; Android
requests allowed operations through the host-control socket.
