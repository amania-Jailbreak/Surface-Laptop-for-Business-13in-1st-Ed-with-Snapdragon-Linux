# Installed Surface KVM investigation — 2026-09-05

## Hardware-test status

The corrected installed boot payload was deployed over SSH and every destination
was verified against its build-side SHA256. A one-shot `surface-el2-kvm` boot was
then requested and `ssh root@surface-pve reboot` executed. SSH did not return
during the initial monitoring period. **EL2/KVM success and the cause of the
hardware reset are not yet established.** Screen feedback is needed before the
next trial. Do not describe this deployment as a successful KVM boot.

Later screen feedback shows Linux boot output and repeated apps-SMMU
`Unhandled context fault` messages, apparently for SID `0x1000` (ADSP).
Thus this trial progressed past GRUB; EL2 status still needs a kernel log.
The user power-cycled back to Ready and SSH returned. Ready reports backlight
2048/4095 and missing ADSP/CDSP firmware. A diagnostic DTB disabling the two
remoteprocs and sound, with an explicit 75% PWM boot brightness, was built as
`build/kvm-audit/ready-el2-no-dsp-bright.dtb`. This sacrifices DSP/audio for
fault isolation; it is not a confirmed root-cause fix. Automatic approval
review rejected its deployment and the immediate brightness adjustment, so
neither action ran. Explicit approval is pending. The original deployed
bundle remained installed while awaiting approval.

The user subsequently authorized the diagnostic deployment. It completed with
all destination hashes verified; the EL2 DTB is
`87c1fd36a4a445c990fa8eb07125f0e7d580c6a4a850184492fc099dc30b33bd`,
146,089 bytes, identical at all three installed paths. Ready brightness was set
to 3500/4095. Backup: `/var/backups/surface-kvm/20260905T132028Z`.
The Ready components were verified unchanged, KVM selected once with
`grub-reboot`, and the second trial reboot executed. See
`deploy-no-dsp.log` and `pre-reboot-no-dsp.txt` under the audit directory.
This trial's outcome must still be checked before claiming the fault is fixed.

The kernel was deliberately reused from the existing build because its bytes
match the working Ready kernel. It was **not recompiled for this trial**.
The initramfs was regenerated on the target for that exact installed kernel
release. The EFI launcher, standalone GRUB, and Ready-derived EL2 DTB were built
locally. No ISO regeneration was used as a substitute for deployment.

## Observed installed layout

| Item | Ready | KVM before correction |
| --- | --- | --- |
| Filesystem | rootfs `/dev/sda3`, GPT 3 | ESP `/dev/sda2`, GPT 2 |
| UUID | `f621d247-7647-4244-aad3-1fffe95afe92` | `584B-B4D4` |
| Mount | `/` | `/boot/efi` |
| Kernel | `/boot/vmlinuz-7.2.0-rc5-surface-laptop-13` | `/EFI/BOOT/surface-kvm-linux` on ESP |
| Kernel SHA256 | `cd7b88de085d1b939e4a75d02997f1d5b7ea4c79a60b156b7201f1ba1d14d60e` | identical to Ready |
| initramfs | `/boot/initrd.img-7.2.0-rc5-surface-laptop-13`, 61,327,361 bytes | `/EFI/BOOT/surface-kvm-initrd.img`, 54,683,394 bytes |
| DTB | `/boot/surface-laptop-13.dtb` | `/EFI/BOOT/surface-laptop-13-el2.dtb`; launcher first installs ESP-root copy |
| GRUB prefix | rootfs `/boot/grub` via UUID wrapper | standalone `(memdisk)/boot/grub` |
| Payload device | fresh UUID lookup | device name inherited through `$cmdpath` |

The ESP partition GUID is `b0a09ff5-fe46-40a1-8be5-067f28fa31fe`.
The ESP-root `surface-kvm-linux` and `surface-kvm-initrd.img` were *different*
older payloads (59,152,896 and 139,131,340 bytes). The terminal GRUB and launcher
copies also differed from the main path. FAT case-insensitivity did not account
for these content differences. Ready's wrapper included the stale `hd1,gpt3`
search hint; the UUID itself was correct.

`efibootmgr -v` could not read Boot#### entries. Mounting efivarfs returned
`Operation not supported`; the running kernel logs `qseecom: untested machine,
skipping`. Therefore Boot#### device paths and firmware BootOrder remain
unverified and unmodified. The selected EFI device paths are now printed by
the launcher, but have not yet been captured from the hardware screen.

## Confirmed software defects corrected

- Standalone GRUB printed successful load messages even when `linux`,
  `devicetree`, or `initrd` failed. It now checks file existence and each result,
  and calls `boot` only after all loads succeed.
- ESP/cmdpath modes ignored explicit payload path options. ESP mode now uses a
  fresh UUID lookup and all modes respect explicit paths. It prints prefix,
  cmdpath, and the resolved payload paths.
- EFI volume selection accepted a lone marker file. It now requires the EFI
  chain's files together, prefers its actual device, and rejects ambiguous
  fallback candidates. The Shell script checks the complete EFI chain and
  selects standalone KVM GRUB when present.
- The fallback service treated the ECV argument as proof of EL2. It now requires
  KVM API version 12 and successful `KVM_CREATE_VM` before clearing fallback.
- The outer GRUB saves Ready fallback to the explicit rootfs grubenv and checks
  that the save succeeds before loading the Secure Launch bridge.

`slbounce` installs an ExitBootServices hook; Secure Launch takes place later,
when Linux's EFI stub exits boot services, **not before the KVM GRUB starts**.
See [upstream slbounce](https://github.com/TravMurav/slbounce). A failed loader
must reboot before attempting Ready, because that EFI session may retain the
hook. A GRUB load-success message cannot establish successful Secure Launch.

Both the deployed TCB (`5dfcd025...0d03d`, 10.0.26100.1742) and slbounce
(`7187f80d...b3996`) matched existing local builds before this work. Rebuilding
the same old safe-EBS patch cannot be claimed as a new fix for the reset.
A no-sweep slbounce comparison build exists only under the ignored audit
directory; it has not been deployed or validated on this laptop.

## Deployment and recovery evidence

Local evidence and binaries are in ignored `build/kvm-audit/`:

- `remote-inventory.txt`, `remote-hashes.txt`, `remote-efi.txt`: original state.
- `dtb-delta.json`: functional Ready-to-EL2 differences; symbols/phandles excluded.
- `bundle/SHA256SUMS`, `bundle/provenance.json`: inputs and kernel provenance.
- `deploy-log.txt`, `pre-reboot.txt`: verified destination hashes, sizes, times.
- `grub-tests.log`: embedded-config, load-failure, and fallback checks.

Target backup: `/var/backups/surface-kvm/20260905T122246Z`.
It contains the overwritten files and `deployed.json`. The normal Ready kernel,
initramfs, DTB, shim, and normal GRUB hashes were verified unchanged.
The original Ready remains the default; KVM was selected for one attempt with
`grub-reboot surface-el2-kvm`. The KVM menu arms Ready for the following boot.

After hardware recovery, check `/proc/cmdline`, `dmesg` for `started at EL2`,
`/dev/kvm`, and a real KVM VM-creation ioctl before setting a persistent KVM
default. If the screen hangs, restart and select `FUSE/PVE ready`; do not repeat
an unknown failing KVM path without collecting its final screen state.

The installer accepts a flat bundle containing the files named in its `mapping`,
SHA256SUMS, and provenance.json. Transfer it with SSH, then run the Python
installer as root on the target. It verifies the target UUIDs, Ready hashes,
matching initramfs version, and TCB hash before backing up and installing.
No large binary, firmware, or credential belongs in Git.
