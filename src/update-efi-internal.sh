#!/bin/bash
# copies the files staged in ~/efi-update/EFI/... onto the same paths on the laptop's internal efi partition (disk0s1).
# for updating single files (a kext binary, config.plist) when the usb isn't plugged in.
# run on the mac: sudo bash update-efi-internal.sh
# each replaced file is kept next to the staged copy as <name>.old-internal first. new files are added.
# paths listed in ~/efi-update/delete.txt (one per line, like EFI/OC/Resources/Audio/x.mp3) are removed, also kept as .old-internal
set -euo pipefail
trap 'echo "stopped at line $LINENO: $BASH_COMMAND"' ERR

PART=disk0s1
MNT=/Volumes/EFI-internal
USER_HOME=$(eval echo "~${SUDO_USER:-$USER}")
STAGE="$USER_HOME/efi-update"

[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
[ -d "$STAGE/EFI" ] || { echo "nothing staged in $STAGE/EFI"; exit 1; }
files=$(cd "$STAGE" && find EFI -type f ! -name '*.old-internal' ! -name '._*' 2>/dev/null | sort)
deletes=$( [ -f "$STAGE/delete.txt" ] && grep -vE '^\s*(#|$)' "$STAGE/delete.txt" || true)
[ -n "$files$deletes" ] || { echo "nothing staged in $STAGE/EFI or $STAGE/delete.txt"; exit 1; }

info=$(diskutil info "$PART")
echo "$info" | grep -q "Partition Type: *EFI" || { echo "$PART is not an EFI partition, stopping"; exit 1; }
echo "$info" | grep -q "Device Location: *Internal" || { echo "$PART is not internal, stopping"; exit 1; }

mount_part() {
  diskutil unmount "$PART" >/dev/null 2>&1 || true
  mkdir -p "$MNT"
  diskutil mount -mountPoint "$MNT" "$PART" >/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(df -P "$MNT" 2>/dev/null | awk 'NR==2{print $1}')" = "/dev/$PART" ] && return 0
    sleep 1
  done
  echo "$MNT is not $PART after mounting, stopping"; df -P "$MNT"; exit 1
}
mount_part
trap 'diskutil unmount "$MNT" >/dev/null 2>&1 || true' EXIT
[ -f "$MNT/EFI/OC/OpenCore.efi" ] || { echo "no opencore on the internal efi, use install-efi-internal.sh instead"; exit 1; }

while IFS= read -r f; do
  dst="$MNT/$f"
  case "$f" in EFI/OC/*|EFI/BOOT/*) ;; *) echo "$f is outside EFI/OC and EFI/BOOT, stopping"; exit 1;; esac
  if [ -e "$dst" ]; then
    cp "$dst" "$STAGE/$f.old-internal"
    cp "$STAGE/$f" "$dst"
    echo "replaced $f"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$STAGE/$f" "$dst"
    echo "added $f"
  fi
done <<< "$files"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in EFI/OC/*|EFI/BOOT/*) ;; *) echo "$f is outside EFI/OC and EFI/BOOT, stopping"; exit 1;; esac
  if [ -e "$MNT/$f" ]; then
    mkdir -p "$(dirname "$STAGE/$f")"
    cp "$MNT/$f" "$STAGE/$f.old-internal"
    rm "$MNT/$f"
    echo "deleted $f"
  else
    echo "already gone: $f"
  fi
done <<< "$deletes"
sync

# verify from a fresh mount
diskutil unmount "$MNT" >/dev/null
mount_part
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$(md5 -q "$STAGE/$f")" = "$(md5 -q "$MNT/$f")" ] || { echo "MISMATCH on $f"; exit 1; }
done <<< "$files"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ ! -e "$MNT/$f" ] || { echo "still there: $f"; exit 1; }
done <<< "$deletes"
chown -R "${SUDO_USER:-root}" "$STAGE"
echo "done: $(echo "$files" | grep -c . | tr -d ' ') file(s) updated, $(echo "$deletes" | grep -c . | tr -d ' ') deleted, checked after a remount"
