import plistlib, shutil, os, sys, uuid
S, OUT = sys.argv[1], sys.argv[2]
X = f"{S}/x"; OC = f"{X}/OpenCore-1.0.8-RELEASE"  # RELEASE boots faster. swap to -DEBUG (and Target 67, SysReport) to debug
efi = f"{OUT}/EFI"
if os.path.exists(efi): shutil.rmtree(efi)
shutil.copytree(f"{OC}/X64/EFI/BOOT", f"{efi}/BOOT")
oc = f"{efi}/OC"
for d in ("ACPI","Kexts","Drivers","Tools","Resources"): os.makedirs(f"{oc}/{d}", exist_ok=True)
shutil.copy(f"{OC}/X64/EFI/OC/OpenCore.efi", oc)
for drv in ("OpenRuntime.efi","OpenHfsPlus.efi","ResetNvramEntry.efi","AudioDxe.efi","OpenCanopy.efi"):
    shutil.copy(f"{OC}/X64/EFI/OC/Drivers/{drv}", f"{oc}/Drivers")
shutil.copy(f"{OC}/X64/EFI/OC/Tools/OpenShell.efi", f"{oc}/Tools")
shutil.copytree(f"{X}/master/OcBinaryData-master/Resources", f"{oc}/Resources", dirs_exist_ok=True)
# boot chime is off: with the 48 kHz file below AudioDxe accepts the chime and then the laptop hangs inside AudioDxe while it
# starts playback (last log line "File VoiceOver_Boot ... is 64 2 2 - Success"), both with and without the picker. the 44.1
# kHz mp3 only "worked" because playback setup failed right away.
# boot chime: the alc285 dacs only take 48 kHz and the chime mp3 is 44.1 kHz, AudioDxe refused it ("playback setup failure
# - Unsupported"). opencore tries .mp3 then .wav, so drop the mp3 and ship a 48 kHz 16 bit wav (afconvert of the same file)
os.remove(f"{oc}/Resources/Audio/OCEFIAudio_VoiceOver_Boot.mp3")
shutil.copy(f"{os.path.dirname(os.path.abspath(__file__))}/OCEFIAudio_VoiceOver_Boot-48k.wav", f"{oc}/Resources/Audio/OCEFIAudio_VoiceOver_Boot.wav")
for a in sorted(os.listdir(f"{S}/ssdt")):
    if a.endswith(".aml"): shutil.copy(f"{S}/ssdt/{a}", f"{oc}/ACPI")

kexts = [  # (source, enabled plugins handled below)
 "Lilu-1.7.2-RELEASE/Lilu.kext",
 "HibernationFixup-1.5.4-RELEASE/HibernationFixup.kext",  # s3 resume dies in hp's firmware, so sleep is hibernation (pmset hibernatemode 25). this keeps the hibernation key in nvram for boot.efi
 "VirtualSMC-1.3.8-RELEASE/Kexts/VirtualSMC.kext",
 "WhateverXe-0.7.0-6bank/WhateverXe.kext",  # 91270/WhateverXe fix/tgl-gt2-6-l3-banks ci build (run 41764065332): upstream 0.7.0 refuses the 80 EU / 6 L3 bank gpu (issue 24), 0.6.1 fails on 26.7.2
 "AMFIPass-v1.4.1-Mod-RELEASE/AMFIPass.kext",
 "AppleALC-1.9.8-RELEASE/AppleALC.kext",
 "SimpleHDA-Tahoe-v1.0.1-RELEASE/SimpleHDA.kext",  # tahoe has no AppleHDA.kext. this injects it so AppleALC has something to patch. must load after AppleALC
 "VirtualSMC-1.3.8-RELEASE/Kexts/SMCBatteryManager.kext",
 "VirtualSMC-1.3.8-RELEASE/Kexts/SMCProcessor.kext",
 "ECEnabler-1.0.6-RELEASE/ECEnabler.kext",
 "VoodooPS2Controller-2.3.7-RELEASE/VoodooPS2Controller.kext",
 "VoodooI2C-2.9.1-RELEASE/VoodooI2C.kext",
 "VoodooI2C-2.9.1-RELEASE/VoodooI2CHID.kext",
 "itlwm_v2.3.0_stable.kext/itlwm.kext",
 "BrcmPatchRAM-2.7.2-RELEASE/BlueToolFixup.kext",
 "IntelBluetooth-v2.4.0/IntelBluetoothFirmware.kext",
 "IntelBluetooth-v2.4.0/IntelBTPatcher.kext",
 "BrightnessKeys-1.0.3-RELEASE/BrightnessKeys.kext",
 "NVMeFix-1.1.3-RELEASE/NVMeFix.kext",
 "RestrictEvents-1.1.6-RELEASE/RestrictEvents.kext",
 "USBToolBox-1.2.0-RELEASE/USBToolBox.kext",
 "UTBMap/UTBMap.kext",
]
# plugin order matters: deps first. (bundle, plugin path, enabled)
plugins = {
 # the mouse and trackpad plugins find nothing (the pointing stick is on the i2c touchpad, see below). VoodooInput stays off, VoodooI2C ships the same one
 "VoodooPS2Controller.kext": [("VoodooInput.kext", False), ("VoodooPS2Keyboard.kext", True), ("VoodooPS2Mouse.kext", True), ("VoodooPS2Trackpad.kext", True)],
 "VoodooI2C.kext": [("VoodooGPIO.kext", True), ("VoodooI2CServices.kext", True), ("VoodooInput.kext", True)],
}
def entry(bundle, comment, enabled=True):
    p = f"{oc}/Kexts/{bundle}"
    info = plistlib.load(open(f"{p}/Contents/Info.plist","rb"))
    exe = info.get("CFBundleExecutable")
    return {"Arch":"x86_64","BundlePath":bundle,"Comment":comment,"Enabled":enabled,
            "ExecutablePath": f"Contents/MacOS/{exe}" if exe and os.path.exists(f"{p}/Contents/MacOS/{exe}") else "",
            "MaxKernel":"","MinKernel":"","PlistPath":"Contents/Info.plist"}
add = []
for k in kexts:
    name = os.path.basename(k)
    shutil.copytree(f"{X}/{k}", f"{oc}/Kexts/{name}", symlinks=True)
    if name in plugins and name == "VoodooI2C.kext":
        for pl, en in plugins[name]: add.append(entry(f"{name}/Contents/PlugIns/{pl}", pl, en))
        add.append(entry(name, name))
    elif name in plugins:
        add.append(entry(name, name))
        for pl, en in plugins[name]: add.append(entry(f"{name}/Contents/PlugIns/{pl}", pl + (" (off: VoodooI2C ships it)" if not en else ""), en))
    else:
        add.append(entry(name, name))

c = plistlib.load(open(f"{OC}/Docs/Sample.plist","rb"))
# ACPI
c["ACPI"]["Add"] = [{"Comment":a,"Enabled":True,"Path":a} for a in sorted(os.listdir(f"{oc}/ACPI"))]
c["ACPI"]["Delete"] = []
c["ACPI"]["Patch"] = [{
  "Base":"","BaseSkip":0,"Comment":"_OSI to XOSI (pairs with SSDT-XOSI)","Count":0,"Enabled":True,
  "Find":bytes.fromhex("5F4F5349"),"Limit":0,"Mask":b"","OemTableId":b"","Replace":bytes.fromhex("584F5349"),
  "ReplaceMask":b"","Skip":0,"TableLength":0,"TableSignature":b"DSDT"},
 {"Base":"","BaseSkip":0,"Comment":"AC._PSR to XPSR (pairs with SSDT-ACFIX)","Count":1,"Enabled":True,
  "Find":b"_PSR","Limit":0,"Mask":b"","OemTableId":b"","Replace":b"XPSR",
  "ReplaceMask":b"","Skip":0,"TableLength":0,"TableSignature":b"DSDT"},
 {"Base":"","BaseSkip":0,"Comment":"EC0._Q27 to XQ27 in UcsiAcpi (pairs with SSDT-ACFIX)","Count":1,"Enabled":True,
  "Find":b"_Q27","Limit":0,"Mask":b"","OemTableId":b"UcsiAcpi","Replace":b"XQ27",
  "ReplaceMask":b"","Skip":0,"TableLength":0,"TableSignature":b"SSDT"},
 # off: hides _S3 so macos can't use s3 (its resume dies in hp's firmware). tested 2026-11-07: macos then never sleeps at
 # all, it only turns the screen off and keeps running (got warm in a bag), and it doesn't hibernate either
 {"Base":"","BaseSkip":0,"Comment":"_S3 to XS3 (hide s3, off: macos then never sleeps)","Count":1,"Enabled":False,
  "Find":bytes.fromhex("085F53335F"),"Limit":0,"Mask":b"","OemTableId":b"","Replace":bytes.fromhex("085853335F"),
  "ReplaceMask":b"","Skip":0,"TableLength":0,"TableSignature":b"DSDT"}]
for q in c["ACPI"]["Quirks"]: c["ACPI"]["Quirks"][q] = False
# Booter
c["Booter"]["MmioWhitelist"] = []; c["Booter"]["Patch"] = []
bq = c["Booter"]["Quirks"]
for q,v in bq.items():
    if isinstance(v,bool): bq[q]=False
for q in ("AvoidRuntimeDefrag","DevirtualiseMmio","EnableSafeModeSlide","EnableWriteUnprotector","ProtectUefiServices","ProvideCustomSlide","RebuildAppleMemoryMap","SyncRuntimePermissions"):
    bq[q]=True
bq["EnableWriteUnprotector"]=False
bq["ResizeAppleGpuBars"]=-1
# DeviceProperties
c["DeviceProperties"]["Add"] = {
  # alc-verbs: lets the muteled helper (src/muteled) set the codec gpios for the mute and mic mute leds
  # layout 71 (hp spectre alc285): mute on the pins, volume on the dacs, which is what this codec has. layout 11 claims
  # mute on the dacs too and macOS ended up with no mute control at all
  "PciRoot(0x0)/Pci(0x1F,0x3)": {"layout-id": bytes.fromhex("47000000"), "device-id": bytes.fromhex("C8340000"), "alc-verbs": bytes.fromhex("01000000")},
  "PciRoot(0x0)/Pci(0x16,0x0)": {"device-id": bytes.fromhex("E0340000")},
}
c["DeviceProperties"]["Delete"] = {}
# Kernel
k = c["Kernel"]
k["Add"] = add; k["Block"] = []; k["Force"] = []; k["Patch"] = []
k["Emulate"]["Cpuid1Data"] = bytes.fromhex("E5060700000000000000000000000000")
k["Emulate"]["Cpuid1Mask"] = bytes.fromhex("FFFFFFFF000000000000000000000000")
kq = k["Quirks"]
for q,v in kq.items():
    if isinstance(v,bool): kq[q]=False
for q in ("AppleXcpmCfgLock","AppleXcpmExtraMsrs","DisableIoMapper","DisableLinkeditJettison","LapicKernelPanic","PanicNoKextDump","PowerTimeoutKernelPanic","CustomSMBIOSGuid","DisableRtcChecksum","ProvideCurrentCpuInfo"):
    kq[q]=True
kq["SetApfsTrimTimeout"] = -1
# Misc
m = c["Misc"]
# no picker: boots the default (macos) straight away. hold esc or option at power on for the picker
m["Boot"].update({"PickerMode":"External","PickerAttributes":17,"ShowPicker":False,"Timeout":5,"HideAuxiliary":True,"PollAppleHotKeys":True,"PickerVariant":"Acidanthera\\GoldenGate"})
# hibernation instead of s3 (resume from s3 dies in hp's firmware). HibernationFixup puts the key in nvram, so look there,
# and boot the hibernated macos straight away even when the picker is on (usb stick)
m["Boot"].update({"HibernateMode":"NVRAM","HibernateSkipsPicker":True})
# no file logging (Target 0x40 fsyncs every line to the usb, very slow) and no SysReport, which RELEASE doesn't do anyway
m["Debug"].update({"AppleDebug":False,"ApplePanic":True,"DisableWatchDog":True,"Target":3,"SysReport":False})
m["Security"].update({"AllowSetDefault":True,"BlacklistAppleUpdate":True,"ScanPolicy":0,"SecureBootModel":"Disabled","Vault":"Optional","DmgLoading":"Signed","ExposeSensitiveData":6})
m["Entries"] = []
m["Tools"] = [{"Arguments":"","Auxiliary":True,"Comment":"OpenShell","Enabled":True,"Flavour":"OpenShell:UEFIShell:Shell","FullNvramAccess":False,"Name":"UEFI Shell","Path":"OpenShell.efi","RealPath":False,"TextMode":False}]
# NVRAM
g = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
nv = c["NVRAM"]["Add"][g]
nv["boot-args"] = "keepsyms=1 debug=0x100 -allow3d -disablegfxfirmware -lilubetaall revpatch=sbvmm"  # no -vi2c-force-polling: VoodooGPIO 44fc744 has tiger lake lp
nv["csr-active-config"] = bytes.fromhex("03080000")
nv["prev-lang:kbd"] = b"en-US:0"
nv["SystemAudioVolume"] = bytes([0x46])
nv["SystemAudioVolumeDB"] = bytes([0xEC])  # -20 dB
c["NVRAM"]["Delete"][g] = ["boot-args","csr-active-config","prev-lang:kbd","SystemAudioVolume","SystemAudioVolumeDB"]
c["NVRAM"]["WriteFlash"] = True
# PlatformInfo: placeholders in the public copy. make your own with `macserial -m MacBookPro16,2` and uuidgen, ROM is your wifi MAC
pi = c["PlatformInfo"]
pi["Generic"].update({"SystemProductName":"MacBookPro16,2","SystemSerialNumber":"W00000000001","MLB":"M0000000000000001",
  "SystemUUID":"00000000-0000-0000-0000-000000000000","ROM":bytes.fromhex("112233445566")})
pi["UpdateSMBIOSMode"] = "Custom"
# UEFI
u = c["UEFI"]
u["Drivers"] = [{"Arguments":("--gpio-setup --restore-nosnoop --force-device=PciRoot(0x0)/Pci(0x1F,0x3)" if d=="AudioDxe.efi" else ""),"Comment":d,"Enabled":True,"HideVerbose":False,"LoadEarly":False,"Path":d} for d in ("OpenRuntime.efi","OpenHfsPlus.efi","ResetNvramEntry.efi","AudioDxe.efi","OpenCanopy.efi")]
# boot chime through AudioDxe on the alc285 (HDA at 1F,3, codec 0)
u["Audio"].update({"AudioSupport":True,"AudioDevice":"PciRoot(0x0)/Pci(0x1F,0x3)","AudioCodec":0,"AudioOutMask":-1,"PlayChime":"Disabled",
  "SetupDelay":500000,"MaximumGain":-15,"MinimumAssistGain":-30,"MinimumAudibleGain":-55,"DisconnectHda":False,"ResetTrafficClass":False})
uq = u["Quirks"]
for q in ("ReleaseUsbOwnership","RequestBootVarRouting","EnableVectorAcceleration"): uq[q]=True
uq["ResizeGpuBars"] = -1
u["ReservedMemory"] = []
# IntelBTPatcher hangs boot on tahoe 26.7.2 right after the usb/hid drivers start (tested 2026-11-05).
# bluetooth works without it (IntelBluetoothFirmware + BlueToolFixup), so it ships disabled.
for e in k["Add"]:
    # SimpleHDA only works on darwin 25 (tahoe) and needs DisableLinkeditJettison (set above)
    if e["BundlePath"]=="SimpleHDA.kext": e["MinKernel"]="25.0.0"; e["MaxKernel"]="25.99.99"
    if e["BundlePath"]=="IntelBTPatcher.kext": e["Enabled"]=False; e["Comment"]+=" (off: hangs boot on tahoe)"
# "install" mode: bluetooth kexts off and no -v, for getting through the macos installer stage.
# the installer froze right after bluetoothd twice. turn them back on (normal build) once macos is installed.
if len(sys.argv) > 3 and sys.argv[3] == "install":
    for e in k["Add"]:
        if e["BundlePath"] in ("BlueToolFixup.kext","IntelBluetoothFirmware.kext","IntelBTPatcher.kext"):
            e["Enabled"] = False; e["Comment"] += " (off for install)"
    nv["boot-args"] = nv["boot-args"].replace("-v ", "")
plistlib.dump(c, open(f"{oc}/config.plist","wb"), sort_keys=True)
print("kexts:", len(add))
# tiger lake ids missing from VoodooI2C 2.9.1: i2c controllers A0E8/A0E9 (and 43E8 for -H), gpio INT34C5
vk = f"{oc}/Kexts/VoodooI2C.kext/Contents"
d = plistlib.load(open(f"{vk}/Info.plist","rb"))
d['IOKitPersonalities']['VoodooI2CPCILakeController']['IOPCIMatch'] += ' 0xa0e88086&0xFFFCFFFF 0x43e88086&0xFFFCFFFF'
plistlib.dump(d, open(f"{vk}/Info.plist","wb"))
d = plistlib.load(open(f"{vk}/PlugIns/VoodooGPIO.kext/Contents/Info.plist","rb"))
d['IOKitPersonalities']['VoodooGPIOTigerLakeLP']['IONameMatch'].append('INT34C5')
plistlib.dump(d, open(f"{vk}/PlugIns/VoodooGPIO.kext/Contents/Info.plist","wb"))
print("patched VoodooI2C for tiger lake")
# AppleALC layout 71 (picked for its mute) also sets pin 0x17 up as a second internal speaker. on this laptop 0x17 isn't
# wired (bios pin config 0x411111f0), so macOS showed a dead "Built-in Speaker". drop the 0x17 pin config verbs
ap = f"{oc}/Kexts/AppleALC.kext/Contents/Info.plist"
d = plistlib.load(open(ap,"rb"))
for e in d["IOKitPersonalities"]["as.vit9696.AppleALC"]["HDAConfigDefault"]:
    if e.get("CodecID") == 0x10ec0285 and e.get("LayoutID") == 71:
        cd = e["ConfigData"]
        e["ConfigData"] = b"".join(cd[i:i+4] for i in range(0, len(cd), 4) if (int.from_bytes(cd[i:i+4], "big") >> 20) & 0x7f != 0x17)
plistlib.dump(d, open(ap,"wb"))
print("patched AppleALC layout 71: no pin 0x17")
# and the layout 71 path list (PathMap) is compiled into the binary, so src/applealc/build.sh builds 1.9.8 with the pin 0x17
# path removed into x/AppleALC-1.9.8-850g8. without it macOS still shows the dead speaker
shutil.copy(f"{X}/AppleALC-1.9.8-850g8/AppleALC", f"{oc}/Kexts/AppleALC.kext/Contents/MacOS/AppleALC")
print("swapped in the AppleALC binary without the pin 0x17 path")
# pointing stick: the synaptics touchpad sends it as mouse report 0x18, which 2.9.1 drops. src/voodooi2c/build.sh builds
# 2.9.1 + pointing-stick.patch (forwards it to VoodooInput's trackpoint device) into x/VoodooI2C-2.9.1-stick
# plus VoodooGPIO from master 44fc744, the first build with tiger lake lp (INT34C5) in it
for b in ("VoodooI2C","VoodooI2CHID"):
    shutil.copy(f"{X}/VoodooI2C-2.9.1-stick/{b}", f"{oc}/Kexts/{b}.kext/Contents/MacOS/{b}")
shutil.copy(f"{X}/VoodooI2C-2.9.1-stick/VoodooGPIO", f"{oc}/Kexts/VoodooI2C.kext/Contents/PlugIns/VoodooGPIO.kext/Contents/MacOS/VoodooGPIO")
print("swapped in the patched VoodooI2C and VoodooGPIO binaries")
