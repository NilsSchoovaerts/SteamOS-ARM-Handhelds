#!/usr/bin/env bash
# Build SteamOS ARM for the Lenovo Legion Tab Y700 Gen 4 (TB322FC, "elden",
# Snapdragon 8 Elite SM8750, Adreno 830). Output in ${WORKDIR}/out:
#   boot.img                   kernel + elden DTB + initramfs + early firmware
#                              (Android v4). Test with: fastboot boot boot.img
#   steamos-tb322fc-usb.img    GPT disk image, one ext4 partition named
#                              "rootfs" (root with /home inside). Write it to a
#                              USB drive: non-destructive, Android stays as is.
#   rootfs.ext4 (--export-ext4) the same filesystem alone, for an existing UFS
#                              partition named "rootfs" (advanced, not needed)
# The tb322fc-linux initramfs mounts the one partition whose GPT name is
# "rootfs" and makes every other disk read-only. There is no SD slot and no
# ROCKNIX ABL: the stock (unlocked) Lenovo bootloader starts boot.img.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${ROOT}/scripts"
MOD="${ROOT}/external-and-mods"
WORKDIR="${STEAMOS_WORK:-${ROOT}/tb322fc-work}"
R="${STEAMOS_ROOTFS:-${WORKDIR}/rootfs}"
KOUT="${KERNEL_OUT:-${WORKDIR}/kernel-tb322fc}"
OUTDIR="${STEAMOS_TB322FC_OUT:-${WORKDIR}/out}"
IMG="${OUTDIR}/steamos-tb322fc-usb.img"
MNT="${WORKDIR}/.image-mnt"
LOOPDEV=""
FIRMWARE_DIRS=()
SKIP_KERNEL=0
SKIP_DOWNLOAD=0
SKIP_APPLY=0
EXPORT_EXT4=0
AUTO_ROOT=0
if [[ -z "${ROOT_MIB:-}" ]]; then AUTO_ROOT=1; ROOT_MIB=0; fi

STEAMOS_BUILD="${STEAMOS_BUILD:-20260925.6175226}"
STEAMOS_BUNDLE="deckard-${STEAMOS_BUILD}-0.5.0"
STEAMOS_URL="https://steamdeck-images.steamos.cloud/vr/${STEAMOS_BUILD}"
# Reuse an already downloaded Valve rootfs.img (e.g. from the Odin 3 build).
STEAMOS_DL="${STEAMOS_DL:-${WORKDIR}/steamos-${STEAMOS_BUILD}}"
if [[ ! -f "${STEAMOS_DL}/rootfs.img.ok" && -f "${ROOT}/sm8750-work/steamos-${STEAMOS_BUILD}/rootfs.img.ok" ]]; then
  STEAMOS_DL="${ROOT}/sm8750-work/steamos-${STEAMOS_BUILD}"
fi

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
sudo_run() { if [[ "${EUID}" -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

usage() {
  cat <<USAGE
Usage: $0 [options]

  --firmware DIR    Import firmware from your own Android copy first
                    (external-and-mods/kernel-tb322fc/pull-firmware.sh output)
  --skip-kernel     Reuse the kernel already in ${KOUT}
  --skip-download   Reuse the extracted Valve rootfs
  --skip-apply      Do not re-run scripts/apply-overlays-sm8750.sh
  --export-ext4     Also write ${OUTDIR}/rootfs.ext4
  -h, --help

Env: STEAMOS_WORK GAMESCOPE_BUILD (required) MESA_STACK (recommended)
     ROOT_MIB JOBS STEAMOS_DL
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --firmware) FIRMWARE_DIRS+=("$(readlink -f "$2")"); shift ;;
    --skip-kernel) SKIP_KERNEL=1 ;;
    --skip-download) SKIP_DOWNLOAD=1 ;;
    --skip-apply) SKIP_APPLY=1 ;;
    --export-ext4) EXPORT_EXT4=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

ensure_kernel() {
  if [[ ${#FIRMWARE_DIRS[@]} -gt 0 ]]; then
    STEAMOS_WORK="${WORKDIR}" "${MOD}/kernel-tb322fc/build.sh" firmware "${FIRMWARE_DIRS[@]}"
  fi
  if [[ "$SKIP_KERNEL" -eq 1 && -f "${KOUT}/boot/boot.img" && -s "${KOUT}/kernel.release" ]]; then
    log "TB322FC kernel already staged in ${KOUT}"
    return 0
  fi
  STEAMOS_WORK="${WORKDIR}" KERNEL_OUT="${KOUT}" "${MOD}/kernel-tb322fc/build.sh" build
}

# Same Valve RAUC bundle and assembly as make-steamos-sm8750.sh.
ensure_official_rootfs() {
  if [[ -x "${R}/usr/bin/bash" ]]; then
    log "Official rootfs already extracted in ${R}"
    return 0
  fi
  local dl="${STEAMOS_DL}" img sha
  img="${dl}/rootfs.img"
  if [[ ! -f "${img}.ok" ]]; then
    [[ "$SKIP_DOWNLOAD" -eq 1 ]] && die "rootfs missing and --skip-download set"
    command -v unsquashfs >/dev/null || die "unsquashfs missing (sudo apt install squashfs-tools)"
    mkdir -p "${dl}"
    if [[ ! -s "${dl}/bundle/rootfs.img.caibx" ]]; then
      log "Fetching Valve RAUC bundle ${STEAMOS_BUNDLE}"
      curl -fL -o "${dl}/${STEAMOS_BUNDLE}.raucb" "${STEAMOS_URL}/${STEAMOS_BUNDLE}.raucb"
      rm -rf "${dl}/bundle"
      unsquashfs -q -d "${dl}/bundle" "${dl}/${STEAMOS_BUNDLE}.raucb"
    fi
    sha="$(sed -n '/^\[image.rootfs\]/,/^\[/{s/^sha256=//p}' "${dl}/bundle/manifest.raucm")"
    log "Assembling official rootfs.img from casync chunks (sha256 ${sha})"
    python3 "${SCRIPTS}/extract_rootfs.py" \
      --caibx "${dl}/bundle/rootfs.img.caibx" --output "${img}" \
      --store "${STEAMOS_URL}/${STEAMOS_BUNDLE}.castr" \
      --store "https://steamdeck-images.steamos.cloud/vr/chunks.castr" \
      --expected-sha256 "${sha}"
    touch "${img}.ok"
  fi
  log "Unpacking rootfs.img -> ${R}"
  mkdir -p "${WORKDIR}/.rootfs-ro" "${R}"
  sudo_run mount -o loop,ro "${img}" "${WORKDIR}/.rootfs-ro"
  sudo_run rsync -aHAX --filter="-x btrfs.*" --numeric-ids "${WORKDIR}/.rootfs-ro/" "${R}/"
  sudo_run umount "${WORKDIR}/.rootfs-ro"
  [[ -x "${R}/usr/bin/bash" ]] || die "unpacked rootfs has no /usr/bin/bash"
}

apply_mods() {
  [[ "$SKIP_APPLY" -eq 1 ]] && { log "Skipping apply-overlays"; return 0; }
  [[ -n "${GAMESCOPE_BUILD:-}" ]] || die "set GAMESCOPE_BUILD (scripts/build-gamescope-in-rootfs.sh output); Valve's gamescope cannot drive the Y700 session"
  [[ -n "${MESA_STACK:-}" ]] || log "NOTE: MESA_STACK not set, Valve's Frame Mesa stays (Odin 3 does the same)"
  log "Applying SM8750 overlay for TB322FC"
  sudo_run env SM8750_DEVICE=tb322fc KERNEL_OUT="${KOUT}" STEAMOS_ROOTFS="${R}" STEAMOS_WORK="${WORKDIR}" \
    MESA_STACK="${MESA_STACK:-}" ${STEAM_ARM_SEED:+STEAM_ARM_SEED="${STEAM_ARM_SEED}"} \
    GAMESCOPE_BUILD="${GAMESCOPE_BUILD}" \
    "${SCRIPTS}/apply-overlays-sm8750.sh"
}

restore_image_suid() {
  local dest="$1" p
  for p in usr/bin/pkexec usr/sbin/pkexec usr/bin/sudo usr/sbin/sudo \
    usr/lib/polkit-1/polkit-agent-helper-1 usr/bin/su usr/bin/passwd usr/bin/newgrp \
    usr/bin/chsh usr/bin/chfn usr/bin/gpasswd usr/bin/unix_chkpwd usr/bin/mount usr/bin/umount; do
    [[ -e "${dest}/${p}" ]] || continue
    sudo_run chown root:root "${dest}/${p}"
    sudo_run chmod 4755 "${dest}/${p}"
  done
  if [[ -e "${dest}/usr/lib/dbus-1.0/dbus-daemon-launch-helper" ]]; then
    sudo_run chown root:root "${dest}/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
    sudo_run chmod 4750 "${dest}/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
  fi
}

cleanup_image() {
  sync || true
  sudo_run umount "${MNT}" 2>/dev/null || true
  if [[ -n "${LOOPDEV:-}" ]]; then sudo_run losetup -d "${LOOPDEV}" 2>/dev/null || true; LOOPDEV=""; fi
}

build_image() {
  local used_mib total_mib root_uuid part_uuid dev t
  for t in sgdisk mkfs.ext4 uuidgen losetup rsync; do
    command -v "$t" >/dev/null || die "$t missing (sudo apt install gdisk e2fsprogs uuid-runtime rsync)"
  done
  [[ -x "${R}/usr/bin/bash" ]] || die "rootfs not ready"
  [[ -e "${R}/sbin/init" || -L "${R}/sbin/init" ]] || die "rootfs has no /sbin/init (the initramfs execs it)"
  [[ -f "${KOUT}/boot/boot.img" ]] || die "missing ${KOUT}/boot/boot.img"

  if [[ "${AUTO_ROOT}" -eq 1 ]]; then
    used_mib="$(sudo_run du -sm --exclude=proc --exclude=sys --exclude=dev --exclude=tmp \
      --exclude=run --exclude='.image-mnt' "${R}" | awk '{print $1}')"
    ROOT_MIB=$((used_mib + used_mib / 10 + 4096))
    log "root auto-size ${ROOT_MIB} MiB (rootfs ${used_mib} MiB + 4 GiB free; grows on first boot)"
  fi
  total_mib=$((ROOT_MIB + 2))
  root_uuid="$(uuidgen)"
  part_uuid="$(uuidgen)"
  mkdir -p "${OUTDIR}" "${MNT}"
  rm -f "${IMG}"
  truncate -s "${total_mib}M" "${IMG}"
  # GPT name "rootfs" is what tb322fc-linux's initramfs looks for.
  sgdisk -o -n "1:2048:+${ROOT_MIB}M" -t 1:8300 -c 1:rootfs -u "1:${part_uuid}" "${IMG}" >/dev/null

  LOOPDEV="$(sudo_run losetup -Pf --show "${IMG}")"
  trap cleanup_image EXIT INT TERM
  dev="${LOOPDEV}p1"
  for _ in $(seq 1 50); do [[ -b "$dev" ]] && break; sleep 0.1; done
  if [[ ! -b "$dev" ]]; then
    # No partition nodes (containers without udev): map p1 by offset instead.
    sudo_run losetup -d "${LOOPDEV}"
    LOOPDEV="$(sudo_run losetup -f --show -o $((2048 * 512)) --sizelimit "$((ROOT_MIB * 1024 * 1024))" "${IMG}")"
    dev="${LOOPDEV}"
    log "no loop partition nodes; using ${dev} at the p1 offset"
  fi

  log "Formatting ${dev} ext4 UUID=${root_uuid}"
  sudo_run mkfs.ext4 -q -F -L rootfs -U "${root_uuid}" -m 1 "${dev}"
  sudo_run mount "${dev}" "${MNT}"
  log "Writing root (with /home)"
  sudo_run rsync -aHAX --numeric-ids --exclude='.image-mnt' "${R}/" "${MNT}/"
  restore_image_suid "${MNT}"
  if [[ -d "${MNT}/home/steamos" ]]; then sudo_run chown -R 1000:1000 "${MNT}/home/steamos"; fi
  sudo_run tee "${MNT}/etc/fstab" >/dev/null <<FSTAB
# SteamOS ARM, Lenovo Legion Tab Y700 Gen 4 (TB322FC): one ext4 root, /home inside.
# The initramfs already mounted it (GPT name "rootfs"); growfs fills the partition.
UUID=${root_uuid}  /  ext4  defaults,noatime,x-systemd.growfs  0 1
FSTAB
  cleanup_image
  trap - EXIT INT TERM

  local -a sums=(boot.img "$(basename "${IMG}")")
  if [[ "${EXPORT_EXT4}" -eq 1 ]]; then
    log "Exporting ${OUTDIR}/rootfs.ext4"
    dd if="${IMG}" of="${OUTDIR}/rootfs.ext4" bs=1M skip=1 count="${ROOT_MIB}" status=none
    sums+=(rootfs.ext4)
  fi
  cp -f "${KOUT}/boot/boot.img" "${OUTDIR}/boot.img"
  (cd "${OUTDIR}" && sha256sum "${sums[@]}" >SHA256SUMS)

  log "================================================================="
  log "SteamOS ARM for Lenovo Legion Tab Y700 Gen 4 (TB322FC) built:"
  log "  ${OUTDIR}/boot.img  (kernel $(cat "${KOUT}/kernel.release"))"
  log "  ${IMG}  (${total_mib} MiB)"
  log "USB drive: sudo dd if=${IMG} of=/dev/sdX bs=4M status=progress conv=fsync"
  log "Tablet in fastboot, USB drive in the other USB-C port, then:"
  log "  fastboot boot ${OUTDIR}/boot.img"
  log "================================================================="
}

mkdir -p "${WORKDIR}"
ensure_kernel
ensure_official_rootfs
apply_mods
build_image
