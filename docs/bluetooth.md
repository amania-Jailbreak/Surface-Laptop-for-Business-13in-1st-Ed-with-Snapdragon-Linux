# Bluetooth bring-up

The board exposes Bluetooth through the Qualcomm GENI UART rather than a USB
HCI device. The DT overlay creates the serdev child (WCN7850 on UART
`serial@a98000`, max 3.2 Mbaud, enable GPIO 116 from the board PMU).

## Two supported ways to load the stack

1. Distribution module tree (verified 2026-08-25). Install the kernel modules
   and the QCA firmware in the target root filesystem:

   ```
   /lib/modules/<release>/kernel/net/bluetooth/bluetooth.ko
   /lib/modules/<release>/kernel/drivers/bluetooth/{btbcm,btqca,hci_uart}.ko
   /lib/firmware/qca/hmtbtfw20.tlv
   /lib/firmware/qca/hmtnv20.*
   ```

   udev loads them automatically when the serdev device probes; no initramfs
   changes are needed because the controller appears after the root pivot.

2. Early initramfs hook. For distributions whose initramfs must provide HCI
   before the pivot (for example network-block root), use
   `initramfs/scripts/` with the same module list plus firmware.

After boot, check:

```sh
rfkill list
bluetoothctl list
dmesg | grep -Ei 'bluetooth|hci|qca|wcn7850|serdev'
```

If the controller is present but no adapter is listed, capture the UART,
firmware, module, and power-sequencer lines together. Do not infer a DTB
failure from a missing `bluetoothctl` command alone.
