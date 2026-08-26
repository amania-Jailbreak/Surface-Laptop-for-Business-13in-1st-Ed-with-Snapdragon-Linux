# Changelog

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

## Hardware support baseline

- separated Surface kernel, DTB, firmware, driver, initramfs, and UKI inputs
  from operating-system image construction;
- added neutral current and Bluetooth UKI assembly;
- added explicit Type-C host and WCN7850 DTB verification;
- added artifact hashes and a public-name boundary check.
