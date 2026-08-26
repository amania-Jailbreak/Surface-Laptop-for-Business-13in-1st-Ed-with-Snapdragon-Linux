# Changelog

## 2026-08-26 - experimental fingerprint USB enablement

- identified the power-button reader from the Windows driver set as ELAN 667
  `04f3:0c9e` (WBF/ESS Match-on-Chip);
- mapped its Windows `QCOM0D09` USB host to DT node `usb@a200000`;
- added a separate overlay and fingerprint UKI target without changing the
  hardware-tested default boot configuration;
- enabled the controller's dedicated `phy@88e0000` after hardware testing
  showed DWC3 core registration fails while that PHY remains disabled;
- documented the remaining USB-enumeration and libfprint validation work.

## 2026-08-26 - touchscreen support

- added the hardware-tested `MSHW0468` HID-over-I2C touchscreen at address
  `0x34` on the GENI controller at `0x00a80000`;
- corrected the board-specific HID descriptor register to `0`, as reported by
  the Windows ACPI `_DSM` and confirmed by a direct descriptor read;
- verified touchscreen `1FD2:4001`, WCN7850 Bluetooth, and both USB-C host
  controllers in the same boot;
- made the touchscreen overlay part of both generated DTBs and added explicit
  build-time validation for the descriptor address;
- fixed the flattened public-repository path handling and made `build.sh dtb`
  independent of kernel, initramfs, firmware, and UKI inputs.

## 2026-08-25 - reproducibility pass

- fixed the standalone board DTS so it compiles bit-identical to the measured
  working base DTB (dr_mode=host on all three USB controllers, no role
  switching, dual-role Type-C connectors);
- committed the matching DTB binary so build.sh dtb and the checked-in file
  agree byte for byte;
- removed all private-workspace defaults from build.sh; KERNEL_SOURCE,
  INITRD_BASE and FIRMWARE_SOURCE are now mandatory environment inputs;
- verified on hardware: neutral UKI boots, Type-C storage works, Bluetooth
  loads from the distribution module tree without initramfs injection.

## 2026-08-26 - fingerprint userspace bring-up

- confirmed the ELAN 667 reader (04f3:0c9e) enumerates on the dedicated
  internal USB host and is a Match-on-Chip sensor compatible with the
  upstream elanmoc driver;
- added drivers/libfprint-elanmoc-surface13.patch: registers the PID and
  selects EP3 for cancelable MOC responses on this sensor only, leaving all
  other elanmoc IDs untouched;
- hardware-tested enrollment (nine stages) and verification
  (fprintd-verify reports verify-match) through fprintd with a custom
  libfprint build; no out-of-tree kernel driver or firmware loading needed;
- documented userspace setup and caveats in docs/fingerprint-userspace.md.

## Hardware support baseline

- separated Surface kernel, DTB, firmware, driver, initramfs, and UKI inputs
  from operating-system image construction;
- added neutral current and Bluetooth UKI assembly;
- added explicit Type-C host and WCN7850 DTB verification;
- added artifact hashes and a public-name boundary check.
