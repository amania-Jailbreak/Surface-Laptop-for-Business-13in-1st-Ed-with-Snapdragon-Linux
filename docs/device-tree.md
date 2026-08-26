# Device-tree notes

The base board description is the known Type-C host configuration for the
Surface Laptop 13. Both external USB controllers are described as host mode,
which is required when the system disk is attached over USB-C.

The touchscreen overlay enables the GENI I2C controller at `0x00a80000` and
adds the `hid-over-i2c` device at address `0x34`. The Surface ACPI `_DSM`
returns HID descriptor register address `0`; using `1` produces an all-zero
descriptor and prevents the driver from binding. See `docs/touchscreen.md`
for the hardware evidence and target-side checks.

The Bluetooth overlay is deliberately separate. It enables:

- `/soc@0/geniqup@ac0000/serial@a98000`;
- a `qcom,wcn7850-bt` serdev child;
- 3.2 Mbaud maximum UART speed;
- the WCN7850 PMU Bluetooth enable GPIO;
- the board regulator inputs used by the Qualcomm HCI driver.

The overlays are applied to a DTB with `fdtoverlay`, not merged into a generic
kernel source tree. The touchscreen overlay is part of both generated DTBs;
the Bluetooth overlay remains an additional boot choice.

The experimental fingerprint overlay enables the internal USB2 controller at
`0x0a200000`. Windows identifies that controller as `QCOM0D09` and enumerates
the power-button ELAN `04f3:0c9e` fingerprint reader below it. See
`docs/fingerprint.md` for evidence, limitations, and test commands.

The experimental 3.5 mm codec work is not part of the default boot artifacts.
It remains documented as an unvalidated experiment under
`device-tree/overlays/experimental/`.
