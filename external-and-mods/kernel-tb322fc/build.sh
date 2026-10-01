#!/usr/bin/env bash
# Build the Lenovo Legion Tab Y700 Gen 4 (TB322FC, "elden", SM8750) kernel
# with tb322fc-linux's own, unmodified scripts (external-and-mods/tb322fc-linux):
#   Linux 7.2 from h0cheung/tb322fc-linux-kernel @ the commit in sources.json,
#   configs/kernel.config, DTB qcom/sm8750-lenovo-elden.dtb + initramfs +
#   early firmware embedded in Image, Android v4 boot.img (fastboot boot).
#
#   build.sh firmware <stock-dir>...   import firmware from your own Android
#   build.sh [build]                   kernel, boot.img, modules -> KERNEL_OUT
#
# KERNEL_OUT layout (read by scripts/apply-overlays-sm8750.sh, tb322fc mode):
#   boot/boot.img  kernel.release  modules/<release>/  firmware/  SHA256SUMS
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
TB="${ROOT}/external-and-mods/tb322fc-linux"
WORKDIR="${STEAMOS_WORK:-${ROOT}/tb322fc-work}"
KOUT="${KERNEL_OUT:-${WORKDIR}/kernel-tb322fc}"

log() { printf '[kernel-tb322fc] %s\n' "$*"; }
die() { printf 'ERROR: [kernel-tb322fc] %s\n' "$*" >&2; exit 1; }

fetch_sources() {
  local c
  for c in kernel wireless-regdb; do
    if [[ -d "${TB}/sources/${c}" ]]; then
      log "sources/${c} present"
    else
      (cd "$TB" && python3 scripts/fetch-sources.py "$c")
    fi
  done
}

firmware_ok() {
  python3 "${TB}/scripts/ci/firmware-bundle.py" verify "${TB}/inputs/firmware" >/dev/null 2>&1
}

cmd_firmware() {
  [[ $# -ge 1 ]] || die "usage: $0 firmware <extracted-stock-dir>..."
  fetch_sources
  (cd "$TB" && python3 scripts/import-firmware.py "$@" sources/wireless-regdb)
  (cd "$TB" && bash scripts/build-topology.sh)
  firmware_ok || die "firmware set incomplete after import (see above)"
  log "firmware complete: ${TB}/inputs/firmware"
}

cmd_build() {
  fetch_sources
  if [[ ! -f "${TB}/inputs/firmware/qcom/sm8750/Lenovo-Y700-Gen4-tplg.bin" ]] \
     && [[ -d "${TB}/inputs/firmware" ]]; then
    (cd "$TB" && bash scripts/build-topology.sh)
  fi
  firmware_ok || die "firmware missing or wrong. First run: $0 firmware <stock-dir> (docs/TB322FC.md)"
  log "building kernel, boot.img and modules (tb322fc-linux scripts/ci/build-kernel.sh)"
  (cd "$TB" && JOBS="${JOBS:-$(nproc)}" bash scripts/ci/build-kernel.sh)

  local A="${TB}/artifacts" rel
  rel="$(cat "$A/kernel.release")"
  [[ "$rel" =~ ^[A-Za-z0-9._+-]+$ ]] || die "bad kernel release '$rel'"
  log "staging ${rel} -> ${KOUT}"
  rm -rf "$KOUT"
  mkdir -p "$KOUT/boot" "$KOUT/modules" "$KOUT/firmware"
  cp -a "$A/boot.img" "$KOUT/boot/boot.img"
  cp -a "$A/sm8750-lenovo-elden.dtb" "$A/kernel.config" "$A/SHA256SUMS" "$KOUT/"
  printf '%s\n' "$rel" >"$KOUT/kernel.release"
  local t; t="$(mktemp -d)"
  tar -xzf "$A/kernel-modules.tar.gz" -C "$t"
  mv "$t/usr/lib/modules/$rel" "$KOUT/modules/$rel"
  rm -rf "$t"
  # Only the files listed in firmware.json, never other stock content.
  python3 - "${TB}/firmware.json" "${TB}/inputs/firmware" "$KOUT/firmware" <<'PY'
import json, shutil, sys
from pathlib import Path
manifest, src, dst = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
for row in json.loads(manifest.read_text())["files"]:
    target = dst / row["path"]
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src / row["path"], target)
    target.chmod(0o644)
PY
  log "done: ${KOUT}/boot/boot.img (kernel ${rel})"
}

case "${1:-build}" in
  firmware) shift; cmd_firmware "$@" ;;
  build) cmd_build ;;
  -h|--help) sed -n '2,13p' "$0" ;;
  *) die "unknown command: $1" ;;
esac
