// muteled: drives the hp elitebook 850 g8 mute and mic mute leds from the macOS mute state.
// the leds hang off the ALC285 codec's gpios (linux: ALC285_FIXUP_HP_GPIO_LED for 103c:8846), gpio2 = mute led,
// gpio0 = mic mute led, gpio high = led on. the gpio verbs go through AppleALC's ALCUserClientProvider, which needs
// the alc-verbs property on HDEF (make_efi.py sets it).
// build: clang -O2 -o muteled muteled.c -framework CoreAudio -framework IOKit -framework CoreFoundation
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dispatch/dispatch.h>
#include <stdio.h>

#define AFG_NID          0x01
#define GET_GPIO_DATA    0xF15
#define GET_GPIO_MASK    0xF16
#define GET_GPIO_DIR     0xF17
#define SET_GPIO_DATA    0x715
#define SET_GPIO_MASK    0x716
#define SET_GPIO_DIR     0x717
#define LED_MUTE         0x04
#define LED_MICMUTE      0x01
#define LEDS             (LED_MUTE | LED_MICMUTE)

static io_connect_t conn;
static int last_data = -1;

static int verb(unsigned verb, unsigned param, uint64_t *out) {
    if (!conn) {
        io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("ALCUserClientProvider"));
        if (!s) return -1;
        kern_return_t kr = IOServiceOpen(s, mach_task_self(), 0, &conn);
        IOObjectRelease(s);
        if (kr) { conn = 0; return -1; }
    }
    uint64_t in[3] = {AFG_NID, verb, param}, res = 0;
    uint32_t n = 1;
    if (IOConnectCallScalarMethod(conn, 0, in, 3, &res, &n)) {
        IOServiceClose(conn); conn = 0;
        return -1;
    }
    if (out) *out = res;
    return 0;
}

static bool device_muted(AudioObjectPropertySelector which, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress a = {which, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioDeviceID dev = 0;
    UInt32 size = sizeof dev;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &dev) || !dev) return false;
    AudioObjectPropertyAddress m = {kAudioDevicePropertyMute, scope, kAudioObjectPropertyElementMain};
    if (!AudioObjectHasProperty(dev, &m)) return false;
    UInt32 muted = 0;
    size = sizeof muted;
    if (AudioObjectGetPropertyData(dev, &m, 0, NULL, &size, &muted)) return false;
    return muted != 0;
}

static void update(bool force) {
    int want = (device_muted(kAudioHardwarePropertyDefaultOutputDevice, kAudioDevicePropertyScopeOutput) ? LED_MUTE : 0) |
               (device_muted(kAudioHardwarePropertyDefaultInputDevice, kAudioDevicePropertyScopeInput) ? LED_MICMUTE : 0);
    if (!force && want == last_data) return;
    uint64_t mask = 0, dir = 0, data = 0;
    // keep the other gpios as the codec has them, only touch the two led bits
    if (verb(GET_GPIO_MASK, 0, &mask) || verb(GET_GPIO_DIR, 0, &dir) || verb(GET_GPIO_DATA, 0, &data)) {
        last_data = -1;
        return;
    }
    verb(SET_GPIO_MASK, (unsigned)((mask | LEDS) & 0xff), NULL);
    verb(SET_GPIO_DIR, (unsigned)((dir | LEDS) & 0xff), NULL);
    verb(SET_GPIO_DATA, (unsigned)(((data & ~LEDS) | want) & 0xff), NULL);
    last_data = want;
}

static OSStatus changed(AudioObjectID obj, UInt32 n, const AudioObjectPropertyAddress *a, void *ctx) {
    dispatch_async(dispatch_get_main_queue(), ^{ update(false); });
    return 0;
}

static AudioDeviceID watched[2];

// listen for mute changes on the current default devices, and move the listeners when the defaults change
static void watch_defaults(void) {
    AudioObjectPropertySelector sel[2] = {kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice};
    AudioObjectPropertyScope scope[2] = {kAudioDevicePropertyScopeOutput, kAudioDevicePropertyScopeInput};
    for (int i = 0; i < 2; i++) {
        AudioObjectPropertyAddress a = {sel[i], kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioDeviceID dev = 0;
        UInt32 size = sizeof dev;
        AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &dev);
        if (dev == watched[i]) continue;
        AudioObjectPropertyAddress m = {kAudioDevicePropertyMute, scope[i], kAudioObjectPropertyElementMain};
        if (watched[i]) AudioObjectRemovePropertyListener(watched[i], &m, changed, NULL);
        if (dev && AudioObjectHasProperty(dev, &m)) AudioObjectAddPropertyListener(dev, &m, changed, NULL);
        watched[i] = dev;
    }
}

static OSStatus defaults_changed(AudioObjectID obj, UInt32 n, const AudioObjectPropertyAddress *a, void *ctx) {
    dispatch_async(dispatch_get_main_queue(), ^{ watch_defaults(); update(false); });
    return 0;
}

int main(void) {
    AudioObjectPropertyAddress out = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectPropertyAddress in = {kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &out, defaults_changed, NULL);
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &in, defaults_changed, NULL);
    watch_defaults();
    update(true);
    if (!conn) fprintf(stderr, "muteled: ALCUserClientProvider not available (alc-verbs not set?), will keep retrying\n");

    // the codec forgets its gpios across sleep, so put the leds back every few seconds
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(t, ^{ update(true); });
    dispatch_resume(t);
    dispatch_main();
}
