# Required kernel settings

The full starting configuration is `kernel/config/base.config`. The build also
merges `kernel/config/desktop.config`, which enables common desktop, removable
storage, network, VPN, and filesystem support as modules where possible.

The following settings are the hardware-facing subset that must remain available:

```text
CONFIG_ARCH_QCOM=y
CONFIG_SERIAL_QCOM_GENI=y
CONFIG_SERIAL_DEV_BUS=y
CONFIG_SERIAL_DEV_CTRL_TTYPORT=y
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_USB_DWC3_DUAL_ROLE=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PLATFORM=y
CONFIG_DRM_AUX_BRIDGE=y
CONFIG_PHY_QCOM_QMP_COMBO=y
CONFIG_PHY_QCOM_USB_SNPS_FEMTO_V2=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
CONFIG_EXT4_FS=y

# Internal Qualcomm UFS storage. The QCOM host and QMP PHY may be modules;
# the Surface initramfs builder includes them and their generated dependencies.
CONFIG_SCSI_UFSHCD=y
CONFIG_SCSI_UFSHCD_PLATFORM=y
CONFIG_SCSI_UFS_QCOM=m
CONFIG_PHY_QCOM_QMP_UFS=m
CONFIG_BT=m
CONFIG_BT_HCIUART=m
CONFIG_BT_HCIUART_SERDEV=y
CONFIG_BT_HCIUART_H4=y
CONFIG_BT_HCIUART_QCA=y
CONFIG_BT_HCIUART_BCM=y
CONFIG_REGMAP_SOUNDWIRE=y
CONFIG_SND_SOC_QDSP6=y
CONFIG_SND_SOC_QDSP6_APM=y
CONFIG_SND_SOC_QDSP6_APM_DAI=y
CONFIG_SND_SOC_QDSP6_APM_LPASS_DAI=y
CONFIG_SND_SOC_QDSP6_PRM=y
CONFIG_SND_SOC_WSA884X=y
CONFIG_ANDROID_BINDER_IPC=y
# CONFIG_ANDROID_BINDER_IPC_RUST is not set
CONFIG_ANDROID_BINDERFS=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_PSI=y
CONFIG_MEMFD_CREATE=y
CONFIG_EFI_STUB=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
```

The USB-root path is intentionally built in. In particular, DWC3 must not
wait for the QMP combo PHY or its AUX bridge dependency to be loaded from the
same USB disk that DWC3 is responsible for discovering. Optional hardware and
desktop features may remain modules and are listed in
`drivers/module-manifest.txt` when the initramfs needs them.

The desktop fragment deliberately leaves legacy SMB1, CIFS debug output, and
WireGuard debug output disabled. A normal build must contain at least:

```text
CONFIG_CIFS=m
CONFIG_WIREGUARD=m
CONFIG_NET_UDP_TUNNEL=m
CONFIG_NLS_UTF8=m
```

The fragment is merged with the source tree's Kconfig database and then passed
through `olddefconfig`. This keeps the same repository usable with nearby
kernel releases: a symbol that does not exist in an older release is resolved
by that release's Kconfig rules instead of being copied into the final config.
