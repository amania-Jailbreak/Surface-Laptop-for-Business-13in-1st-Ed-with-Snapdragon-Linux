# Windows power-management notes

This note records the hardware evidence used for the suspend work. It does not
redistribute the vendor installer, Windows drivers, firmware packages, or an
operating-system image.

## Source material

The investigated installer was:

```text
SurfaceLaptop_13in_1st_Edition_Win11_26100_26.061.13017.0.msi
SHA256: 5231aaffd1baca4e2006dcc0c80477b325ec32f9a34e4511e5321fb49c9b64f3
```

The Windows ACPI registry export was inspected separately. The relevant
devices are the two Qualcomm USB wrappers (`URS0`/`QCOM0C8B` at `0x0a600000`
and `URS1`/`QCOM0C8C` at `0x0a800000`) and the UCSI device (`UCS0`/`QCOM0CA4`).
The Windows device map associates these with `UrsSynopsys`, `qcusbcucsi`, and
`UcmUcsiAcpiClient`.

## What the Windows binaries tell us

The installer contains native ARM64 Qualcomm components with Power Framework
(`PoFx`) integration. The USB-C UCSI driver registers a PoFx device and the
USB4 bus/filter components contain explicit sleep, resume, PHY-standby, link
resume, and reset-timeout state handling. `UCS0.bin` describes a private
resource graph for the primary, secondary, and tertiary USB blocks: GDSCs,
clocks, interconnect bandwidth, and PMIC/TLMM GPIO operations.

Those resources are Windows PEP/PoFx data, not a Linux firmware interface. The
Linux driver cannot consume the binary resource graph directly. It is useful
as evidence that the two DWC3 wrappers and their xHCI children must be kept as
a coordinated power-management unit when the root disk is attached through
USB-C.

## SuperSpeed and retimer evidence

The installer also contains a useful description of the USB 3 path. The
relevant INF files bind to these ACPI devices:

| Installer component | Windows binding | Role indicated by the INF |
| --- | --- | --- |
| `qcusbcucsi8380` | `ACPI\\QCOM0CA4` (`UCS0`) | USB-C/UCSI policy and power-framework client |
| `QcUsb4Bus8380` | `ACPI\\QCOM0C6D` | USB4 bus device |
| `QcUsb4Filter8380` | `USB4\\QCOM0CD10001` | USB4 host-router filter, marked for USB-disk boot loading |
| `QcXhciFilter8380` | `URS\\QCOM0C8B/0C8C/0D07` plus `ACPI\\QCOM0CA1/0D08/0D09` | xHCI/URS host-mode filter |
| `QcUsbFnSsFilter8380` | `URS\\QCOM0C8B/0C8C/0D07&FUNCTION` | USB function-mode SuperSpeed filter |

The native filters contain state names for PHY presets, USB 3 warm-up,
quick bit lock, link lane disable, standby, and SuperSpeed/SuperSpeedPlus
transitions. They are not Linux drivers, but they explain why merely enabling
the DWC3 and xHCI devices is not equivalent to the Windows configuration.

The embedded platform device tree in `Surface_UEFI_9.166.235.bin` is more
directly useful. Its `usb0`, `usb1`, and `usb2` blocks each describe a PS8830
retimer, use a 100 kHz management bus, allow up to 500 microseconds of clock
stretching, and wait 20 milliseconds after reset. The entries are:

| Firmware block | QMP block | I2C bus field | Target | Reset field | Power-enable fields |
| --- | --- | ---: | ---: | --- | --- |
| `usb0` | `fd5000` | `4` | `0x08` | `9` | `3p3=10`, `1p1=0`, `1p8=0` |
| `usb1` | `fda000` | `8` | `0x08` | `176` | `3p3=186`, `1p1=188`, `1p8=175` |
| `usb2` | `fdf000` | `2` | `0x08` | `185` | `3p3=187`, `1p1=189`, `1p8=126` |

The GPIO values above are firmware resource fields, not ready-made Linux
`gpio-ranges` or regulator references. The `usb1` values line up with the
TLMM GPIOs used by the upstream X1E Microsoft Type-C example; the `usb0`
fields still require an exact PMIC/TLMM provider mapping before they can be
used in a Linux DT. `usb2` is disabled in the current Linux board description
and is not part of the first external-port test.

The same firmware tree contains complete SuperSpeed PHY register tables for
`fd5000`, `fda000`, and `fdf000`. This is evidence that the QMP PHY blocks are
expected to be paired with the retimer and its power sequence. It is not a
reason to copy the vendor register table into Linux: the upstream Qualcomm
QMP driver already owns the PHY programming.

The observed Linux state is consistent with the missing retimer path:

* the active Type-C storage controller (`a600000`, QMP `fd5000`) enumerates the
  RTL9210 at 480 Mb/s on USB bus 1;
* the USB 3 companion bus has no corresponding storage device;
* the Linux DT connects the QMP PHY directly to DWC3 and contains no PS8830
  node; and
* the QMP PHY reports dummy `vdda-phy`/`vdda-pll` supplies because those supply
  relationships are not described.

This makes the first speed test a separate DTB/UKI that enables the exact
QUP0 SE4 and QUP1 SE0 I2C paths, adds the PS8830 graph, and supplies the
retimer rails. It must be tested without replacing either known-good UKI.
The USB4 host-router resource at ACPI `QCOM0D09` (I2C address `0x4b` on
`I2C6`/QUP0 SE5) is a different path and must not be mistaken for the PS8830
at address `0x08`.

The MSI, its extracted files, and all Windows `.sys` files remain outside this
repository. Only the installer SHA256 and the hardware facts needed to
reproduce the Linux investigation are recorded here.

## GPIO29 and the display rail

The ACPI `TDPR` power resource maps to the Linux `regulator-edp-3p3` rail:

```text
Windows _ON:  write 0x02 to the GPIO29-backed register, then wait 150 ms
Windows _OFF: clear the same register
Linux:        GPIO29, active high, startup delay 150 ms
```

Windows shares this power resource between the touchscreen and the GPU display
monitor. Therefore the display rail must not be forced `regulator-always-on`
as a USB workaround: doing so changes the normal display power state and was
observed to make the Type-C path fail on the test machine. The suspend test
keeps the display rail under normal regulator control.

## Linux suspend strategy

The test DTB marks both Qualcomm USB wrappers with
`qcom,keep-host-on-suspend`. The kernel patches honor that opt-in at two
levels:

1. the Qualcomm DWC3 wrapper does not tear down its host-side power state;
2. the child `xhci-plat` controller does not save/stop the host during
   `s2idle`.

The xHCI guard is deliberately limited to `PM_SUSPEND_TO_IDLE`. Runtime PM is
not changed, and the normal UKIs do not receive this policy. The test UKI
selects `mem_sleep_default=s2idle` and disables USB device autosuspend so that
the USB-C system disk remains available while the display can still turn off.

This is a bring-up workaround, not proof that deep suspend is safe. Deep sleep
must remain a separate test after a reliable non-USB root boot path exists.
## Display-off path

The panel in the tested machine identifies as `Monitor\\LGD07AD`. The matching
Surface panel package installs a UMDF lower filter, while `ACPI\\MSHW0380` is
handled by Surface Display Hardware Driver with Windows Directed Fx enabled.
The extracted binaries contain separate `DISPLAY OFF` and `DISPLAY ON`
handlers, flush display initialization work on monitor-off, and expose a PSR
control command. Qualcomm's display package also carries eDP power-timing and
PMIC PWM parameters, including PWM glitch removal.

This differs from the unmodified Linux DRM disable path, which disables the
backlight, unprepares the panel, pushes an idle pattern, tears down the eDP
link and PHY, and drops runtime-PM references. On this machine that full path
causes an immediate hardware reset when the desktop turns the display off.

The Surface DT therefore opts into an experimental conservative blanking path:

- the backlight is disabled normally;
- the panel remains prepared;
- the eDP controller and PHY retain their runtime-PM references;
- PSR is used when advertised by the panel, otherwise only the stream is
  idled and restarted;
- re-enable does not acquire duplicate runtime-PM references.

The policy is scoped by `qcom,keep-edp-active-on-blank` and
`keep-panel-prepared-on-disable`; other boards retain the upstream behavior.
It intentionally favors display-off stability over maximum idle power saving.
