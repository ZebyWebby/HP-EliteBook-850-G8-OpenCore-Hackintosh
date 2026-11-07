#!/bin/sh
# offline macos tahoe install from the INSTALL usb partition.
# in macos recovery: disk utility, make an apfs volume called "Macintosh HD" on the free space, quit disk utility,
# then Utilities > Terminal and run:   sh /Volumes/INSTALL/install-tahoe.sh
PKG=/Volumes/INSTALL/InstallAssistant.pkg
TARGET="${1:-/Volumes/Macintosh HD}"
APP="$TARGET/Applications/Install macOS Tahoe.app"

if [ ! -f "$PKG" ]; then echo "can't find $PKG, is the INSTALL partition mounted?"; exit 1; fi
if [ ! -d "$TARGET" ]; then
  echo "can't find $TARGET. make it in disk utility first, or pass the volume path:"
  echo "  sh /Volumes/INSTALL/install-tahoe.sh \"/Volumes/<your volume>\""
  ls /Volumes; exit 1
fi

echo "1/2 unpacking the installer app onto $TARGET (a few minutes)..."
installer -pkg "$PKG" -target "$TARGET" || { echo "unpacking failed"; exit 1; }

echo "2/2 starting the tahoe install, the laptop will reboot a few times. pick the macos installer entry in opencore each time."
"$APP/Contents/Resources/startosinstall" --agreetolicense --volume "$TARGET" --nointeraction
