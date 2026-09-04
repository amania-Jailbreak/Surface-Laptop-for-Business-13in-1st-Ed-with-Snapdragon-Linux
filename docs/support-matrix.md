# Support matrix

This table records hardware results for the exact Surface Laptop for Business
13-inch (1st Edition) board. A feature is not marked working merely because
its driver builds.

| Feature | Status | Source / artifact | Notes |
| --- | --- | --- | --- |
| USB-C host and external storage | tested | base DTS, DWC3/QMP config | required for USB-root boot |
| Internal UFS storage | tested on the Proxmox boot path | base DTS, UFS host/PHY config | base DT nodes were disabled and are now enabled for all public variants |
| USB-A and internal HID | tested | base DTS, kernel config | keyboard and touchpad |
| Touchscreen | tested | `touchscreen.dtso` | HID-over-I2C at `0x34` |
| Wi-Fi | tested | WCN7850 firmware manifest | firmware supplied separately |
| Bluetooth | tested | `bluetooth.dtso` | WCN7850 over GENI UART |
| Fingerprint reader | tested with userspace patch | `fingerprint-usb.dtso` | ELAN `04f3:0c9e`; distribution userspace setup required |
| CIFS | enabled | `kernel/config/desktop.config` | loadable module |
| WireGuard | enabled | `kernel/config/desktop.config` | loadable module |
| Waydroid binder/PSI/memfd | enabled | `kernel/config/desktop.config` | host kernel primitives only |
| Internal speaker | partial | audio DT in base DTS | depends on DSP/codec firmware |
| Internal microphone | not working | audio DT | VA capture codec path remains unresolved |
| 3.5 mm jack | experimental | `overlays/experimental/audio-jack.dtso` | excluded from default builds |
| Suspend/resume | unsupported | — | may reboot or lose USB devices |

Release notes should include the tested kernel source revision, DTB variant,
initramfs source, firmware hashes, and the exact target OS command line.
