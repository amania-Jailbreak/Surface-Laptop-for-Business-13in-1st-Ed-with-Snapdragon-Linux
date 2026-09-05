# Drivers and firmware

The kernel configuration keeps the hardware-critical Qualcomm and Surface
paths enabled, including:

- Qualcomm GENI serial and serdev;
- USB DWC3/QCOM, xHCI, USB storage and UAS;
- WCN7850 Wi-Fi and Bluetooth HCI UART/QCA;
- Qualcomm APR/GPR, AudioReach, LPASS and SoundWire;
- WSA884x audio codec support;
- EFI stub and compressed initramfs support.

The exact settings are recorded in `drivers/kernel-config.md`. Modules needed
before the real root is available are listed in `drivers/module-manifest.txt`.
Firmware names and hashes are in `drivers/firmware-manifest.json`.

The WCN7850 Wi-Fi and Bluetooth firmware files are hardware inputs, not
operating-system packages. Check the vendor redistribution terms before
putting them on a public hosting service.
