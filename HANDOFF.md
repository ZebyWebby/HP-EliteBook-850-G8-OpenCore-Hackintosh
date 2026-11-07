# HANDOFF

where things stand on zeb's elitebook 850 g8 hackintosh, written 2026-11-06 for whoever picks this up next (human or agent).
read README.md and AGENTS.md first. this file covers the live state, which AGENTS.md's "status" section is older than.

## state of the laptop

- macos tahoe 26.7.2 (25G332) is installed on the internal ssd. opencore is on the internal efi too since 2026-11-06 and boots
  without the usb
- the usb's `EFI/OC/config.plist` matches this repo (bluetooth kexts on except IntelBTPatcher, `-v` still on)
- last event: the laptop **hard froze** during a gpu test (see "video driver" below). it needs a forced power off and reboot.
  nothing on disk was changed by that test. after it's back, check `/Library/Logs/DiagnosticReports/` for a panic log

| thing | status |
| --- | --- |
| boot, install | works. POST ERROR / clock reset fixed with `DisableRtcChecksum` |
| graphics, metal | works (Metal 2) with the 91270 WhateverXe fork + WhateverXe-Graphics 0.4.0 pkg |
| bluetooth | works with IntelBluetoothFirmware + BlueToolFixup. IntelBTPatcher stays off (hangs boot) |
| bt keyboard | pairing steps sent to zeb, result unknown |
| wifi | not checked in this session |
| trackpad, touchscreen | gpio interrupts with VoodooGPIO master, boots fine (touchpad pin 175, touchscreen pin 267), polling config kept on the usb |
| hardware video decode | h264 and hevc yes, vp9 and av1 no (driver package doesn't expose them) |
| parsec hosting | connects, but the stream is a **solid green screen** (see below) |
| youtube in safari | reported broken, not characterised yet (no safari/webkit crash reports) |
| thunderbolt | not done |

## remote access

- mac: `ssh zebastian@<tailscale-ip>` (tailscale). neptune's key is in authorized_keys
- sudo over ssh needs zeb's password, ask zeb
- gui admin prompts from ssh fail (-60007). bluetooth is blocked by tcc from ssh
- xcode command line tools are installed on the mac (clang works). lldb attach is denied, use in-process signal handlers instead
- zeb's windows desktop: `ssh Zeb@<tailscale-ip>`, the usb gets plugged in there for edits (D: is OPENCORE, H: is INSTALL)

## usb layout (`EFI/OC/` on the OPENCORE partition)

- `config.plist`: the normal build, same as this repo
- `config.plist.normal`: same as config.plist
- `config.plist.install`: bluetooth kexts off, no `-v` (from `make_efi.py <work> <out> install`)
- `config.plist.bak`: older backup
- `kext-backup/`: upstream WhateverXe 0.7.0 and 0.6.1, kept in case the fork build has to be swapped out

## mac-side files

- `~/Desktop/goodies/`: LinearMouse, Rectangle, AltTab, Stats, MonitorControl, Maccy, Karabiner, IINA, Keka, Pearcleaner,
  BetterDisplay, plus hackintosh/ with Hackintool, MaciASL, OCAT
- `~/.parsec/config.json`: `host_software_encode` is `{"value": false}` (hardware). parsec rewrites this file on quit and
  drops non-boolean values, so only edit it while parsec is quit
- `~/wxva-fix/`: the patched video driver work (below). `install.sh` and `revert.sh` copy a bundle into
  `/Library/GPUBundles/AppleIntelTGLGraphicsVADriver.bundle`, `original/` is the untouched mod-signed bundle

## video driver (the open problem)

b00t0x's WhateverXe-Graphics ships apple's big sur `AppleIntelTGLGraphicsVADriver` (16.0.32) plus a `TGLVA` adapter.
apple never shipped a tiger lake mac, so its video processing path (VPHAL) was never run on this gpu.

what happens when parsec (or mediaanalysisd, or WhateverXe issue 23's safari case) converts BGRA to NV12 through
`VTPixelTransferSession`:

1. `VphalRenderer` holds three renderers at ctx+0x910 (VEBOX), +0x918 (VEBOX2), +0x920 (composite). b00t0x leaves both
   VEBOX slots NULL on purpose (trampolines at 0xd80 and 0xd98 skip them), so the stock driver crashes on a NULL store
2. with the NULL derefs patched, the composite renderer runs but fails with status 31. it builds its gpu kernel at runtime
   by linking 519 CMFC kernel pieces. every piece has platform id 13 (tiger lake) in its `CMPI` header, but the driver's
   copy of the linker only accepts 1 to 8 (check at file offset 0x1ee5f2, `83 e9 07`)
3. raising that limit in memory let it link, and then the gpu hung and froze the whole laptop. the old linker produces a
   kernel this gpu can't run. **don't retry that patch**
4. apple's GVA prints `Error scheduling command 0` and VideoToolbox still returns 0, so callers get an untouched buffer.
   an all-zero NV12 frame is solid green, which is parsec's green screen

what's installed right now (`/Library/GPUBundles/...VADriver.bundle`, ad-hoc signed, AMFIPass accepts it without `amfi=0x80`):

- patch 1 at 0x1336c7 to 0x1336f7: NULL-safe stores of the status-report pointer into the +0x920 and +0x910 renderers
- patch 3, code cave in the mach-o header padding at 0x1110 (free 0x10d3 to 0x1160):
  - 0x130e91 jumps to cave A: if the VEBOX slot is NULL, skip its `SetStatusReportParams` call (go to 0x130ea5)
  - 0x12d2f1 jumps to cave B: if the VEBOX slot is NULL, set renderpass `bCompNeeded = 1`, clear +0x20, return 0
    (the same path the driver takes when VEBOX is disabled), exit at 0x12d474
- result: nothing crashes, but conversions still produce no output

file offsets equal vm addresses in this binary (__TEXT vmaddr 0, fileoff 0).

### next step (agreed direction, not started)

make the driver tell GVA it can't do pixel transfer, so VideoToolbox converts BGRA to NV12 itself (cpu) and parsec still
uses the hardware h264/hevc encoder. find what GVA queries for scaler support (the strings `branchPP0: GetDriverParameter`
and `kAVDColorCorrection_*` in AppleGVA, in the dyld cache `.02` file) or make the render path fail early in a way
VideoToolbox falls back from. verify with a pixel test before letting parsec near it: fill a BGRA buffer red and white,
transfer, read Y/UV back (red is about Y 81 U 90 V 240, white Y 235 UV 128).

the fallback that already works is parsec software encoding (`host_software_encode` true), which neptune called a workaround
and didn't want.

## useful debugging tricks on the mac

- test programs that call `VTPixelTransferSession` reproduce the bug without parsec
- the driver can be patched in a test process only: `vm_protect(..., VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY)` on its text
  pages works for non-hardened processes. vtable slots are plain pointers (VphalRenderer::Render is index 8 at 0x758198,
  0x759fc0, 0x75b328, 0x75bbe0)
- call-site tracing: rewrite `call rel32` targets to stubs allocated within 2gb of the driver that log return values
- single-step tracing: `int3` at a function entry plus a SIGTRAP handler that sets the trap flag and records rip.
  this is how the failing checks were found
- careful: anything that actually submits gpu work can hang the gpu and freeze the laptop

## issue triage (2026-11-06, from zeb's desktop, ssh key `zeb-desktop-claude`)

- pointing stick: not ps/2. PS2M's _STA is 0 (P2ME off) and all 4 ps/2 aux ports time out, so the ps/2 mouse plugins are
  turned on but do nothing. the synaptics i2c touchpad (06cb:ce09) has two mouse collections, report 0x02 and 0x18 (3 buttons),
  next to the ptp digitizer. 0x18 is almost certainly the stick. VoodooI2CMultitouchHIDEventDriver only parses digitizer
  collections and never forwards other reports, so they're dropped. fix: patch VoodooI2CHID to send report 0x18 to
  VoodooInput's TrackpointDevice. raw reports couldn't be captured over ssh (IOHIDManagerOpen 0xe00002e2, tcc input monitoring)
- usb-c charging: AC._PSR returns EC0.ACST, cached until EC0.GACP bit 0 is set, which only _Q06 (barrel) does. usb-c raises
  _Q27 in the `UcsiAcpi` ssdt, which goes to UBTC (windows ucsi only). SSDT-ACFIX plus the _PSR and _Q27 renames fix it.
  works (tested 2026-11-06). the charge led blinks with zeb's non-hp 60 W usb-c brick: the 850 g8 wants 65 W, hp firmware
  flags a low-power adapter that way. it holds around 97% and doesn't charge (IsCharging no, ChargingCurrent 0)
- sound: tahoe has no AppleHDA.kext, so AppleALC has nothing to patch. codec is ALC285. the NHLT table means the internal mic
  is a dmic on the intel dsp, which macOS can't drive. a headset mic can work once AppleHDA is back.
  SimpleHDA 1.0.1 (laobamac, lilu plugin, injects AppleHDA through opencore, no root patch) added after AppleALC,
  MinKernel 25.0.0. its optional HAL pkg is not installed. layout-id is still 11, try other ALC285 layouts if 11 is wrong.
  speakers work (tested 2026-11-06). the internal mic shows up but can't capture anything
- sleep: two failures. going down: darkwake panic in IOGraphicsFamily (17 s timeout). waking: "Sleep Wake failure in EFI"
  (0x1F) after a real S3 sleep, the firmware rebooted. pmset was stock (hibernatemode 3, standby, powernap, tcpkeepalive on)
- bluetooth: works, but bluetoothd logs `addScanFilterByUUID failed` (LE scan filters), what IntelBTPatcher normally fixes.
  no newer IntelBluetoothFirmware than 2.4.0
- touchscreen: VoodooI2CTouchscreenHIDEventDriver attaches on every boot in the logs, so it dies at runtime, not at load.
  "Couldn't alloc class VoodooGPIOTigerLakeLP" every boot. catch it live next time it stops
- the build work dir isn't on zeb's desktop, so config.plist was patched to match make_efi.py by hand. rebuild with
  make_efi.py once the work dir is back, it should produce the same config
- heliport: its launch at login helper doesn't start on tahoe. `~/Library/LaunchAgents/dev.neptunethefox.heliport-at-login.plist`
  runs `open -g -a /Applications/HeliPort.app` at login instead
- tailscale: `~/Library/LaunchAgents/dev.neptunethefox.tailscale-at-login.plist` opens it at login (and
  `TailscaleStartOnLogin` is set true)
- charger: zeb uses a xiaomi 90 W (20 V 5 A) brick. the "60 W" in AdapterDetails / `pmset -g adapter` is a placeholder:
  VirtualSMC doesn't implement adapter watts (AC-W is a FIXME) and hp's EC does usb-c pd itself, macOS never sees the real
  wattage. on ac the battery current is 0 (system fully powered) and no dropouts in a 3 minute log. it sits at 96% and
  doesn't charge, hp firmware doesn't top off near full. the blinking charge led is set by hp's EC, not macOS
- safari youtube: worked again on 2026-11-06 without changes, logs showed hevc decoding fine
- touchscreen: TPL0 (ELAN2513, 04f3:2a60) is in ssdt `INTTPL`. power and reset gpios are only set in _PS0 (DSDT), the
  interrupt is a GpioInt (no tiger lake VoodooGPIO, so polling). `~/hid-test/hidtest 60` on the mac records raw reports from
  the touchscreen and touchpad into `~/hid-test/hid-test.txt`. it has to run from Terminal with input monitoring allowed
  (ssh is blocked by tcc). run on 2026-11-06 with the touchscreen dead: zero reports from the touchscreen, so the panel
  itself is silent (unpowered, held in reset, or not polled), not macOS dropping its data
- pointing stick, confirmed by the same log: report 0x18 is the stick, 4 bytes `18 <buttons> <dx> <dy>`, dx/dy signed 8-bit,
  buttons bit 0 left, bit 1 right (0x04 middle not seen). 1459 reports while it was moved. the touchpad's own data is
  report 0x03
- pointing stick fix (2026-11-06): `src/voodooi2c/pointing-stick.patch` on VoodooI2C 2.9.1 sends relative mouse reports to
  VoodooInput's TrackpointDevice. built on the mac with `src/voodooi2c/build.sh` (no xcode needed), installed on the usb.
  the release 2.9.1 kexts are backed up in `EFI/OC/kext-backup/VoodooI2C-2.9.1-release/` on the usb: copy both back over
  `EFI/OC/Kexts/` if boot or the touchpad breaks.
  first build didn't work: no "Relative pointer found" in the boot log, because kIOHIDElementKey only lists the top level
  collections and the patch didn't walk their children. fixed in the patch (collectElements), VoodooI2CHID rebuilt and
  installed, not tested yet. the stick only has left and right buttons, no middle, so VoodooInput's middle button
  scrolling can't be used
- gpio (2026-11-06): VoodooGPIO built from master 44fc744 (its tiger lake lp tables match linux pinctrl-tigerlake), installed
  in the VoodooI2C bundle, `-vi2c-force-polling` dropped. VoodooGPIO.hpp is unchanged from the 2.9.1 pin, VoodooI2C rebuilt
  bit-identical. fallback on the usb: `EFI/OC/config.plist.polling` (copy over config.plist) and
  `EFI/OC/kext-backup/VoodooGPIO-2.9.1-release/VoodooGPIO`. booted fine: VoodooGPIOTigerLakeLP matched INT34C5, TPD0 and TPL0
  report `Interrupt Mode = GPIO` (gpioPin 175 and 267). touchscreen reliability across reboots not checked yet.
  pmset is still stock (hibernatemode 3, standby, powernap on), the sleep command was never run
- touchscreen jumps (2026-11-06): a raw capture showed the ELAN2513 sends one report with a far off position (850+ of 3888
  units) right before a lift, and sometimes a one report phantom touch. normal drag steps are 20 to 60 units.
  `src/voodooi2c/touchscreen-jumps.patch` holds the pointer when a finger moves more than 12% of the screen in one report,
  until a second report agrees. replaying the capture: all 9 junk reports held, no jump through. zeb confirmed the jumps
  are gone (2026-11-06). built into VoodooI2CHID, installed on the internal efi with `src/update-efi-internal.sh` (files in `~/efi-update/EFI/...`). the usb still has the
  previous VoodooI2CHID, update it next time it's plugged in
- hotkeys (2026-11-06), from the VoodooPS2 2.3.7 DEBUG build (its key log only shows in `sudo dmesg` on tahoe, not in
  `log show`; LogScanCodes does nothing in the RELEASE build). with "launch hotkeys without fn" off in the bios:
  mute alone = F5 (3f), fn+mute = e020 (sent once), airplane alone = F11 (57), fn+airplane = e078, F12 = 58,
  fn+F12 (star) = 0x68 = F17. `SSDT-PS2K` maps e078 to F18 through RMCF "Custom ADB Map"
- mute key "unmuting itself": the built-in output had no mute control at all (`output muted of (get volume settings)` =
  missing value), so macOS showed the icon and reverted. fix: SimpleHDA's HAL pkg (`SimpleHDA-HAL-1.0.1.pkg`, payload is
  only `/Library/Audio/Plug-Ins/SimpleHDA/AppleHDAHALPlugIn.bundle`, no scripts)
- mute leds: linux has 103c:8846 as ALC285_FIXUP_HP_GPIO_LED, gpio2 (0x04) = mute led, gpio0 (0x01) = mic mute led, high = on,
  verbs on the afg node 0x01. `alc-verbs` on HDEF enables AppleALC's ALCUserClientProvider, and `src/muteled` (CoreAudio
  listener + 5 s re-assert for sleep) sets the gpios. LaunchAgent `src/muteled/dev.neptunethefox.muteled.plist`, binary in
  `~/.local/bin/muteled`
- the HAL pkg loaded (SimpleHDAHALAvailable = Yes) but the output still had no mute: AppleHDAEngineOutput only had
  volume, `evis` and `jack` controls. the codec (queried through alc-verbs): dacs 0x02/0x03 have volume but no mute,
  pins 0x14/0x17/0x21 have mute but no steps. layout 11 claims mute and volume on both. switched to layout 71 (hp spectre
  alc285, mute on pins, volume on dacs, adds pin 0x17 which this laptop's bios marks not connected). works (2026-11-06): the output now has a
  settable mute, fn+mute stays muted and the led follows
- layout 71 also made a dead second output "Built-in Speaker" (its PathMap has a separate group for pin 0x17, and AppleHDA
  builds it even with the pin set to not connected). `src/applealc/build.sh` builds AppleALC 1.9.8 from source with that
  group removed (ResourceConverter + clang, no xcode). x86_64 only, same 382 imports as the release build. works (2026-11-06): one
  speaker output, mute and the led still fine
- mute led confirmed: writing gpio data 0x05 through alc-verbs lit the orange mute led. muteled runs from the LaunchAgent
- the usb is behind the internal efi again: it lacks SSDT-PS2K and the alc-verbs config. copy them over next time
- boot chime (2026-11-06): DEBUG log said "PlayFile playback setup failure - Unsupported". the chime mp3 is 44.1 kHz and
  both alc285 dacs (0x02, 0x03) only list 48 kHz (param 0x0A = 0x000e0040). opencore tries .mp3 then .wav, so the mp3 is
  gone and `src/OCEFIAudio_VoiceOver_Boot-48k.wav` (afconvert LEI16@48000) is shipped as OCEFIAudio_VoiceOver_Boot.wav.
  that made it worse: AudioDxe accepts the 48 kHz file and the laptop hangs inside AudioDxe while it starts playback (last
  log line "File VoiceOver_Boot for type OCEFIAudio lang 7 is 64 2 2 (486504) - Success"), with and without the picker.
  black screen, no apple logo, from both the internal efi and the usb. PlayChime is Disabled now, the wav stays for later
- no verbose (-v gone) and no picker (ShowPicker false, hold esc or option for it), 2026-11-06. the usb rescue stick keeps
  the picker on purpose (ShowPicker true, Timeout 3), the only difference from the repo config
- sleep (2026-11-06): after the pmset changes the darkwake panic is gone, but waking still dies in the firmware
  ("Sleep Wake failure in EFI", 0x1F) and the laptop freezes. FACP has Low Power S0 Idle = 1, so hp may not test s3 resume.
  RTCMemoryFixup with rtcfx_exclude=80-FF was injected (checked in the opencore log) and it still froze, so it's not the rtc.
  it also stops macos writing its sleep failure code (that lives in rtc 0x80+), so it was taken out again. sleep is off for
  now (`pmset -a disablesleep 1`). next idea: hibernatemode 25, so waking goes through a normal boot and opencore
- display wake (2026-11-06): with sleep disabled the display still turns off after `displaysleep` minutes, and on wake
  the panel stays black while macos thinks it's on (IODisplayWrangler power state 4, brightness 1024). TGLBacklightPWM
  shows the duty at 17741/17777 but the control word dropped from 0x80000000 to 0x0, so the pwm enable bit isn't restored
  on display wake. brightness writes (DisplayServicesSetBrightness) and a pmset displaysleepnow / caffeinate -u cycle
  don't bring it back. WhateverXe bug, workaround `sudo pmset -a displaysleep 0`
- lock screen (2026-11-06): the first lock, while the backlight was already in that broken state, took the laptop down
  (no panic, the unified log for 14:11 to 14:16 is empty, SMC cause 5). with displaysleep 0 and a fresh boot a recorded lock
  at 14:20:24 kept the display on (power state 4, ctl 0x80000000) and worked fine. so locking is safe while display sleep
  stays off, the trigger is the display off/on path
- opencore is the RELEASE build again (Target 3, no SysReport), and the 1.0.8 ocvalidate reports no issues
- lockups after 15 to 30 minutes (2026-11-06): the iris xe render ring hangs (`Kernel_*.gpuRestart` in
  /Library/Logs/DiagnosticReports, several in a row), WindowServer stops checking in and watchdogd panics ("userspace
  watchdog timeout: no successful checkins from WindowServer"). before every hang mediaanalysisd floods the log with
  `AVD error: Gen75IntelGVAScheduleAVDCommands: Command[0] err = 11` (622 lines before the 14:40 hang, 451 before 15:52), so
  its background video analysis through the hardware decoder kills the gpu. it runs when the mac is idle, hence the delay.
  workaround: `launchctl disable gui/501/com.apple.mediaanalysisd` plus a bootout (undo with `launchctl enable`). this loses
  photos scene and face analysis. hardware decode in other apps (VideoToolbox) may hit the same bug, watch for gpuRestart files
- speaker loudness (2026-11-06): at 100% volume the speaker dac (0x02) already sits at 0x57 = 0 dB, its maximum, so the
  codec has no more gain. windows sounds louder because of the b&o / realtek apo software dsp. eqMac 1.9.2 is installed in
  /Applications for a volume boost and eq, its HAL driver adds the "Internal Speakers (eqMac)" output, which is now the
  default output. muteled follows the default device, so the mute led tracks eqMac's mute
- cpu performance (2026-11-06): xcpm with the MacBookPro16,2 vectors, ratio range 4 to 44. measured with `~/cpuclk/clk`
  (dependent add chain, 1 add per cycle) and `sudo bash ~/cpuclk/measure.sh` (powermetrics). on ac: 4.37 GHz single core,
  4.0 GHz on all cores sustained (powermetrics shows MAX_TURBO_LIMIT, the chip's own ceiling). on battery: 4.3 GHz single
  core, 3.1 GHz all cores (hp's lower battery power limit), about 1 GHz at idle. a first run on ac right after a reboot only
  got about 2 GHz, it was the post-boot background work, not the charger

## other to-dos

- EFI copied to the internal ssd's efi partition on 2026-11-06 with `src/install-efi-internal.sh` (it was empty before, only
  macos metadata, backup in `~/efi-internal-backup-20261105-180900.tar`). the first runs silently stopped before copying (set -e +
  pipefail on an `ls` of the missing EFI folder), fixed, and the script now verifies after a remount. installed for real on
  2026-11-06. boots without the usb through an f10 customized boot entry (`\EFI\BOOT\BOOTx64.efi`), tested 2026-11-06. config changes now
  have to go to both the usb and the internal efi. `-v` can go
- update AGENTS.md's status section (it still describes the pre-install state)
- thunderbolt
- switch back to upstream WhateverXe once issue 24 (80 EU / 6 L3 bank gpus) is fixed
- maybe post the VEBOX findings on WhateverXe issue 23
- confirm the bt keyboard pairing and whether screen sharing (vnc) was turned on
