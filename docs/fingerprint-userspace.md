# Fingerprint userspace (libfprint)

The DT overlay enumerates the reader as USB `04f3:0c9e`. Upstream libfprint
does not list this PID yet, so a small driver patch is required for enrollment
and matching.

## Patch summary

- register PID `04f3:0c9e` (ELAN 667, Match-on-Chip) in the elanmoc driver;
- this sensor reports MOC responses on EP3 and has no separate EP4 response
  pipe; the driver selects EP3 for cancelable MOC reads only when this PID is
  probed, so all other supported sensors are unaffected;
- hardware-tested: enrollment (9 stages) completes, `fprintd-verify` reports
  `verify-match`, listing and delete work through fprintd.

The full diff is kept as `drivers/libfprint-elanmoc-surface13.patch`.
## Applying

Build against libfprint master (1.94.x):

```sh
git clone https://gitlab.freedesktop.org/libfprint/libfprint.git
cd libfprint
patch -p1 < /path/to/libfprint-elanmoc-surface13.patch
meson setup build -Ddrivers=elanmoc -Dintrospection=false -Ddoc=false \
  -Dinstalled-tests=false -Dudev_rules=enabled -Dudev_rules_dir=/usr/lib/udev/rules.d \
  -Dudev_hwdb=enabled -Dudev_hwdb_dir=/usr/lib/udev/hwdb.d
meson compile -C build && sudo meson install -C build
```

If the distribution fprintd must use this library without replacing the system
package, run it with:

```
Environment=LD_LIBRARY_PATH=/usr/local/lib/aarch64-linux-gnu
```

(a systemd drop-in for `fprintd.service` is sufficient).

Note: current upstream master has an unrelated meson bug in
`tests/meson.build` when introspection is disabled (`foreach driver_test:
drivers_tests` iterates a dict with one variable). Use meson <= 1.3 or fix
that line locally if configure fails.

## Verification commands

```sh
lsusb -d 04f3:0c9e
fprintd-list $USER
sudo fprintd-enroll -f right-index-finger $USER
sudo fprintd-verify $USER        # expect: verify-match (done)
```

PAM integration (`libpam-fprintd`, `pam-auth-update`) is left to the
distribution layer and is not enabled by this repository.
