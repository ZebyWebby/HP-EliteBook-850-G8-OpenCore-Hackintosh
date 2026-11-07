#!/bin/bash
# builds VoodooI2C 2.9.1 + pointing-stick.patch + touchscreen-jumps.patch on a mac with only the xcode command line tools (no xcode).
# usage: build.sh <work>   (output: <work>/x/VoodooI2C-2.9.1-stick/{VoodooI2C,VoodooI2CHID,VoodooGPIO}, the kext binaries)
# make_efi.py copies those binaries into the release 2.9.1 bundles, so the release Info.plists and plugins stay.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES=("$HERE/pointing-stick.patch" "$HERE/touchscreen-jumps.patch")
W="$(mkdir -p "$1" && cd "$1" && pwd)/voodooi2c-src"
OUT="$(dirname "$W")/x/VoodooI2C-2.9.1-stick"
rm -rf "$W" "$OUT"; mkdir -p "$W" "$OUT"
cd "$W"

git clone -q --recursive --branch v2.9.1 https://github.com/VoodooI2C/VoodooI2C.git
git clone -q https://github.com/acidanthera/MacKernelSDK.git && git -C MacKernelSDK checkout -q 3f750085caa17ec3a7880f11c11bf4f48cd6a164
git clone -q --branch 1.1.6 https://github.com/acidanthera/VoodooInput.git
for p in "${PATCHES[@]}"; do (cd VoodooI2C && patch -s -p1 < "$p"); done
# VoodooGPIO master: 2.9.1 pins 733dc80, whose binary has no tiger lake lp code. 44fc744 (2026-10-25) builds it in.
# VoodooGPIO.hpp is the same in both, so VoodooI2C's view of the class doesn't change
git -C VoodooI2C/Dependencies/VoodooGPIO fetch -q origin master && git -C VoodooI2C/Dependencies/VoodooGPIO checkout -q 44fc744

R=$W/VoodooI2C
SDK=$W/MacKernelSDK
CLT=/Library/Developer/CommandLineTools
LIBKMODCXX=$(ls $CLT/SDKs/MacOSX*.sdk/usr/lib/libkmodc++.a | tail -1)
CCKEXT=$(ls $CLT/usr/lib/clang/*/lib/darwin/libclang_rt.cc_kext.a | tail -1)
OBJ=$W/obj

# 10.13 is what xcode raises the projects' 10.11 target to. the IOHIDEventService methods the headers expose depend on it.
# fortify off so memcpy stays plain memcpy, like the release build
CFLAGS=(-arch x86_64 -mmacosx-version-min=10.13 -mkernel -fapple-kext -nostdinc -fno-builtin -fno-common
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -D_FORTIFY_SOURCE=0 -Os -g0
  -I"$SDK/Headers" -I"$W/VoodooInput/VoodooInput"
  -Wno-inconsistent-missing-override -Wno-deprecated-declarations -Wno-unused-command-line-argument)
CXXFLAGS=("${CFLAGS[@]}" -x c++ -std=gnu++11 -fno-exceptions -fno-rtti)

# what xcode generates for a kext target: the kmod_info and the c++ runtime start/stop hooks
info_stub() { # bundle-id version file
  cat > "$3" <<EOS
#include <mach/mach_types.h>
#include <mach/kmod.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL($1, "$2", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOS
}

build() { # name bundle-id version srcdir sources... (source lists match the xcode targets)
  local name=$1 id=$2 ver=$3 dir=$4; shift 4
  local objs=() o
  mkdir -p "$OBJ/$name"
  for f in "$@"; do
    o="$OBJ/$name/$(basename "${f%.cpp}").o"
    (cd "$dir" && clang "${CXXFLAGS[@]}" -c "$f" -o "$o" 2>>"$OBJ/warnings.log")
    objs+=("$o")
  done
  info_stub "$id" "$ver" "$OBJ/$name/info.c"
  clang "${CFLAGS[@]}" -x c -c "$OBJ/$name/info.c" -o "$OBJ/$name/info.o"
  clang -arch x86_64 -mmacosx-version-min=10.13 -nostdlib -Xlinker -kext \
    "$LIBKMODCXX" "${objs[@]}" "$OBJ/$name/info.o" "$SDK/Library/x86_64/libkmod.a" "$CCKEXT" -o "$OUT/$name"
  echo "built $OUT/$name"
}

build VoodooI2C com.alexandred.VoodooI2C 2.9.1 "$R/VoodooI2C/VoodooI2C" \
  "../../Multitouch Support/VoodooI2CDigitiserStylus.cpp" \
  "../../Multitouch Support/VoodooI2CDigitiserTransducer.cpp" \
  VoodooI2CDevice/VoodooI2CDeviceNub.cpp \
  VoodooI2CController/VoodooI2CPCILakeController.cpp \
  VoodooI2CController/VoodooI2CControllerNub.cpp \
  VoodooI2CController/VoodooI2CController.cpp \
  ../../Dependencies/VoodooI2CACPIResourcesParser/VoodooI2CACPIResourcesParser.cpp \
  VoodooI2CController/VoodooI2CACPIController.cpp \
  "../../Multitouch Support/VoodooI2CMultitouchEngine.cpp" \
  "../../Multitouch Support/VoodooI2CMultitouchInterface.cpp" \
  VoodooI2CController/VoodooI2CControllerDriver.cpp \
  VoodooI2CController/VoodooI2CPCIController.cpp \
  ../../Dependencies/helpers.cpp \
  "../../Multitouch Support/Native/VoodooI2CNativeEngine.cpp"

build VoodooI2CHID com.alexandred.VoodooI2CHID 1 "$R/VoodooI2C Satellites/VoodooI2CHID/VoodooI2CHID" \
  Overrides/VoodooI2CHIDDeviceOverride.cpp VoodooI2CPrecisionTouchpadHIDEventDriver.cpp \
  Sensors/VoodooI2CSensorHubEventDriver.cpp VoodooI2CTouchscreenHIDEventDriver.cpp \
  Sensors/VoodooI2CAccelerometerSensor.cpp VoodooI2CMultitouchHIDEventDriver.cpp \
  Sensors/VoodooI2CSensorHubEnabler.cpp Overrides/VoodooI2CHIDSYNA3602Device.cpp VoodooI2CHIDDevice.cpp \
  Sensors/VoodooI2CSensor.cpp VoodooI2CHIDTransducerWrapper.cpp VoodooI2CStylusHIDEventDriver.cpp \
  Sensors/VoodooI2CDeviceOrientationSensor.cpp

build VoodooGPIO org.coolstar.VoodooGPIO 1.1 "$R/Dependencies/VoodooGPIO/VoodooGPIO" \
  VoodooGPIO.cpp VoodooGPIOIntel.cpp VoodooGPIOAMD.cpp VoodooGPIOSunrisePointH.cpp VoodooGPIOSunrisePointLP.cpp \
  CannonLake-H/VoodooGPIOCannonLakeH.cpp CannonLake-LP/VoodooGPIOCannonLakeLP.cpp IceLake-LP/VoodooGPIOIceLakeLP.cpp \
  TigerLake-H/VoodooGPIOTigerLakeH.cpp TigerLake-LP/VoodooGPIOTigerLakeLP.cpp \
  AlderLake-N/VoodooGPIOAlderLakeN.cpp AlderLake-S/VoodooGPIOAlderLakeS.cpp
