#!/usr/bin/env bash
# Copy the firmware directories tb322fc-linux needs from YOUR OWN Y700 Gen 4
# running Android (USB debugging on). Read-only on the tablet.
#   pull-firmware.sh [output-dir]      (default: tb322fc-work/stock)
# /vendor/firmware_mnt/image usually needs root (Magisk "su"); without root
# whatever is readable is copied and the importer lists what is missing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-${STEAMOS_WORK:-${ROOT}/tb322fc-work}/stock}"
command -v adb >/dev/null || { echo "ERROR: adb missing (sudo apt install adb)" >&2; exit 1; }
adb get-state >/dev/null || { echo "ERROR: no tablet over adb (USB debugging on, cable in, allow the PC)" >&2; exit 1; }
mkdir -p "$OUT"
DIRS="/vendor/firmware /vendor/firmware_mnt/image /odm/etc/wifi/peach"
if adb shell 'su -c id' 2>/dev/null | grep -q 'uid=0'; then
  echo "root available: copying with su"
  adb exec-out "su -c 'tar -cf - $DIRS 2>/dev/null'" | tar -xf - -C "$OUT" || true
else
  echo "no root: copying what Android lets adb read"
  adb exec-out "tar -cf - $DIRS 2>/dev/null" | tar -xf - -C "$OUT" || true
fi
echo "copied into $OUT:"; du -sh "$OUT"/* 2>/dev/null || true
echo "next: external-and-mods/kernel-tb322fc/build.sh firmware $OUT"
