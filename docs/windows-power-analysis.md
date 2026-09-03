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
