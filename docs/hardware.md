# Hardware notes

These values were collected from Windows PnP information, ACPI tables, EDID,
and successful Linux boot tests on Surface SKU 2095.

## Machine

| Item | Value |
|---|---|
| Product | Surface Laptop for Business 13in 1st Ed with Snapdragon |
| SKU suffix | 2095 |
| SoC | Qualcomm Snapdragon X Plus X1P42100 |
| CPU | 8 cores |
| Memory tested | 16 GiB |
| Firmware tested | Microsoft UEFI 9.42.235 |
| Storage | Hynix UFS, Windows ACPI ID `QCOM24A5` |

## Early console

| Item | Value |
|---|---|
| ACPI object | `\_SB.UARD` |
| MMIO | `0x00894000` |
| ACPI GSI | 845 |
| Device Tree SPI | 813 |
| Kernel argument | `earlycon=qcom_geni,0x894000` |

The UART is described by firmware but is not known to be externally exposed
on the retail chassis.

## USB and input

The working host controller is the multi-port controller at `0x0a400000`
(`usb_mp` in the upstream X1 Device Tree). The internal ELAN composite device
enumerates as USB `04f3:3317` and provides the keyboard and touchpad.

## Internal display

| Item | Value |
|---|---|
| Windows monitor ID | `LGD07AD` |
| Panel string | LG Display `LP130WU1` |
| Native mode | 1920×1280 at 60 Hz |
| Link | Internal eDP through DP3 |
| DP controller | `0x0aea0000` |
| DP PHY | `0x0aec5a00` |
| Data lanes | 0, 1, 2, 3 |
| Link rates | 1.62, 2.7, 5.4, 8.1 Gbit/s |

The Surface-specific SSDT adds `\_SB.TDPR` as the power resource for
`\_SB.GPU0.MON0`. Its operation region is `0x0f11d000`, which maps to TLMM
GPIO29 using the X1 TLMM layout:

```text
0x0f100000 + 29 × 0x1000 = 0x0f11d000
```

`TDPR._ON` writes `2` to the status register at offset 4 and waits 150 ms.
The Device Tree therefore models the panel 3.3 V rail as a fixed regulator
enabled by GPIO29 with a 150 ms startup delay.

The ACPI panel XML reports PMIC PWM backlight control, a 12-bit brightness
range, and 200 Hz PWM. The working Device Tree uses PMK8550 PWM channel 0
with a 5,000,000 ns period.

## ACPI identities used during bring-up

| Function | ACPI identity / resource |
|---|---|
| GPU/display | `QCOM0D17` |
| USB multi-port | `QCOM0D08`, MMIO `0x0a400000` |
| Secondary USB | `QCOM0D09`, MMIO `0x0a200000` |
| UFS | `\_SB.UFS0`, MMIO `0x01d84000` |
| Display hardware control | `MSHW0380` under `I2C1` |

Raw ACPI tables are intentionally not included in this repository.
