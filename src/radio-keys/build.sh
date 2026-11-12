#!/bin/bash
# builds RadioKeys.app (the hotkey helper: airplane, F1 display switch, star) and radio-toggle, installs them and
# starts the login agent.
# run on the mac from the repo: bash src/radio-keys/build.sh
set -euo pipefail
trap 'echo "stopped at line $LINENO: $BASH_COMMAND"' ERR
cd "$(dirname "$0")"

APP="$HOME/Applications/RadioKeys.app"
AGENT="$HOME/Library/LaunchAgents/dev.neptunethefox.radiokeys.plist"
BIN="$HOME/.local/bin"
TMP="$(mktemp -d)"

clang -O2 -Wall -fobjc-arc -framework AppKit -framework Carbon -framework IOKit -framework IOBluetooth \
  -framework CoreFoundation -o "$TMP/radio-keys" radio-keys.m
clang -O2 -Wall -framework IOKit -framework IOBluetooth -framework CoreFoundation \
  -o "$TMP/radio-toggle" ../radio-toggle/radio-toggle.c

# stop the running helper before replacing it
launchctl bootout "gui/$(id -u)/dev.neptunethefox.radiokeys" 2>/dev/null || true

mkdir -p "$APP/Contents/MacOS" "$BIN" "$HOME/Library/LaunchAgents"
cp Info.plist "$APP/Contents/Info.plist"
cp "$TMP/radio-keys" "$APP/Contents/MacOS/radio-keys"
# ad hoc signature. macOS ties the bluetooth and input monitoring permissions to it, so every rebuild needs them
# granted again (Privacy & Security, remove RadioKeys, add it back). keep rebuilds rare: key actions and popups for
# F16 and F17 live in keys.plist. a self-signed certificate would fix this, but codesign only takes
# one the system trusts, and trusting it is a security setting for zeb to change
codesign --force --sign - --identifier dev.neptunethefox.radiokeys "$APP"
cp "$TMP/radio-toggle" "$BIN/radio-toggle"
# the key actions are zeb's to edit, only install the default file once
CONF="$HOME/Library/Application Support/RadioKeys"
mkdir -p "$CONF"
[ -f "$CONF/keys.plist" ] || cp keys.plist "$CONF/keys.plist"
# only rewrite the launch agent when it changed: every write makes macos show a "background items added" notification
sed "s|/Users/zebastian|$HOME|g" dev.neptunethefox.radiokeys.plist > "$TMP/agent.plist"
cmp -s "$TMP/agent.plist" "$AGENT" || cp "$TMP/agent.plist" "$AGENT"
rm -rf "$TMP"

launchctl bootstrap "gui/$(id -u)" "$AGENT"
sleep 1
launchctl print "gui/$(id -u)/dev.neptunethefox.radiokeys" | grep -E "state|pid" | head -2
tail -4 "$HOME/Library/Logs/radio-toggle.log"
