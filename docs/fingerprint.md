# Fingerprint reader

The power button contains an ELAN 667-series Match-on-Chip fingerprint
reader. The Windows driver package identifies its USB interfaces as:

- `USB\\VID_04F3&PID_0C9E&MI_00`: Windows Biometric Framework / WinUSB;
- `HID\\VID_04F3&PID_0C9E&MI_01`: firmware-update HID interface;
- firmware revision `0405` (`Surface667FPR`).

Windows attaches the composite device to ACPI host controller `QCOM0D09`.
Its `_CRS` MMIO base is `0x0a200000`, which maps directly to
`/soc@0/usb@a200000` in the board DT. The measured Linux baseline leaves this
controller disabled, so the fingerprint reader cannot enumerate.

`device-tree/overlays/fingerprint-usb.dtso` enables that internal USB2 host
and its dedicated eUSB2 PHY at `0x088e0000`. Enabling only the controller
leaves the PHY disabled and causes `dwc3-qcom` to defer with
`failed to register DWC3 Core`.
It does not contain or redistribute the proprietary Windows driver or
firmware.

## Test status

Controller enablement is experimental until hardware testing confirms
`04f3:0c9e` in `lsusb`. Use the generated fingerprint UKI as a separate boot
entry and keep the validated boot entry unchanged.

After booting the test entry:

```sh
lsusb -d 04f3:0c9e
lsusb -t
dmesg | grep -Ei 'a200000|04f3|0c9e|elan|finger'
```

Enumeration is only the first stage. Upstream libfprint's development device
list does not currently include `04f3:0c9e`, although adjacent ELAN MOC IDs
are supported. A small ID/quirk addition may work, but enrollment and matching
must be tested before enabling PAM authentication. Keep password login
available throughout testing.
