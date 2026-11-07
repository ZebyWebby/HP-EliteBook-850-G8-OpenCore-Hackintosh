---
name: opencore-efi
description: how to work on this repo's opencore EFI for zeb's hp elitebook 850 g8 (tiger lake, macos tahoe) - editing src/make_efi.py and EFI/OC/config.plist, kexts, SSDTs, the custom VoodooI2C/AppleALC builds, deploying to the laptop's internal efi partition or the OPENCORE usb, and debugging the laptop's macos hardware (audio, mute leds, touchpad, pointing stick, touchscreen, keyboard hotkeys, brightness, sleep, usb-c charging, graphics). use this whenever the task touches anything in this repo or the hackintosh laptop itself, even if the user only says "the laptop", "the mac", "the usb", "it won't boot", or names a symptom like "the touchscreen stopped working" or "sound is broken".
---

# opencore efi for the hp elitebook 850 g8

read AGENTS.md (rules, local patches, acpi paths), README.md (hardware status, install) and HANDOFF.md (live state and
the history of every fix) before changing things. this skill is the working method that sits on top of those.

## the three places and who can do what

| place | how to reach it | notes |
| --- | --- | --- |
| zeb's windows pc | this checkout, `C:\Users\Zeb\elitebook-850-g8-opencore` | can push to git.neptunethefox.dev. git autocrlf is on, so text files are CRLF in the working copy |
| the laptop (macos tahoe 26.7.2) | `ssh zebastian@<tailscale-ip>` over tailscale, key `zeb-desktop-claude` from the pc | repo copy at `~/elitebook-850-g8-opencore` (clean LF). no sudo over ssh, no login for the git server |
| the OPENCORE usb (rescue stick) | `/Volumes/OPENCORE` on the mac, `D:` on the pc | also holds `SysReport/ACPI` (acpi dump), `debug-backup/` (DEBUG opencore + drivers), `kext-backup/`, `config.plist.*` backups |

the laptop boots from its own efi partition (`disk0s1`). the usb is the way back in when a change breaks boot: boot it
with f9. if both break, have zeb plug the usb into the pc and fix it on `D:` with python/plistlib.

when ssh times out after a reboot or a freeze, tailscale on the mac usually hasn't connected: ask zeb to toggle it in the
menu bar. `tailscale ping` from the pc showing `rx 0` means the tunnel is up but stuck.

## changing the config

`src/make_efi.py` builds `EFI/` from extracted release zips, but its work dir isn't on the pc. so every change goes in two
places that must stay in step:

1. edit `src/make_efi.py` (the source of truth, with a lowercase comment saying why)
2. apply the same change to `EFI/OC/config.plist` with python plistlib (`plistlib.dump(..., sort_keys=True)`)
3. validate with the 1.0.8 ocvalidate from the RELEASE zip:
   `OpenCore-1.0.8-RELEASE/Utilities/ocvalidate/ocvalidate.exe EFI/OC/config.plist` must say "No issues found".
   OCAT's bundled ocvalidate is 0.8.8 and flags every newer key, don't use it

new kexts: add to the `kexts` list in make_efi.py in load order (Lilu first, plugins after what they depend on), copy the
bundle into `EFI/OC/Kexts/`, add the Kernel.Add entry to config.plist next to the same neighbour. check the kext's
`OSBundleLibraries` before adding. downloads (kexts, release zips, pkgs) need zeb's ok first: say the file, the source
and the size. verify hashes against the release's checksums when it publishes them.

## SSDTs

- source in `src/SSDT-*.dsl`, compiled output in `EFI/OC/ACPI/`, listed in config.plist ACPI.Add (sorted by path)
- compile on the mac with iasl-stable from the MaciASL dmg:
  `hdiutil attach -nobrowse -readonly -mountpoint /tmp/maciasl ~/Desktop/goodies/hackintosh/MaciASL-1.6.5-RELEASE.dmg`,
  then `/tmp/maciasl/MaciASL.app/Contents/MacOS/iasl-stable SSDT-X.dsl`, scp the .aml back
- to read the firmware's tables, copy `DSDT.aml` and the `SSDT-*.aml` you need from `/Volumes/OPENCORE/SysReport/ACPI/`
  into `/tmp/acpi` on the mac and disassemble there (`iasl-stable -d`). never copy MSDM: it holds zeb's windows key.
  /tmp is wiped on every reboot, so expect to redo this
- method renames go in ACPI.Patch with `Count 1` and `TableSignature`/`OemTableId` set, after checking the name occurs
  once in that table (count the bytes in the .aml with python)
- guard every macos-only method with `If (_OSI ("Darwin"))`. the DSDT's own _OSI calls are renamed to XOSI, an SSDT's are not

## custom kext builds (on the mac, command line tools only)

- `bash ~/elitebook-850-g8-opencore/src/voodooi2c/build.sh ~/stick-build/work` clones pinned VoodooI2C 2.9.1,
  applies `pointing-stick.patch` and `touchscreen-jumps.patch`, checks out VoodooGPIO 44fc744 and writes
  `x/VoodooI2C-2.9.1-stick/{VoodooI2C,VoodooI2CHID,VoodooGPIO}`
- `bash ~/elitebook-850-g8-opencore/src/applealc/build.sh ~/alc-build/work` builds AppleALC 1.9.8 with layout 71's pin 0x17
  path removed into `x/AppleALC-1.9.8-850g8/AppleALC`
- only the binaries go into the release bundles (`Contents/MacOS/`), the release Info.plists stay. make_efi.py does the
  same swap, so keep its copy lines in step
- builds are reproducible: an unchanged binary rebuilds to the same hash, which is a quick way to see what a patch touched
- to change a patch: clone, apply the existing patch, edit, regenerate with `git diff` (core repo) plus
  `git -C "VoodooI2C Satellites/VoodooI2CHID" diff --src-prefix=... --dst-prefix=...` (submodule), and rebuild from scratch
  with build.sh to prove the new patch applies cleanly
- before shipping a kernel binary, compare with the release one: `nm -gU` for kmod_info and the start/stop symbols,
  `nm -u` counts, `lipo -info` (release builds are often fat, ours are x86_64 only)

## deploying

sudo only works when zeb types it, so stage everything, then hand over one command.

**internal efi (`disk0s1`), single files** (the usual case):
1. stage files at their real path under `~/efi-update/EFI/...` on the mac (start from `rm -rf ~/efi-update`). a new kext
   needs both its bundle files and the changed `EFI/OC/config.plist`, stage them together
2. files to remove go in `~/efi-update/delete.txt`, one `EFI/OC/...` path per line
3. zeb runs `sudo bash ~/update-efi-internal.sh` (keep `~/update-efi-internal.sh` a copy of `src/update-efi-internal.sh`).
   it checks disk0s1 is the internal EFI partition, keeps every replaced or deleted file as `<name>.old-internal` in the
   stage, and verifies from a fresh remount. tell zeb what it should print (n updated, n deleted)
4. rolling back = copy the `.old-internal` files back over the staged ones and run it again

**internal efi, whole thing:** `sudo bash ~/elitebook-850-g8-opencore/src/install-efi-internal.sh` copies EFI/BOOT and EFI/OC
from the usb (backup tar in `~`). `sudo bash .../src/check-efi-internal.sh` writes `~/efi-check.txt` with what's really there.

**the usb** (writable without sudo): back up what you replace (`config.plist.<reason>`, `kext-backup/<name>/`), then from the
mac repo copy:

```sh
cd ~/elitebook-850-g8-opencore
rsync -rc --exclude="._*" --exclude="config.plist.*" --exclude="kext-backup/" --exclude=".DS_Store" EFI/ /Volumes/OPENCORE/EFI/
rsync -rcn --delete --itemize-changes (same excludes) EFI/ /Volumes/OPENCORE/EFI/ | grep -E "^(>f.*c|>f\+|\*deleting)"
```

the second line must print nothing. the usb config differs from the repo on purpose: `ShowPicker true`, `Timeout 3`, so
the rescue stick always shows the picker. reapply that with plutil after syncing the config, and keep
`config.plist.normal` equal to it. always deploy to both the internal efi and the usb, or note in HANDOFF.md which one is behind.

**the mac repo copy:** files edited on the pc go to `~/elitebook-850-g8-opencore` with scp in the same step, so the two
copies never drift. check with `git hash-object --stdin-paths` on both sides (see lessons).

**after deploying:** a change only applies after the next boot. check `sysctl -n kern.boottime` against the file times
before deciding a fix failed.

## debugging toolbox

- **opencore log:** the RELEASE build logs nothing. for one diagnostic boot, put `debug-backup/OpenCore.efi` (and the
  DEBUG driver you care about, e.g. `debug-backup/Drivers/AudioDxe.efi`) on the usb with `Misc.Debug.Target 67`, boot the
  usb with f9, read `/Volumes/OPENCORE/opencore-*.txt` (FAT, contains NULs: `tr -d '\000'`). put the usb back after
- **kext IOLog lines** (VoodooI2C, VoodooPS2, AppleALC) only show in `sudo dmesg` on tahoe, not in `log show`. have zeb run
  `sudo dmesg > ~/ps2debug/dmesg.txt` right after reproducing, the buffer is small
- **keyboard codes:** the VoodooPS2 DEBUG build logs `sending key e020=4a down` lines (dmesg only). `LogScanCodes` does
  nothing in the RELEASE build. key remaps go in `SSDT-PS2K` (RMCF "Custom ADB Map")
- **touch devices first look:** `ioreg -r -c VoodooI2CDeviceNub -d2` should show TPD0 and TPL0 with a
  VoodooI2CHIDDevice each, and `Interrupt Mode = GPIO` with `gpioPin` 175/267. the usb keeps `config.plist.polling`
  (polling mode, the setup before VoodooGPIO 44fc744) and `kext-backup/VoodooI2C*-release/` as fallbacks. a dead panel that
  sends no reports at all points at power/reset (TPL0 `_PS0`), not at macos
- **raw HID (touchpad, pointing stick, touchscreen):** `~/hid-test/hidtest 30` writes `~/hid-test/hid-test.txt`. it has to
  run from Terminal with Input Monitoring allowed, tcc blocks it over ssh (`0xe00002e2`)
- **codec verbs:** `alc-verbs` on HDEF enables AppleALC's ALCUserClientProvider. small IOKit tools in `~/muteled/`
  (`gpio`, `ampcaps`, `rates`, `aud`) call `IOConnectCallScalarMethod(conn, 0, {nid, verb, param}, 3, ...)`. pause the
  muteled LaunchAgent before poking gpios by hand, it rewrites them every 5 s
- **coreaudio controls:** `osascript -e "output muted of (get volume settings)"` = `missing value` means the device has
  no mute control at all
- **backlight:** `TGLBacklightPWM` on the registry root (`ioreg -d1 -l -w0`), little endian u32s: write count at byte 4,
  duty at 8, pwm frequency at 16. `IODisplayParameters` on AppleBacklightDisplay has the macos side
- **sleep:** `pmset -g log | grep -E "Failure|Sleep  |Wake  "`, `/Library/Logs/DiagnosticReports/*Sleep Wake*` and
  `Kernel-*.panic` (the panic string is in the json's `macOSPanicString`)
- **sample a value while zeb reproduces:** a small loop on the mac that prints only on change, started in the background
  before asking zeb to press keys. `ioreg -l` is slow (~1 s), query the exact object instead

## lessons that cost a reboot

- a script with `set -euo pipefail` quits silently on `ls missing | sed` or a failing `du` in `$(...)`. add an ERR trap
  that prints the line and guard optional commands with `|| true`. the first internal install "succeeded" without copying
- tahoe mounts FAT through fskit: check `df -P <mountpoint>` names the right `/dev/diskXsY` before copying, and verify
  from a fresh remount, not the mount you just wrote through
- the boot chime: the alc285 dacs only take 48 kHz. with a 48 kHz file AudioDxe starts playback and the laptop hangs with a
  black screen, picker or not. keep `PlayChime Disabled`
- sleep: s3 resume dies in hp's firmware ("Sleep Wake failure in EFI", 0x1F) and freezes the laptop. RTCMemoryFixup didn't
  help and hides the failure code. sleep is off (`pmset -a disablesleep 1`). don't ask zeb to test sleep casually
- layout 11 left macos with no mute control: the dacs have volume but no mute, the pins mute but no steps. layout 71 matches
- the git working copies differ only in line endings: compare them with `git hash-object --stdin-paths` on both sides,
  not md5
- installing a LaunchAgent can be blocked by auto mode: write the plist into the repo and give zeb the `launchctl
  bootstrap` command. "Bootstrap failed: 5" usually means it was already loaded
- `ioreg` property names that show up as bundle settings are not always live state: read the value back after a change

## rules (from AGENTS.md, the ones that bite)

- never add WhateverGreen (WhateverXe replaces it). keep LapicKernelPanic on, IntelBTPatcher off
- keep the PlatformInfo serial, MLB, ROM and SystemUUID as they are
- never commit `SysReport/`, opencore logs or acpi dumps (MSDM = windows key). the repo stays private
- docs and comments lowercase, no middle dots or bullet dots as separators
- commit as `clawd <clawd@neptunethefox.dev>`, never force push, only commit when zeb asks. push from the pc
  (`GIT_TERMINAL_PROMPT=0 git push origin main`), then bring the mac copy along with a `git bundle` + `--ff-only` merge
  and `git update-ref refs/remotes/origin/main <sha>` there
- record what you found and changed in HANDOFF.md (and README.md when the hardware status changes), on both copies

## device facts

pin numbers, report ids, acpi paths, pci ids and verbs: read `references/device-facts.md` when you need them.
