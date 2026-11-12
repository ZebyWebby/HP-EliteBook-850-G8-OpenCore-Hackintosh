# HP-EliteBook-850-G8-OpenCore-Hackintosh
This is an EFI folder I have for the HP EliteBook 850 G8

> [!IMPORTANT]
> This EFI was made with **Claude** (Claude Code, Anthropic's AI), not just by a person. Claude wrote the config, the SSDTs,
> the kext patches and builds and the scripts, and debugged everything over SSH while I tested it on the laptop. So if
> something looks weird, that's why.

> [!NOTE]
> This is the final state of the EFI from November 2026, copied off the laptop's own EFI partition before it moved to Linux.

> [!CAUTION]
> This is **ONLY** for macOS Tahoe 26.7.2 and 26.7.3 (it updated to 26.7.3 fine) so stuff **COULD** break when used with a different macOS version.
> It uses WhateverXe instead of WhateverGreen. **NEVER** add WhateverGreen, the two must not load together.

> [!NOTE]
> OpenCore version used is 1.0.8 (RELEASE), SMBIOS MacBookPro16,2

> [!NOTE]
> Change your SMBIOS Serial Number, MLB, ROM etc. The ones in config.plist are placeholders.

### Legend:
- [X] Working
- ❓ Untested
- [ ] Not working

## Specs
| Component Type | What is it |
| ------------- | ------------- |
| CPU | Intel Core i5-1145G7 |
| GPU | Intel Iris Xe Graphics (80 EU) |
| CPU Codename | Tiger Lake |
| SSD | WD SN530 256GB NVMe |
| Wi-Fi Card | Intel AX201 |
| Bluetooth | Intel 8087:0026 |
| Audio | Realtek ALC285 |
| Trackpad | Synaptics SYNA30BE (I2C, with the pointing stick) |
| Touchscreen | ELAN2513 (I2C) |
| OS | macOS Tahoe 26.7.3 (25G342) |

- [X] Graphics Acceleration (Metal, with WhateverXe 0.7.0 6 L3 bank fork + the WhateverXe-Graphics pkg)
- [X] Wi-Fi (itlwm + HeliPort)
- [X] Bluetooth (LE devices can be flaky, IntelBTPatcher hangs the boot on 26.7.2 so it's off)
- [X] Keyboard
- [X] Trackpad with gestures
- [X] Pointing stick and its buttons (middle button scrolling too, needed a patched VoodooI2CHID because it's not PS/2)
- [X] Touchscreen
- [X] Speakers + Headphone jack (SimpleHDA + custom AppleALC, Tahoe doesn't even have AppleHDA anymore)
- [X] Mute key + mute LED
- [X] Brightness + brightness keys (the bar stops a little short of full but it is full)
- [X] Battery Indicator + Percentage
- [X] Charging (including USB-C)
- [X] All USB ports (USB map included)
- [X] H264 and HEVC hardware decode
- [X] Booting without the USB
- [X] Hotkeys with an on-screen popup like the volume one (RadioKeys): airplane turns Wi-Fi and Bluetooth off together, F1 display switch opens Mission Control, star (F12) opens the screenshot toolbar, F10 is Insert (the Mac Help key) with an Insert popup
- [X] Function keys (with HP's hotkeys on by default: F1 display switch is F16, F5 is mute, F11 airplane is F18 and F12 star is F17. hold fn for the plain F-keys)
- ❓ HDMI
- ❓ External monitors over USB-C (can be flaky on Tiger Lake)
- ❓ Webcam
- [ ] Sleep (waking up from S3 fails inside HP's firmware and the laptop freezes. HP's own forum has G8s failing to wake on Windows too. hibernation never kicked in and hiding S3 just keeps it awake with the screen off, so sleep stays turned off. SHUT IT DOWN BEFORE PUTTING IT IN A BAG)
- [ ] Display sleep (the screen stays black after it turns off, so that's off too)
- [ ] Internal Microphone (it's on the Intel DSP, macOS has no driver for it. use a headset, USB or bluetooth mic)
- [ ] Boot chime (the laptop hangs while it starts playing it)
- [ ] Thunderbolt
- [ ] Fingerprint Scanner, NFC, Smart Card Reader
- [ ] DRM in Safari (Disney+, Netflix, Apple TV+). use a Chromium based browser or Firefox
- [ ] VP9 and AV1 hardware decode

> [!WARNING]
> The GPU can hang after 15 to 30 minutes of sitting idle. That's mediaanalysisd (Photos background analysis) breaking the
> video decoder. Turn it off with `launchctl disable gui/501/com.apple.mediaanalysisd` (you lose Photos face and scene search)

## BIOS settings (F10)
Already fine: Secure Boot off, Fast Boot off, Sure Start BIOS protection off, BitLocker off.

- Advanced > System Options > Configure Storage Controller for VMD: **Off** (macOS can't see the SSD with VMD on. if you keep Windows, run `bcdedit /set {current} safeboot minimal` first, boot it once in safe mode after turning VMD off, then `bcdedit /deletevalue {current} safeboot`, or it bluescreens)
- Security > Trusted Execution Technology (TXT): **Off**
- Video Memory Size: **128 MB** (512 MB breaks the boot with "No slide values are usable")
- Leave VT-d and virtualization on
- Optional: Battery Health Manager "Maximize my battery duration" to charge to 100%

## Installing
1. Copy the EFI folder and a Tahoe recovery (`python3 macrecovery.py -b Mac-CFF7D910A743CAAF -m 00000000000000000 -os latest download` from the OpenCore Utilities) to a FAT32 GPT USB drive. Or do the offline install with `src/install-tahoe.sh` and the InstallAssistant.pkg on an exFAT partition
2. Boot it with F9, pick macOS Recovery, make an APFS volume in Disk Utility and reinstall macOS
3. After installing: the WhateverXe-Graphics pkg (graphics acceleration), HeliPort (Wi-Fi), the SimpleHDA HAL pkg (volume and mute) and `src/muteled` (mute LEDs)
4. Hotkeys: run `bash src/radio-keys/build.sh`. It installs RadioKeys (a background helper that starts at login), which grabs the airplane key (F18: Wi-Fi and Bluetooth off or on together), F1 (F16: Mission Control) and star (F17: screenshot toolbar) and shows a popup for each, plus an Insert popup for F10 (it only watches that key, so it needs Input Monitoring). Allow Bluetooth for RadioKeys the first time, and untick any F16/F17 shortcuts in System Settings > Keyboard > Keyboard Shortcuts. What F1 and star do is set in `~/Library/Application Support/RadioKeys/keys.plist` (a shell command, an SF Symbols icon and the popup text per key), restart it after editing with `launchctl kickstart -k gui/$(id -u)/dev.neptunethefox.radiokeys`. It also installs `radio-toggle` in `~/.local/bin` for Terminal: `radio-toggle status`, `radio-toggle wifi off`, `radio-toggle bt on`
5. Turn sleep off so it doesn't freeze: `sudo pmset -a hibernatemode 0 standby 0 powernap 0 proximitywake 0 tcpkeepalive 0 displaysleep 0` and `sudo pmset -a disablesleep 1`
6. Copy the EFI to the internal disk with `sudo bash src/install-efi-internal.sh`, then in F10 > Advanced > Boot Options turn on Customized Boot with `\EFI\BOOT\BOOTx64.efi`

There's no boot picker, it boots straight into macOS. Hold Esc or Option at power on for it.

## How it's put together
`src/make_efi.py` builds the whole EFI folder and config.plist, the SSDT sources and the patched kext build scripts are in `src/`, and HANDOFF.md has the notes on every fix.

- Kexts: Lilu, VirtualSMC (+ SMCBatteryManager, SMCProcessor), ECEnabler, WhateverXe + AMFIPass 1.4.1 Mod, AppleALC (custom), SimpleHDA, VoodooPS2Controller, VoodooI2C + VoodooI2CHID (custom), BrightnessKeys, itlwm, BlueToolFixup, IntelBluetoothFirmware, NVMeFix, RestrictEvents, USBToolBox + UTBMap
- SSDTs: EC-USBX, AWAC, PNLF, PMC, XOSI (I2C GPIO interrupts), ACFIX (USB-C charging), PS2K (keyboard)
- boot-args: `keepsyms=1 debug=0x100 -allow3d -disablegfxfirmware -lilubetaall revpatch=sbvmm`, csr-active-config `03080000`, SecureBootModel Disabled
