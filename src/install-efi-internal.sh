#!/bin/bash
# copies the usb's opencore (EFI/BOOT and EFI/OC) onto the laptop's internal efi partition (disk0s1).
# run on the mac: sudo bash install-efi-internal.sh
# anything already on the internal efi partition is saved to ~/efi-internal-backup-<time>.tar first, and only
# EFI/BOOT and EFI/OC are replaced, other folders (e.g. EFI/Microsoft) are left alone.
set -euo pipefail
trap 'echo "stopped at line $LINENO: $BASH_COMMAND"' ERR

SRC=/Volumes/OPENCORE/EFI
PART=disk0s1
MNT=/Volumes/EFI-internal
USER_HOME=$(eval echo "~${SUDO_USER:-$USER}")
STAMP=$(date +%Y%m%d-%H%M%S)

[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo bash $0"; exit 1; }
[ -f "$SRC/OC/OpenCore.efi" ] && [ -f "$SRC/BOOT/BOOTx64.efi" ] && [ -f "$SRC/OC/config.plist" ] \
  || { echo "usb opencore not found at $SRC (is the OPENCORE usb plugged in and mounted?)"; exit 1; }

# make sure disk0s1 really is the internal efi partition before writing to it
info=$(diskutil info "$PART")
echo "$info" | grep -q "Partition Type: *EFI" || { echo "$PART is not an EFI partition, stopping"; exit 1; }
echo "$info" | grep -q "Device Location: *Internal" || { echo "$PART is not internal, stopping"; exit 1; }

# mount, and make sure $MNT really is the partition (on tahoe fat goes through fskit, and a mount that isn't there
# yet would send the copy into a plain folder on the macos disk, which is what happened the first time)
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
echo "mounted $PART at $MNT"

# back up what's there now
if [ -n "$(ls -A "$MNT" 2>/dev/null)" ]; then
  B="$USER_HOME/efi-internal-backup-$STAMP.tar"
  tar -cf "$B" -C "$MNT" .
  chown "${SUDO_USER:-root}" "$B"
  echo "backed up the old internal efi to $B"
  if [ -d "$MNT/EFI" ]; then ls "$MNT/EFI" | sed 's/^/  had EFI\//'; else echo "  it had no EFI folder"; fi
fi

# space check (usb EFI plus a margin)
need=$(du -sk "$SRC" | cut -f1)
free=$(df -k "$MNT" | awk 'NR==2{print $4}')
have_now=$( { du -sk "$MNT/EFI/OC" "$MNT/EFI/BOOT" 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}')
[ $((free + have_now)) -gt $((need + 1024)) ] || { echo "not enough space on $PART ($free KB free, need $need KB)"; exit 1; }

mkdir -p "$MNT/EFI"
rm -rf "$MNT/EFI/OC" "$MNT/EFI/BOOT"
cp -R "$SRC/BOOT" "$SRC/OC" "$MNT/EFI/"
find "$MNT" -name '._*' -delete
sync

# verify from a fresh mount, so nothing is read back from the cache
diskutil unmount "$MNT" >/dev/null
mount_part

for f in BOOT/BOOTx64.efi OC/OpenCore.efi OC/config.plist; do
  a=$(md5 -q "$SRC/$f"); b=$(md5 -q "$MNT/EFI/$f")
  [ "$a" = "$b" ] || { echo "MISMATCH on $f"; exit 1; }
done
n_src=$(find "$SRC/BOOT" "$SRC/OC" -type f ! -name '._*' | wc -l | tr -d ' ')
n_dst=$(find "$MNT/EFI/BOOT" "$MNT/EFI/OC" -type f | wc -l | tr -d ' ')
[ "$n_src" = "$n_dst" ] || { echo "file count differs: usb $n_src, internal $n_dst"; exit 1; }
echo "done: $n_dst files on the internal efi after a remount, BOOTx64.efi, OpenCore.efi and config.plist match the usb"
df -k "$MNT" | awk 'NR==2{print "used " $3 " KB on " $1}'
