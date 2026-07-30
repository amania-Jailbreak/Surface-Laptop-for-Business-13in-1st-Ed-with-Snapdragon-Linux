# Firmware

Firmware binaries are not included.

The tested initramfs contained:

```text
/lib/firmware/qcom/gen71500_sqe.fw
/lib/firmware/qcom/gen71500_gmu.bin
/lib/firmware/qcom/gen71500_zap.mbn
/lib/firmware/qcom/x1p42100/Microsoft/Surface12/qcdxkmsucpurwa.mbn
```

The last file is currently referenced using the Surface Pro 12 directory
because it was the available X1P42100 Microsoft firmware during bring-up. It
worked on the tested Laptop, but this path is provisional and should be
replaced with a firmware package specific to this product when one becomes
available.

Place the required files under a staging directory preserving the paths above,
then set `FIRMWARE_ROOT` when building the initramfs:

```bash
export FIRMWARE_ROOT="$PWD/firmware"
./scripts/build-initramfs.sh ../busybox ../linux out/initramfs.cpio.gz
```

Obtain firmware from an appropriately licensed vendor package or from the
matching device installation. Do not commit firmware blobs unless their
redistribution terms explicitly allow it.
