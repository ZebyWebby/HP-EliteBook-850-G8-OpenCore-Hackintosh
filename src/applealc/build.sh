#!/bin/bash
# builds AppleALC 1.9.8 with ALC285 layout 71 minus its pin 0x17 speaker path, on a mac with only the xcode command line
# tools. layout 71 is used because it puts mute on the pins and volume on the dacs, which is what this codec has (layout
# 11 left macOS with no mute control). on the hp elitebook 850 g8 pin 0x17 isn't wired, and its path showed up as a dead
# second "Built-in Speaker".
# usage: build.sh <work>   (output: <work>/x/AppleALC-1.9.8-850g8/AppleALC, the kext binary)
# make_efi.py copies the binary into the release 1.9.8 bundle, so the release Info.plist stays.
set -euo pipefail
W="$(mkdir -p "$1" && cd "$1" && pwd)/applealc-src"
OUT="$(dirname "$W")/x/AppleALC-1.9.8-850g8"
rm -rf "$W" "$OUT"; mkdir -p "$W" "$OUT"
cd "$W"

git clone -q --branch 1.9.8 https://github.com/acidanthera/AppleALC.git
git clone -q --branch 1.7.2 https://github.com/acidanthera/Lilu.git
git clone -q https://github.com/acidanthera/MacKernelSDK.git && git -C MacKernelSDK checkout -q 3f750085caa17ec3a7880f11c11bf4f48cd6a164
A=$W/AppleALC

# drop the pin 0x17 path group from layout 71 (the resource files are plists without the xml header)
python3 - "$A/Resources/ALC285/Platforms71.xml" <<'EOF'
import plistlib, sys
p = sys.argv[1]
head = b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n'
d = plistlib.loads(head + open(p, "rb").read() + b"</plist>\n")
def nodes(o):
    if isinstance(o, dict):
        return ([o["NodeID"]] if "NodeID" in o else []) + [n for v in o.values() for n in nodes(v)]
    if isinstance(o, list):
        return [n for v in o for n in nodes(v)]
    return []
for pm in d["PathMaps"]:
    before = len(pm["PathMap"])
    pm["PathMap"] = [g for g in pm["PathMap"] if 0x17 not in nodes(g)]
    assert len(pm["PathMap"]) == before - 1, "expected exactly one 0x17 group"
out = plistlib.dumps(d)
out = out[out.index(b"<dict>"):out.rindex(b"</plist>")]
open(p, "wb").write(out)
print("layout 71: removed the pin 0x17 path")
EOF

# ResourceConverter turns Resources/ into kern_resources.cpp (generate.sh is what the xcode build phase runs)
TB=$W/tools; mkdir -p "$TB"
clang++ -std=gnu++14 -fobjc-arc -framework Foundation -O2 "$A/ResourceConverter/main.mm" -o "$TB/ResourceConverter"
PROJECT_DIR="$A" TARGET_BUILD_DIR="$TB" bash -e "$A/ResourceConverter/generate.sh" > "$W/generate.log" 2>&1
[ -f "$A/AppleALC/kern_resources.cpp" ] || { echo "kern_resources.cpp not generated, see $W/generate.log"; exit 1; }

SDK=$W/MacKernelSDK
CLT=/Library/Developer/CommandLineTools
LIBKMODCXX=$(ls $CLT/SDKs/MacOSX*.sdk/usr/lib/libkmodc++.a | tail -1)
CCKEXT=$(ls $CLT/usr/lib/clang/*/lib/darwin/libclang_rt.cc_kext.a | tail -1)
OBJ=$W/obj; mkdir -p "$OBJ"

CFLAGS=(-arch x86_64 -mmacosx-version-min=10.13 -mkernel -fapple-kext -nostdinc -fno-builtin -fno-common
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -D_FORTIFY_SOURCE=0 -Os -g0
  -DMODULE_VERSION=1.9.8 -DPRODUCT_NAME=AppleALC -DHAVE_ANALOG_AUDIO=1
  -mmmx -msse -msse2 -msse3 -mfpmath=sse -mssse3 -fno-asynchronous-unwind-tables
  -I"$SDK/Headers" -I"$W/Lilu/Lilu" -I"$A/AppleALC" -I"$A/AppleALC/ALCUserClient" -I"$A/AppleALC/ALCUserClientProvider"
  -Wno-inconsistent-missing-override -Wno-deprecated-declarations -Wno-unused-command-line-argument -Wno-vla
  -Wno-ossharedptr-misuse -Wno-unknown-warning-option)
CXXFLAGS=("${CFLAGS[@]}" -x c++ -std=gnu++14 -fno-exceptions -fno-rtti)

objs=()
for f in "$A/AppleALC/kern_alc.cpp" "$A/AppleALC/kern_start.cpp" "$A/AppleALC/kern_resources.cpp" \
         "$A/AppleALC/ALCUserClient/ALCUserClient.cpp" "$A/AppleALC/ALCUserClientProvider/ALCUserClientProvider.cpp" \
         "$W/Lilu/Lilu/Library/plugin_start.cpp"; do
  o="$OBJ/$(basename "${f%.cpp}").o"
  clang "${CXXFLAGS[@]}" -c "$f" -o "$o" 2>>"$OBJ/warnings.log"
  objs+=("$o")
done

# the kmod_info xcode generates for a lilu plugin: MODULE_START/STOP are AppleALC_kern_start/stop
cat > "$OBJ/info.c" <<'EOS'
#include <mach/mach_types.h>
#include <mach/kmod.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(as.vit9696.AppleALC, "1.9.8", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = AppleALC_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = AppleALC_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOS
clang "${CFLAGS[@]}" -x c -c "$OBJ/info.c" -o "$OBJ/info.o"
clang -arch x86_64 -mmacosx-version-min=10.13 -nostdlib -Xlinker -kext \
  "$LIBKMODCXX" "${objs[@]}" "$OBJ/info.o" "$SDK/Library/x86_64/libkmod.a" "$CCKEXT" -o "$OUT/AppleALC"
echo "built $OUT/AppleALC"
