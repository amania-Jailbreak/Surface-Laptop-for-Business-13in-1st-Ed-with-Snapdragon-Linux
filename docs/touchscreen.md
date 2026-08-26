# Touchscreen

The internal touchscreen is an HID-over-I2C device at address `0x34` on the
GENI controller at `0x00a80000`. Windows ACPI identifies it as
`MSHW0468`/`PNP0C50` and reports GPIO 38 as its interrupt.

The important board-specific value is:

```dts
hid-descr-addr = <0>;
```

This is not interchangeable with the value used by some other Snapdragon
Surface models. On the target machine, a direct 30-byte read from HID
descriptor register 0 begins with `1e 00 00 01`; register 1 returns an invalid
descriptor. The wrong value causes `i2c_hid_of` to report
`unexpected HID descriptor bcdVersion (0x0000)`.

The public build applies `device-tree/overlays/touchscreen.dtso` to both the
current and Bluetooth DTBs. A successful boot contains a line similar to:

```text
hid-multitouch ... I2C HID v1.00 Device [hid-over-i2c 1FD2:4001] on 1-0034
```

Useful checks on the target machine:

```sh
readlink /sys/bus/i2c/devices/1-0034/driver
grep -i -A8 -B1 '1FD2:4001\|hid-over-i2c' /proc/bus/input/devices
dmesg | grep -Ei 'i2c_hid|hid-multitouch|1-0034'
```

The configuration was hardware-tested together with USB-C host mode and the
WCN7850 Bluetooth overlay on 2026-08-26.
