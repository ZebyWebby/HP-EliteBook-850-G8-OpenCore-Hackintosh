// airplane mode for the laptop: turns the intel wifi (itlwm) and bluetooth on or off together.
//   radio-toggle [all|wifi|bt] [status|on|off|toggle]      default: all toggle
// toggle with all: if either radio is on, both go off, otherwise both go on.
// wifi goes through itlwm's user client, the same call as HeliPort's "Turn Wi-Fi Off" (ioctl numbers and struct
// from HeliPort ClientKit). bluetooth uses IOBluetooth's private power calls, the same ones blueutil uses.
// build: clang -O2 -framework IOKit -framework IOBluetooth -framework CoreFoundation -o radio-toggle radio-toggle.c
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdlib.h>
#include <time.h>

#define IOCTL_80211_POWER 2
#define IOCTL_MASK 0x800000
#define IOCTL_VERSION 1
struct ioctl_power { unsigned int version, enabled, maxsleep; };

// every run is logged to ~/Library/Logs/radio-toggle.log, so failures from Shortcuts (no terminal) can be read later
static FILE *logfile;
static void logmsg(const char *fmt, ...) {
    if (!logfile) return;
    va_list ap; va_start(ap, fmt); vfprintf(logfile, fmt, ap); va_end(ap);
    fflush(logfile);
}

int IOBluetoothPreferenceGetControllerPowerState(void);
void IOBluetoothPreferenceSetControllerPowerState(int state);

static io_connect_t open_itlwm(void) {
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOEthernetController"), &it)) return 0;
    io_connect_t con = 0;
    io_service_t s;
    while (!con && (s = IOIteratorNext(it))) {
        char name[32] = "";
        CFStringRef c = IORegistryEntryCreateCFProperty(s, CFSTR("IOClass"), kCFAllocatorDefault, 0);
        if (c) { CFStringGetCString(c, name, sizeof name, kCFStringEncodingUTF8); CFRelease(c); }
        if (!strcmp(name, "itlwm") || !strcmp(name, "itlwmx")) {
            kern_return_t kr = IOServiceOpen(s, mach_task_self(), 0, &con);
            if (kr) logmsg("  IOServiceOpen(%s) failed: 0x%x\n", name, kr);
        }
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    return con;
}

// -1 when there's no itlwm
static int wifi_get(void) {
    io_connect_t con = open_itlwm();
    if (!con) return -1;
    struct ioctl_power p = {0};
    size_t len = sizeof p;
    kern_return_t r = IOConnectCallStructMethod(con, IOCTL_80211_POWER, NULL, 0, &p, &len);
    IOServiceClose(con);
    if (r) logmsg("  wifi power read failed: 0x%x\n", r);
    return r ? -1 : (p.enabled != 0);
}

static int wifi_set(int on) {
    io_connect_t con = open_itlwm();
    if (!con) return -1;
    struct ioctl_power p = { IOCTL_VERSION, (unsigned int)on, 0 };
    kern_return_t r = IOConnectCallStructMethod(con, IOCTL_80211_POWER | IOCTL_MASK, &p, sizeof p, NULL, 0);
    IOServiceClose(con);
    if (r) logmsg("  wifi power set failed: 0x%x\n", r);
    return r ? -1 : 0;
}

static int bt_get(void) { return IOBluetoothPreferenceGetControllerPowerState() != 0; }

static int bt_set(int on) {
    IOBluetoothPreferenceSetControllerPowerState(on);
    // the controller takes a moment to switch, wait up to 3 s for it
    for (int i = 0; i < 30 && bt_get() != on; i++) usleep(100000);
    return bt_get() == on ? 0 : -1;
}

static const char *word(int s) { return s < 0 ? "not found" : s ? "on" : "off"; }

// airplane key: if either radio is on, both go off, otherwise both go on.
// returns the new state (1 on, 0 off), or -1 when a radio didn't switch. used by radio-keys
__attribute__((unused)) static int radio_toggle_all(void) {
    int w = wifi_get(), b = bt_get();
    int want = !(w == 1 || b == 1), rc = 0;
    logmsg("  toggle all: wifi %s, bluetooth %s -> %s\n", word(w), word(b), word(want));
    if (w >= 0 && wifi_set(want)) rc = -1;
    if (bt_set(want)) rc = -1;
    return rc ? -1 : want;
}

#ifndef RADIO_TOGGLE_NO_MAIN
int main(int argc, char **argv) {
    const char *target = "all", *cmd = "toggle";
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "all") || !strcmp(argv[i], "wifi") || !strcmp(argv[i], "bt")) target = argv[i];
        else if (!strcmp(argv[i], "status") || !strcmp(argv[i], "on") || !strcmp(argv[i], "off") || !strcmp(argv[i], "toggle")) cmd = argv[i];
        else { fprintf(stderr, "usage: radio-toggle [all|wifi|bt] [status|on|off|toggle]\n"); return 2; }
    }
    int do_wifi = strcmp(target, "bt") != 0, do_bt = strcmp(target, "wifi") != 0;
    const char *home = getenv("HOME");
    char path[1024];
    if (home) { snprintf(path, sizeof path, "%s/Library/Logs/radio-toggle.log", home); logfile = fopen(path, "a"); }
    time_t now = time(NULL); char ts[32]; strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", localtime(&now));
    logmsg("%s %s %s (uid %d, ppid %d)\n", ts, target, cmd, getuid(), getppid());
    int w = do_wifi ? wifi_get() : 0, b = do_bt ? bt_get() : 0;
    logmsg("  before: wifi %s, bluetooth %s\n", word(w), word(b));

    if (!strcmp(cmd, "status")) {
        if (do_wifi) printf("wifi: %s\n", word(w));
        if (do_bt) printf("bluetooth: %s\n", word(b));
        return 0;
    }
    int want = !strcmp(cmd, "on") ? 1 : !strcmp(cmd, "off") ? 0 : !(w == 1 || b == 1);
    int rc = 0;
    if (do_wifi) {
        if (w < 0) { fprintf(stderr, "wifi: itlwm not found\n"); rc = 1; }
        else if (wifi_set(want)) { fprintf(stderr, "wifi: failed to turn %s\n", word(want)); rc = 1; }
        else printf("wifi: %s\n", word(want));
    }
    if (do_bt) {
        if (bt_set(want)) { fprintf(stderr, "bluetooth: failed to turn %s\n", word(want)); rc = 1; }
        else printf("bluetooth: %s\n", word(want));
    }
    logmsg("  after: wifi %s, bluetooth %s, exit %d\n", word(do_wifi ? wifi_get() : 0), word(do_bt ? bt_get() : 0), rc);
    return rc;
}
#endif
