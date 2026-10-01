# Lenovo Legion Tab Y700 Gen 4 (TB322FC)

**Status: experimental, not boot-tested.** The source tree is complete and
statically checked; nobody has booted this SteamOS image on a Y700 yet.

## Hardware

| | |
|---|---|
| Model / codename | TB322FC, `elden` |
| SoC / GPU | Snapdragon 8 Elite SM8750 / Adreno 830 (Turnip, zink) |
| Kernel | Linux 7.2, h0cheung/tb322fc-linux-kernel @ `09e22021` (tb322fc-linux `sources.json`) |
| DTB | `qcom/sm8750-lenovo-elden.dtb`, model "Lenovo Legion Y700 Gen4", embedded in `Image` |
| Display | CSOT PP8807HB1-1 / NT36536, **1904x3040 portrait-native** DSI (no EDID), 24/30/40/60/90/120/144/165 Hz; gamescope and KWin rotate it to landscape |
| Touch | NT36536 on SPI (firmware built into the kernel) |
| Audio | AW88461 speakers + WCD9395 mics, AudioReach topology + UCM from tb322fc-linux |
| Wi-Fi / BT | ath12k PEACH / QCA UART, stock firmware |
| Fan | none in the DTS; kernel thermal zones only (no fan daemon) |

What differs from the Odin 3 target (`SM8750_DEVICE=tb322fc` in
`scripts/apply-overlays-sm8750.sh`): own kernel/boot.img instead of ROCKNIX,
stock-matched firmware, `tb322fc-overlay/` instead of `sm8750-overlay/` (no
odin3d, InputPlumber pad, forced rotation, AYN UCM or Odin Steam config), one
root partition named `rootfs` instead of BOOT/root/home on microSD.

## Build (Linux PC, x86_64 or arm64)

Host packages (Debian/Ubuntu names): `git python3 build-essential curl bzip2
flex bison bc pkg-config libssl-dev libelf-dev gcc-aarch64-linux-gnu
libc6-dev-arm64-cross clang lld llvm mkbootimg m4 alsa-utils dwarves kmod
squashfs-tools rsync gdisk e2fsprogs uuid-runtime adb fastboot`.

```bash
# 1. firmware from your own tablet (Android, USB debugging; root for full set)
external-and-mods/kernel-tb322fc/pull-firmware.sh
# 2. gamescope with the TB322FC touch fix (needs a Frame rootfs with meson+gcc)
scripts/build-gamescope-in-rootfs.sh <frame-rootfs> /work/gamescope-build
# 3. everything else
GAMESCOPE_BUILD=/work/gamescope-build ./make-steamos-tb322fc.sh --firmware tb322fc-work/stock
```

Optional: `MESA_STACK=` from `scripts/build-mesa.sh` (same as the Odin 3).
Output: `tb322fc-work/out/boot.img`, `steamos-tb322fc-usb.img`, `SHA256SUMS`.

## Firmware

82 files listed with SHA256 in `external-and-mods/tb322fc-linux/firmware.json`,
found by checksum in the copies of `/vendor/firmware`,
`/vendor/firmware_mnt/image` and `/odm/etc/wifi/peach`. `regulatory.db*` come
from wireless-regdb, the audio topology is generated. Nothing is imported
unless the whole set matches. Firmware is not in this repository.

## Boot test (non-destructive)

Bootloader must be unlocked (Lenovo, wipes Android data once). Nothing is
flashed: `fastboot boot` runs the image once; a normal reboot returns to Android.

```bash
sudo dd if=tb322fc-work/out/steamos-tb322fc-usb.img of=/dev/sdX bs=4M status=progress conv=fsync
# tablet: power off, hold Volume Down + Power -> fastboot, USB cable to the PC
fastboot boot tb322fc-work/out/boot.img
```

The initramfs waits ~60 s for a partition whose GPT name is `rootfs` and makes
every other disk read-only (UFS included). Plug the USB drive into the second
USB-C port, or swap the PC cable for the drive right after `fastboot boot`.
If the UFS already has a partition named `rootfs` the boot stops (ambiguous).
First boot: up to a few minutes of black screen while Steam starts.

## Known limitations

- Not boot-tested; USB-host rootfs on the Y700 is untested by tb322fc-linux too.
- Sensors (rotation, light) need the native hexagonrpc/libssc/iio-sensor-proxy
  build plus your calibration data; units are staged in
  `/usr/share/steamos-tb322fc/sensors/`, not enabled.
- Steam performance overlay (mangoapp) off, as on the Odin 3 (`GAMESCOPE_MANGOAPP`).
- tb322fc-linux's newer Mesa a8xx fixes are not in the 26.2.3 stack.
- Battery reporting / charger wake: limits of the tb322fc kernel apply.
- The topology hash expects alsatplg 1.2.15.x; an older `alsa-utils` makes the
  firmware check fail.
