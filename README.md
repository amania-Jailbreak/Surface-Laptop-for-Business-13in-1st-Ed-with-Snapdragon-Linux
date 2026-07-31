# Linux on Surface Laptop 13-inch (X1P42100)

Microsoft **Surface Laptop for Business 13in 1st Ed with Snapdragon**
(SKU suffix 2095) を、Device Treeを使ってmainline系ARM64 Linuxで起動するための
初期サポートです。

現在、8 CPUコア、GPU、内蔵eDP画面、PWMバックライト、USB、内蔵キーボード、
タッチパッド、BusyBox initramfs、USB上のUbuntu 26.04 Desktop ARM64まで
実機で動作しています。

> This repository contains early Device Tree and bring-up tooling for the
> Microsoft Surface Laptop 13-inch with Qualcomm X1P42100.

## 対応状況

| 機能 | 状態 |
|---|---|
| ARM64 UEFI / UKI直接起動 | ✅ |
| ARM64 GRUB | ⚠️ 実機では不安定 |
| CPU 8コア | ✅ |
| USBホスト | ✅ |
| 内蔵キーボード・タッチパッド | ✅ |
| Adreno GPU / MSM DRM | ✅ |
| 内蔵eDP 1920×1280 | ✅ |
| PWMバックライト | ✅ |
| Ubuntu 26.04 Desktop ARM64（USB） | ✅ |
| UFS内蔵ストレージ | 🚧 無効 |
| Wi-Fi / Bluetooth | 未検証 |
| バッテリー・充電 | 未検証 |
| サスペンド | 未検証 |
| 内蔵オーディオ | 無効 |

詳細は [docs/status.md](docs/status.md) を参照してください。

## 対象機種

```text
Surface Laptop for Business 13in 1st Ed with Snapdragon
Snapdragon X Plus X1P42100
System SKU suffix: 2095
```

Surface Laptop 7の13.8/15インチ版やSurface Pro 12とは別機種です。
それらのDTBをそのまま使用しないでください。

## リポジトリ構成

```text
.
├── boot/
│   └── grub.cfg
├── configs/
│   └── kernel.fragment
├── docs/
│   ├── firmware.md
│   ├── hardware.md
│   └── status.md
├── initramfs/
│   ├── devnodes.list
│   ├── gpu-diag.sh
│   ├── gpu-smoke.c
│   └── init
├── kernel/arch/arm64/boot/dts/qcom/
│   └── x1p42100-microsoft-surface-laptop-13.dts
└── scripts/
    ├── assemble-usb-tree.sh
    ├── build-grub-efi.sh
    ├── build-initramfs.sh
    ├── build-kernel.sh
    ├── build-uki.sh
    └── extract-ubuntu-rootfs.sh
```

カーネル、DTB、EFI、initramfs、ファームウェア、ACPIダンプなどの生成物は
Gitへ含めません。

## 検証環境

- Linux commit:
  `fc02acf6ac0ccde0c805c2daa9148683cdd01ba8`
- Kernel version: Linux 7.2-rc5 development tree
- Cross compiler: `aarch64-linux-gnu-gcc`
- Boot method: systemd-stub UKI (`BOOTAA64.EFI`)
- Test date: 2026-07-31

新しいカーネルではDTSやKconfigシンボルの調整が必要になる場合があります。

## ビルド環境

Ubuntu/Debian系x86-64ホストの例です。

```bash
sudo apt update
sudo apt install -y \
  git build-essential bc bison flex \
  libssl-dev libelf-dev dwarves \
  device-tree-compiler \
  gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
  libc6-dev-arm64-cross cpio gzip rsync \
  grub-common grub2-common systemd-ukify
```

カーネルソースを用意します。

```bash
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
```

### 1. カーネルとDTB

```bash
JOBS=4 ./scripts/build-kernel.sh ../linux ./out
```

生成物：

```text
out/Image
out/surface-laptop-13.dtb
```

ネットワーク共有やメモリの少ない環境では、`JOBS=2`または`JOBS=1`を推奨します。

### 2. BusyBox

BusyBoxをARM64静的リンクでビルドします。

```bash
git clone https://git.busybox.net/busybox
cd busybox
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
yes "" | make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- oldconfig
make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cd ..
```

BusyBoxの版によっては`olddefconfig`が無いため、上の例では`oldconfig`を使います。

### 3. ファームウェア

必要なファームウェアはこのリポジトリに含まれません。
[docs/firmware.md](docs/firmware.md) の構成で配置してください。

```bash
export FIRMWARE_ROOT="$PWD/firmware"
./scripts/build-initramfs.sh \
  ../busybox \
  ../linux \
  ./out/initramfs.cpio.gz
```

### 4. ARM64 UKI（推奨）

この機種ではGRUBの描画中やメニュー操作中にハードリセット・フリーズが
発生したため、Ubuntu起動にはsystemd-stubによる直接UKIを使用します。

ARM64版`linuxaa64.efi.stub`、カーネル、DTB、initramfsを1つの
`BOOTAA64.EFI`へまとめます。

```bash
./scripts/build-uki.sh \
  /path/to/ukify \
  /path/to/linuxaa64.efi.stub \
  ./out/Image \
  ./out/surface-laptop-13.dtb \
  ./out/initramfs.cpio.gz \
  ./out/BOOTAA64.EFI
```

既定のカーネルコマンドラインはUSB上の
`LABEL=UBUNTU_ROOT`をroot filesystemとして使用します。

### 5. ARM64 GRUB EFI（BusyBox診断用・非推奨）

x86-64ホストではARM64版GRUBモジュールを展開し、そのディレクトリを指定します。

```bash
./scripts/build-grub-efi.sh \
  /path/to/grub-arm64/usr/lib/grub/arm64-efi \
  ./out/BOOTAA64.EFI
```

成功時、`file`はAArch64 EFI applicationと表示します。

### 6. USB用ツリー

```bash
./scripts/assemble-usb-tree.sh \
  ./out/Image \
  ./out/surface-laptop-13.dtb \
  ./out/initramfs.cpio.gz \
  ./out/BOOTAA64.EFI \
  ./out/usb-root
```

FAT32 USBのルートへ`out/usb-root`の**中身**をコピーします。

```text
USB
├── EFI/BOOT/BOOTAA64.EFI
└── boot
    ├── Image
    ├── initramfs.cpio.gz
    └── surface-laptop-13.dtb
```

Ubuntu ARM64をUSB上のext4 rootfsから起動する手順は
[docs/ubuntu-usb.md](docs/ubuntu-usb.md) にあります。UKI内のinitramfsが
`LABEL=UBUNTU_ROOT`を検出し、自動的に`switch_root`します。

## 起動

現在のEFIは未署名です。検証時はSecure Bootを無効化し、Windowsの回復画面から
USB Storageを選択します。

UEFI removable-media fallback pathの`EFI/BOOT/BOOTAA64.EFI`から直接起動します。
Ubuntu Desktop用にはGRUBメニューを経由しません。

詳細ログと自動診断が必要なら次を選びます。

```text
Surface Laptop 13 X1P42100 - verbose diagnostics
```

BusyBox verbose診断版は、起動USBの書き込み可能なVFATパーティションを自動検出し、
ルートへ次のファイルを保存します。

```text
gpu-diagnosis.txt
```

## 内蔵画面の実装

内蔵画面はDP3を使用します。ACPI解析から次をDevice Treeへ移植しました。

- eDPパネル電源: TLMM GPIO29
- 電源投入後待機: 150 ms
- バックライト: PMK8550 PWM channel 0
- PWM周期: 5,000,000 ns（200 Hz）
- DP PHY: `0x0aec5a00`
- パネル: LGD07AD / 1920×1280 @ 60 Hz

画面が`aec5a00.phy not ready`で止まる場合は、特に
`CONFIG_PHY_QCOM_EDP=y`を確認してください。`=m`のままモジュールを
initramfsへ入れないと、DP3はbindしません。

詳しい根拠は [docs/hardware.md](docs/hardware.md) にあります。

## 既知の制限

- UFSは安全のためDTSで無効です。
- GRUBは実機上でフリーズまたはハードリセットする場合があります。Ubuntuには
  直接UKI起動を推奨します。
- Wi-Fi、Bluetooth、カメラ、充電、サスペンドは未完成です。
- 内蔵オーディオは有効にしていません。
- GPU zap firmwareは現在Surface Pro 12用X1P42100ファイルを参照しています。
- 完成したディストリビューション用DTBではなく、bring-up段階です。

内蔵スピーカー保護が確認できるまで、スピーカーを有効化しないでください。

## 安全な検証

- Windowsと回復キーを残してください。
- 最初はRAM上のBusyBoxだけを起動してください。
- 内蔵UFSへ書き込まないでください。
- 学校・会社管理端末では、UEFI変更やUSB起動の許可を先に取得してください。
- 常に動作済みのImage・DTB・initramfs・BOOTAA64.EFIを別に保存してください。

## Contributing

実機テスト結果には、機種名、SKU、カーネルcommit、DTB、該当dmesgを添えてください。
UUID、BitLocker回復キー、シリアル番号、MACアドレスなどは公開前に削除してください。

Device Treeをmainlineへ提出する場合は、このリポジトリの履歴をそのまま送らず、
Linux kernel coding style、DT binding、`make dtbs_check`に合わせてパッチを
作り直してください。

## License

- Device Tree: BSD-3-Clause
- Repository scripts and original diagnostic source: MIT
- Linux and BusyBox are not vendored and retain their own licenses

See [LICENSES](LICENSES/).
