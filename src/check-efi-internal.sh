#!/bin/bash
# shows what is really on the laptop's internal efi partition (disk0s1) and checks the fat filesystem.
# run on the mac: sudo bash check-efi-internal.sh   (writes ~/efi-check.txt)
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
PART=disk0s1
MNT=/Volumes/EFI-internal
OUT="$(eval echo "~${SUDO_USER:-$USER}")/efi-check.txt"
{
  echo "== diskutil info"; diskutil info "$PART" | grep -E "Device Node|Partition Type|File System|Volume Name|Disk Size|Device Location"
  diskutil unmount "$PART" >/dev/null 2>&1
  echo "== fsck_msdos (read only)"; fsck_msdos -n "/dev/r$PART" 2>&1
  mkdir -p "$MNT"
  diskutil mount -mountPoint "$MNT" "$PART"
  echo "== df"; df -k "$MNT"
  echo "== top level"; ls -la "$MNT"
  echo "== EFI tree"; find "$MNT/EFI" -maxdepth 3 2>&1 | head -60
  echo "== boot files"; ls -la "$MNT/EFI/BOOT" "$MNT/EFI/OC/OpenCore.efi" "$MNT/EFI/OC/config.plist" 2>&1
  diskutil unmount "$MNT"
} > "$OUT" 2>&1
chown "${SUDO_USER:-root}" "$OUT"
echo "written to $OUT"
