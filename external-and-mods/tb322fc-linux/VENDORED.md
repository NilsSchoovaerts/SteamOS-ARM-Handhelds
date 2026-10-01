# Vendored from tb322fc-linux

Snapshot `tb322fc-linux-20260929171628` of
https://github.com/h0cheung/tb322fc-linux (GPL-3.0, see LICENSE), reduced to
what the SteamOS TB322FC target uses. Layout is unchanged so its own scripts
run unmodified from this directory:

| Kept | Used for |
|---|---|
| `sources.json` | kernel (h0cheung/tb322fc-linux-kernel @ 09e22021, tree a00fb035), wireless-regdb |
| `configs/` | kernel.config, cmdline.txt, initramfs.list, busybox.config, AVB test key |
| `initramfs/init` | rootfs handoff (GPT name `rootfs`) |
| `firmware.json`, `scripts/import-firmware.py`, `scripts/ci/firmware-bundle.py` | 82 firmware files by SHA256 |
| `inputs/audio/`, `scripts/build-topology.sh` | AudioReach topology |
| `scripts/build-boot.sh`, `scripts/ci/build-kernel.sh`, `tools/avbtool`, `packages/als-bridge` | Image + DTB + boot.img + modules |
| `rootfs/` | UCM (installed by tb322fc-overlay), sensor and camera units |
| `patches/` | hexagonrpc / iio-sensor-proxy / libcamera (sensor stack, optional) |
| `packages/gamescope-armada/0023…`, `packages/gamescope-session/0001…` | references for the gamescope/session changes |

Left out: the Arch Linux ARM rootfs pipeline and the ArmadaOS packages (the
SteamOS userspace replaces them). External-and-mods/kernel-tb322fc/build.sh
drives these scripts; nothing here was edited.
