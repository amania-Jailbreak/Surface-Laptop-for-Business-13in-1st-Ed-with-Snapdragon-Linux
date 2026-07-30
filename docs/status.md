# Bring-up status

Tested with Linux commit `fc02acf6ac0ccde0c805c2daa9148683cdd01ba8`
(Linux 7.2-rc5 development tree) on 2026-07-30.

| Component | Status | Notes |
|---|---|---|
| UEFI boot | Working | GRUB ARM64 EFI, Secure Boot disabled |
| CPU | Working | All 8 cores online |
| Memory | Working | 16 GiB test machine |
| Generic timer/GIC | Working | Uses upstream `purwa.dtsi` |
| BusyBox initramfs | Working | RAM-only shell |
| USB host | Working | `usb_mp` |
| Internal keyboard | Working | ELAN USB composite device |
| Internal touchpad | Working | ELAN USB composite device |
| TLMM/GPIO | Working | Normal deferred probing |
| GPU | Working | MSM DRM render node and ioctl smoke test |
| Internal eDP | Working | 1920×1280 panel through DP3 |
| Backlight | Working | PMK8550 PWM, 200 Hz |
| Ubuntu ARM64 rootfs on USB | Experimental | `LABEL=UBUNTU_ROOT` + BusyBox `switch_root` |
| UFS | Disabled | Board-specific validation still required |
| Wi-Fi/Bluetooth | Not tested | Firmware and PCIe path not integrated |
| Audio | Disabled | Speaker protection must be validated first |
| Camera | Disabled | Not investigated |
| Battery/charging | Not tested | Not ready for normal laptop use |
| Suspend/resume | Not tested | Not ready for normal laptop use |
| External display | Not tested | USB-C retimer topology is incomplete |

## Removed bring-up workarounds

The working configuration does not require:

- `maxcpus=1` or `nr_cpus=1`
- a patched deferred-probe core
- manual writes to `drivers_probe`
- skipping TLMM probing
- deleting SCM interconnect properties
- disabling the SBSA watchdog

`clk_ignore_unused`, `pd_ignore_unused`, and `regulator_ignore_unused` remain
available in the verbose GRUB entry for diagnosis, but are not used by the
normal entry.
