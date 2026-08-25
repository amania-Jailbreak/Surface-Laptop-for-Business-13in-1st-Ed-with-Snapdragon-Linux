# Required kernel settings

The full starting configuration is `kernel/config/base.config`. The following
settings are the hardware-facing subset that must remain available:

```text
CONFIG_ARCH_QCOM=y
CONFIG_SERIAL_QCOM_GENI=y
CONFIG_SERIAL_DEV_BUS=y
CONFIG_SERIAL_DEV_CTRL_TTYPORT=y
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_USB_DWC3_DUAL_ROLE=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=m
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
CONFIG_EFI_STUB=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
```

The exact `m` versus `y` choice can vary with the kernel release. Any module
needed before root discovery must be listed in
`drivers/module-manifest.txt` and added to the initramfs.
