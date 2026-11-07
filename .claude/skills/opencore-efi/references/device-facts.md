# device facts for the hp elitebook 850 g8 (103c:8846)

collected while getting macos tahoe working, 2026-11-05 and 2026-11-06. details and the reasoning behind each fix are in
HANDOFF.md.

## acpi

| what | path or name |
| --- | --- |
| root | `_SB.PC00`, cpus `_SB.PR00..` (Processor objects) |
| embedded controller | `_SB.PC00.LPCB.EC0` (fake EC for macos at `LPCB.EC`, SSDT-EC-USBX) |
| ps/2 keyboard | `_SB.PC00.LPCB.PS2K`, `_HID HPQ8002`. `PS2M` has `_STA 0` (P2ME off), the pointing stick isn't ps/2 |
| igpu, panel | `_SB.PC00.GFX0`, panel `DD1F`, backlight `PNLF` (`_UID 19`) |
| trackpad | `_SB.PC00.I2C0.TPD0`, SYNA30BE |
| touchscreen | `_SB.PC00.I2C1.TPL0`, ELAN2513, defined in ssdt `INTTPL`. power and reset gpios only set in `_PS0` (DSDT) |
| gpio controller | `_HID INT34C5` (tiger lake lp) |
| ac adapter | `_SB.AC._PSR` returns `EC0.ACST`, refreshed only when `EC0.GACP` bit 0 is set (`PWUP`) |
| usb-c events | `EC0._Q27` in ssdt `UcsiAcpi` (OEM table id) -> `_SB.UBTC` (USBC000, windows ucsi) |
| barrel charger event | `EC0._Q06` |
| brightness keys | `_Q86`/`_Q87` or hp wmi -> `\_GPE.G400` -> `G40B` (ssdt) -> `Notify (\_SB.PC00.GFX0.DD1F, 0x86/0x87)`, once per press |
| sleep | `_S3` exists (when `SS3`), FACP `Low Power S0 Idle = 1` |
| mic | NHLT table present: the internal mic is a dmic on the intel dsp |
| rtc | AWAC off through `STAS = 1` (SSDT-AWAC) |

## hid devices

| device | vendor:product | reports |
| --- | --- | --- |
| synaptics touchpad | 06cb:ce09 | 0x03 ptp digitizer, 0x18 pointing stick `18 <buttons> <dx> <dy>` (signed 8 bit, bit 0 left, bit 1 right, no middle), 0x02 second mouse collection (never seen sending) |
| elan touchscreen | 04f3:2a60 | 0x01 one finger per report `01 <flags> <w> <h> <x lo> <x hi> <x lo> <x hi> <y lo> <y hi> ..`, flags bit 0 tip, bits 2+ contact id. x max ~3888, y max ~2160 |

the elan panel sends one junk position (850+ units away) right before a lift: `touchscreen-jumps.patch` holds the pointer
for moves over 12% of the screen in one report until a second report agrees.

gpio pins with VoodooGPIO 44fc744: touchpad 175, touchscreen 267, both `Interrupt Mode = GPIO`.

## keyboard (VoodooPS2 codes, "launch hotkeys without fn keypress" off)

| key | alone | with fn |
| --- | --- | --- |
| F1 display switch | F1 | win + p (macos sees ⌘P) |
| mute | F5 (3f) | e020 mute |
| airplane | F11 (57) | e078, mapped to F18 (ADB 0x4f) by SSDT-PS2K |
| star (F12) | F12 (58) | 0x68 = F17 (ADB 0x40) |

## audio (realtek alc285, 10ec:0285, codec address 0, afg node 0x01)

| node | what |
| --- | --- |
| 0x02, 0x03 | dacs: volume (87 steps), no mute, 48 kHz only (param 0x0A = 0x000e0040) |
| 0x14 | internal speaker pin (`0x90170130` in the layout, bios `0x90170110`), mute only |
| 0x17 | not wired (bios `0x411111f0`), layout 71 turns it into a dead second speaker, removed in the custom build |
| 0x21 | headphone pin `0x012b1020`, mute only |
| 0x19 | headset mic pin, 0x12 internal mic pin (the real mic is on the dsp, not here) |
| gpio2 (0x04) | mute led, high = on |
| gpio0 (0x01) | mic mute led, high = on |

verbs on node 0x01: `0xF16`/`0x716` gpio mask, `0xF17`/`0x717` direction, `0xF15`/`0x715` data. `0xF00` param `0x12`
output amp caps (bit 31 = mute), `0x09` widget caps, `0x0A` pcm rates. linux has this laptop as
`ALC285_FIXUP_HP_GPIO_LED` (`alc_fixup_hp_gpio_led(codec, action, 0x04, 0x01)`).

## pci

| device | id | macos |
| --- | --- | --- |
| hda controller | 8086:a0c8 at 1F,3, spoofed `device-id 34C8` | AppleHDA through SimpleHDA |
| me | 0x16,0 spoofed `device-id 34E0` | |
| i2c controllers | 8086:a0e8/a0e9 | VoodooI2C (ids added to IOPCIMatch) |
| thunderbolt nhi `TDM0` | 8086:9a1b | no driver, thunderbolt doesn't work |
| thunderbolt pcie ports `TRP0/TRP1` | 8086:9a23, 9a25 | present, nothing attached |
| thunderbolt xhci `TXHC` | | works, usb on the type-c ports |

## backlight

panel pwm frequency 17777, macos max 65403 (`F19Ta68b` profile from WhateverXe, top step 0xff7b). at the top of the bar
macos, the display service and the panel all report 100% (duty 17741).
