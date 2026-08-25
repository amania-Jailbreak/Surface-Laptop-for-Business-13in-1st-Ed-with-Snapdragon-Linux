# Device-tree notes

The base board description is the known Type-C host configuration for the
Surface Laptop 13. Both external USB controllers are described as host mode,
which is required when the system disk is attached over USB-C.

The Bluetooth overlay is deliberately separate. It enables:

- `/soc@0/geniqup@ac0000/serial@a98000`;
- a `qcom,wcn7850-bt` serdev child;
- 3.2 Mbaud maximum UART speed;
- the WCN7850 PMU Bluetooth enable GPIO;
- the board regulator inputs used by the Qualcomm HCI driver.

The overlay is applied to a DTB with `fdtoverlay`, not merged into a generic
kernel source tree. This keeps the base and Bluetooth boot choices separate.

The experimental 3.5 mm codec work is not part of the default boot artifacts.
It remains documented as an unvalidated experiment under
`device-tree/overlays/experimental/`.
