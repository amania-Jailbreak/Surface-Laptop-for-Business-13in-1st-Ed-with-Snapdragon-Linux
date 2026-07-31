# Ubuntu ARM64をUSBから起動する

既知の動作版BusyBoxを残したまま、同じUSB上のext4 rootfsへ切り替える手順です。
内蔵UFSには書き込みません。実機ではGRUBが不安定だったため、Ubuntu Desktopは
systemd-stub UKIから直接起動します。

## USBパーティション

対象デバイス名を必ず確認してから作業します。

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

以下はUSBが`/dev/sdX`の場合の例です。`/dev/sdX`を実際のUSBデバイスへ置き換えてください。
この操作は対象デバイスの内容を消去します。

```bash
USB=/dev/sdX

sudo parted -s "$USB" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 512MiB \
  set 1 esp on \
  mkpart UBUNTU_ROOT ext4 512MiB 100%

sudo mkfs.fat -F32 -n SURFACEBOOT "${USB}1"
sudo mkfs.ext4 -L UBUNTU_ROOT "${USB}2"
```

FAT32パーティションへ、`out/usb-root`の中身をコピーします。

```bash
sudo mkdir -p /mnt/surface-efi
sudo mount "${USB}1" /mnt/surface-efi
sudo cp -a out/usb-root/. /mnt/surface-efi/
sync
sudo umount /mnt/surface-efi
```

## Ubuntu ARM64 rootfs

Ubuntu Baseまたは同等のARM64 rootfsを用意し、ext4パーティションへ展開します。
デスクトップ用ISOをそのままコピーする方式ではありません。

手元のUbuntu Desktop ARM64 ISOから作る場合は、`squashfs-tools`、`fakeroot`、
`7z`をホストへ入れて、次を実行します。ISO内のベース、Desktop追加、Live追加の
3レイヤーを順番に重ねます。

```bash
./scripts/extract-ubuntu-rootfs.sh \
  ../ubuntu-26.04-desktop-arm64.iso \
  ./out/ubuntu-rootfs.tar
```

生成したtarballをext4パーティションへ展開します。

```bash
sudo mkdir -p /mnt/ubuntu-root
sudo mount "${USB}2" /mnt/ubuntu-root

# Ubuntu Desktop ARM64 ISOから生成したrootfs tarball
sudo tar --numeric-owner -xpf out/ubuntu-rootfs.tar \
  -C /mnt/ubuntu-root

sudo mkdir -p /mnt/ubuntu-root/etc
sudo cp /etc/resolv.conf /mnt/ubuntu-root/etc/resolv.conf 2>/dev/null || true
sync
sudo umount /mnt/ubuntu-root
```

rootfsには少なくとも次が必要です。

```text
/sbin/init
/bin/sh
/etc
/var
```

## カーネル設定

Ubuntu DesktopではGPU・内蔵画面用ドライバに加えて、Snapのマウントに使う
SquashFS圧縮形式をカーネルへ組み込みます。

```text
CONFIG_DRM=y
CONFIG_DRM_MSM=y
CONFIG_DRM_MSM_DPU=y
CONFIG_DRM_MSM_DP=y
CONFIG_PHY_QCOM_EDP=y
CONFIG_CLK_X1E80100_DISPCC=y
CONFIG_CLK_X1E80100_GPUCC=y
CONFIG_CLK_X1P42100_GPUCC=y
CONFIG_SQUASHFS=y
CONFIG_SQUASHFS_LZO=y
CONFIG_SQUASHFS_XZ=y
CONFIG_SQUASHFS_LZ4=y
```

起動に必要なドライバを`=m`にする場合は、対応するモジュールもinitramfsへ
含める必要があります。初期bring-upでは`=y`を推奨します。

## カーネルとinitramfsの再生成

追加したrootfs用設定を含むカーネルをビルドします。

```bash
JOBS=4 ./scripts/build-kernel.sh ../linux ./out
```

その後、BusyBoxとファームウェアを使ってinitramfsを作ります。

```bash
export FIRMWARE_ROOT="$PWD/firmware"
./scripts/build-initramfs.sh \
  ../busybox \
  ../linux \
  ./out/initramfs.cpio.gz
```

UKIを生成します。`linuxaa64.efi.stub`はARM64版systemd-boot-efiパッケージから
取得できます。

```bash
./scripts/build-uki.sh \
  /path/to/ukify \
  /path/to/linuxaa64.efi.stub \
  ./out/Image \
  ./out/surface-laptop-13.dtb \
  ./out/initramfs.cpio.gz \
  ./out/BOOTAA64.EFI

./scripts/assemble-usb-tree.sh \
  ./out/Image \
  ./out/surface-laptop-13.dtb \
  ./out/initramfs.cpio.gz \
  ./out/BOOTAA64.EFI \
  ./out/usb-root
```

FAT32パーティションの`EFI/BOOT/BOOTAA64.EFI`を更新すると、UEFIから
Ubuntu用UKIが直接起動します。既定では次の指定を使います。

```text
root=LABEL=UBUNTU_ROOT rootfstype=ext4 rootwait rw
```

BusyBox initramfsがUSB rootfsを最大30秒待ち、`/sbin/init`へ切り替えます。
失敗した場合は自動的にBusyBoxシェルへ戻るため、診断を続けられます。

起動に成功するとGDMを経由してUbuntu 26.04 Desktopが内蔵eDPへ表示されます。
GUIが表示されない場合でも、`Ctrl+Alt+F3`でTTYへ切り替えられることがあります。

## トラブルシュート

`Could not mount LABEL=UBUNTU_ROOT`と表示される場合は、次を確認します。

```text
ext4パーティションのラベルがUBUNTU_ROOTか
CONFIG_EXT4_FS=yになっているか
CONFIG_USB_STORAGE=yになっているか
CONFIG_SCSI=yとCONFIG_BLK_DEV_SD=yになっているか
USBが/dev/sdaとして列挙されているか
```

まずBusyBox項目で起動し、次を確認できます。

```sh
cat /proc/partitions
blkid
```
