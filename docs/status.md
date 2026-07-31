# Bring-up status

Tested with Linux commit `fc02acf6ac0ccde0c805c2daa9148683cdd01ba8`
(Linux 7.2-rc5 development tree) on 2026-07-31.

| Component | Status | Notes |
|---|---|---|
| UEFI boot | Working | Direct systemd-stub UKI, Secure Boot disabled |
| GRUB ARM64 EFI | Unstable | May freeze or hard-reset during menu rendering |
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
| Ubuntu 26.04 Desktop ARM64 on USB | Working | GDM/desktop on internal eDP; `LABEL=UBUNTU_ROOT` + BusyBox `switch_root` |
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
available in diagnostic command lines. The current Ubuntu UKI retains them
while more power-domain coverage is validated.

## Ubuntu Desktop milestone

The verified USB configuration uses:

- a FAT32 `SURFACEBOOT` partition containing `EFI/BOOT/BOOTAA64.EFI`
- an ext4 partition labeled `UBUNTU_ROOT`
- a systemd-stub UKI containing the ARM64 kernel, board DTB and BusyBox initramfs
- built-in MSM DRM, DPU, DP, eDP PHY, GPUCC and SquashFS decompression support

GDM and the Ubuntu 26.04 desktop render on the internal 1920×1280 eDP panel.
The built-in keyboard and touchpad remain usable after `switch_root`.
