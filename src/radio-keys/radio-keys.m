// radio-keys: background helper for the hp elitebook 850 g8 hotkeys, each with an on-screen popup like the volume one.
// SSDT-PS2K turns the hotkeys into F-keys: airplane e078 -> F18, display switch (F1) e06e -> F16, star (F12) is F17.
//   F18: switches wifi and bluetooth together (radio-toggle.c)
//   F16, F17: run a shell command from ~/Library/Application Support/RadioKeys/keys.plist (defaults below), so their
//   job can change without a rebuild: edit the file, then `launchctl kickstart -k gui/$(id -u)/dev.neptunethefox.radiokeys`
// Shortcuts can't do this: its keyboard shortcuts go through the services system, which ignores a bare F-key.
// carbon hot keys take a bare F-key and need no input monitoring permission.
// F10 is insert, which SSDT-PS2K sends as the mac help key (0x72). it has to reach the app, so it isn't a hot key: a
// listen-only event tap sees it and only shows the popup. that tap needs input monitoring (asked for once).
// build and install: src/radio-keys/build.sh (on the mac)
#define RADIO_TOGGLE_NO_MAIN
#include "../radio-toggle/radio-toggle.c"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <IOKit/hidsystem/ev_keymap.h>
#include <stdatomic.h>

static NSPanel *panel;
static NSImageView *icon;
static NSTextField *label;
static NSUInteger shown;        // bumped on every show, so an old fade out doesn't hide a newer popup
static atomic_bool busy;

// F16 / F17 actions: command (run with /bin/sh -c), symbol (an SF Symbols name) and text for the popup
static NSDictionary *keyActions;
static NSDictionary *defaultActions(void) {
    return @{
        @"F16": @{ @"command": @"open -a 'Mission Control'", @"symbol": @"hp:display", @"text": @"Mission Control" },
        @"F17": @{ @"command": @"open -a Screenshot", @"symbol": @"hp:prog", @"text": @"Screenshot" },
    };
}

// line drawings of the icons printed on the hp keys that SF Symbols has nothing close to. 100 x 80 points, template
static NSImage *hpIcon(NSString *name) {
    NSImage *img = [NSImage imageWithSize:NSMakeSize(100, 80) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [NSColor.blackColor set];
        NSBezierPath *p = [NSBezierPath bezierPath];
        p.lineWidth = 5;
        p.lineCapStyle = NSLineCapStyleRound;
        p.lineJoinStyle = NSLineJoinStyleRound;
        if ([name isEqualToString:@"display"]) {
            // F1 switch display: a screen between two upright bars, |[]|
            [p moveToPoint:NSMakePoint(12, 14)]; [p lineToPoint:NSMakePoint(12, 66)];
            [p moveToPoint:NSMakePoint(88, 14)]; [p lineToPoint:NSMakePoint(88, 66)];
            [p appendBezierPathWithRoundedRect:NSMakeRect(26, 20, 48, 40) xRadius:5 yRadius:5];
            [p stroke];
        } else if ([name isEqualToString:@"prog"]) {
            // F12 programmable key: two overlapping diamonds
            for (int i = 0; i < 2; i++) {
                CGFloat cx = i ? 64 : 36;
                [p moveToPoint:NSMakePoint(cx, 64)]; [p lineToPoint:NSMakePoint(cx + 26, 40)];
                [p lineToPoint:NSMakePoint(cx, 16)]; [p lineToPoint:NSMakePoint(cx - 26, 40)]; [p closePath];
            }
            [p stroke];
        }
        return YES;
    }];
    img.template = YES;
    return img;
}

// popup icon: an SF Symbols name, "hp:name" for one of the drawings above, or "text:xyz" for a key that has a word
// printed on it instead of a picture
static NSImage *iconImage(NSString *symbol, NSString *text) {
    if ([symbol hasPrefix:@"hp:"]) return hpIcon([symbol substringFromIndex:3]);
    if ([symbol hasPrefix:@"text:"]) {
        NSString *word = [symbol substringFromIndex:5];
        NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:52 weight:NSFontWeightMedium],
                                 NSForegroundColorAttributeName: NSColor.blackColor };
        NSSize s = [word sizeWithAttributes:attrs];
        NSImage *img = [NSImage imageWithSize:s flipped:NO drawingHandler:^BOOL(NSRect r) {
            [word drawAtPoint:NSZeroPoint withAttributes:attrs];
            return YES;
        }];
        img.template = YES;     // tinted like the symbols
        return img;
    }
    return [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:text]
        ?: [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:text];
}

static void showOSD(NSString *symbol, NSString *text) {
    const CGFloat size = 200;
    if (!panel) {
        NSRect r = NSMakeRect(0, 0, size, size);
        panel = [[NSPanel alloc] initWithContentRect:r
                                           styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                             backing:NSBackingStoreBuffered defer:NO];
        panel.level = NSStatusWindowLevel;
        panel.opaque = NO;
        panel.backgroundColor = NSColor.clearColor;
        panel.ignoresMouseEvents = YES;
        panel.hasShadow = YES;
        panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary |
                                   NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
        NSVisualEffectView *v = [[NSVisualEffectView alloc] initWithFrame:r];
        v.material = NSVisualEffectMaterialHUDWindow;
        v.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        v.state = NSVisualEffectStateActive;
        // round the blur with a mask image, not a layer corner radius: the window server shapes the window and its
        // shadow from the mask, so the corners don't show a square shadow or unblurred edges
        const CGFloat radius = 22;
        NSImage *mask = [NSImage imageWithSize:NSMakeSize(2 * radius + 1, 2 * radius + 1) flipped:NO drawingHandler:^BOOL(NSRect rr) {
            [NSColor.blackColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rr xRadius:radius yRadius:radius] fill];
            return YES;
        }];
        mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
        mask.resizingMode = NSImageResizingModeStretch;
        v.maskImage = mask;
        panel.contentView = v;

        icon = [[NSImageView alloc] initWithFrame:NSMakeRect(40, 66, 120, 100)];
        icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:68 weight:NSFontWeightRegular];
        icon.contentTintColor = NSColor.labelColor;
        [v addSubview:icon];

        label = [NSTextField labelWithString:@""];
        label.frame = NSMakeRect(8, 26, size - 16, 22);
        label.alignment = NSTextAlignmentCenter;
        label.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
        label.textColor = NSColor.labelColor;
        [v addSubview:label];
    }
    icon.image = iconImage(symbol, text);
    label.stringValue = text;

    // centred, in the lower part of the screen the mouse is on
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *s in NSScreen.screens)
        if (NSPointInRect(NSEvent.mouseLocation, s.frame)) screen = s;
    NSRect f = screen.frame;
    [panel setFrameOrigin:NSMakePoint(NSMidX(f) - size / 2, f.origin.y + f.size.height * 0.14)];

    NSUInteger me = ++shown;
    panel.alphaValue = 1;
    [panel orderFrontRegardless];
    [panel invalidateShadow];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (me != shown) return;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *c) {
            c.duration = 0.35;
            panel.animator.alphaValue = 0;
        } completionHandler:^{
            if (me == shown) [panel orderOut:nil];
        }];
    });
}

static void runKey(NSString *key) {
    NSDictionary *a = keyActions[key];
    if (![a isKindOfClass:NSDictionary.class]) return;
    NSString *symbol = a[@"symbol"], *text = a[@"text"], *cmd = a[@"command"];
    showOSD([symbol isKindOfClass:NSString.class] ? symbol : @"keyboard", [text isKindOfClass:NSString.class] ? text : key);
    if (![cmd isKindOfClass:NSString.class] || !cmd.length) return;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[ @"-c", cmd ];
    NSError *err = nil;
    if (![task launchAndReturnError:&err])
        logmsg("%s: couldn't run '%s': %s\n", key.UTF8String, cmd.UTF8String, err.localizedDescription.UTF8String);
}

static CFMachPortRef insertTap;

static CGEventRef onKeyEvent(CGEventTapProxy p, CGEventType t, CGEventRef e, void *u) {
    if (t == kCGEventTapDisabledByTimeout || t == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(insertTap, true);
        return e;
    }
    bool insert = false;
    if (t == kCGEventKeyDown)
        insert = CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode) == kVK_Help &&
                 !CGEventGetIntegerValueField(e, kCGKeyboardEventAutorepeat);
    else if (t == NX_SYSDEFINED) {
        // in case the help key comes through as a special key instead of a key press
        NSEvent *ne = [NSEvent eventWithCGEvent:e];
        insert = ne.subtype == 8 && ((ne.data1 & 0xFFFF0000) >> 16) == NX_KEYTYPE_HELP && ((ne.data1 & 0xFF00) >> 8) == 0xA;
    }
    if (insert) {
        logmsg("insert key\n");
        showOSD(@"text:insert", @"Insert");
    }
    return e;
}

static void startInsertTap(void) {
    if (!CGPreflightListenEventAccess()) CGRequestListenEventAccess();
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(NX_SYSDEFINED);
    insertTap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionListenOnly, mask, onKeyEvent, NULL);
    if (!insertTap) {
        logmsg("  insert popup off: allow RadioKeys in Privacy & Security > Input Monitoring, then restart it\n");
        return;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(NULL, insertTap, 0), kCFRunLoopCommonModes);
    CGEventTapEnable(insertTap, true);
    logmsg("  insert popup on\n");
}

static OSStatus onHotKey(EventHandlerCallRef h, EventRef e, void *u) {
    EventHotKeyID hk = { 0, 0 };
    GetEventParameter(e, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof hk, NULL, &hk);
    if (hk.id == 16) { runKey(@"F16"); return noErr; }
    if (hk.id == 17) { runKey(@"F17"); return noErr; }

    // F18, airplane
    bool expected = false;
    if (!atomic_compare_exchange_strong(&busy, &expected, true)) return noErr;   // still switching from the last press
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int s = radio_toggle_all();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (s < 0) showOSD(@"exclamationmark.triangle", @"Airplane Mode Failed");
            else if (s) showOSD(@"airplane", @"Airplane Mode Off");
            else showOSD(@"airplane", @"Airplane Mode On");
            atomic_store(&busy, false);
        });
    });
    return noErr;
}

int main(void) {
    @autoreleasepool {
        const char *home = getenv("HOME");
        char path[1024];
        if (home) { snprintf(path, sizeof path, "%s/Library/Logs/radio-toggle.log", home); logfile = fopen(path, "a"); }

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSString *conf = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/RadioKeys/keys.plist"];
        NSDictionary *fromFile = [NSDictionary dictionaryWithContentsOfFile:conf];
        keyActions = fromFile ?: defaultActions();
        logmsg("radio-keys started, %s\n", fromFile ? "keys from keys.plist" : "default keys (no readable keys.plist)");

        EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
        InstallApplicationEventHandler(&onHotKey, 1, &spec, NULL, NULL);
        struct { UInt32 code, id; const char *name; } keys[] = { { kVK_F18, 1, "F18" }, { kVK_F16, 16, "F16" }, { kVK_F17, 17, "F17" } };
        int ok = 0;
        for (int i = 0; i < (int)(sizeof keys / sizeof keys[0]); i++) {
            EventHotKeyRef ref;
            OSStatus st = RegisterEventHotKey(keys[i].code, 0, (EventHotKeyID){ 'RDIO', keys[i].id }, GetApplicationEventTarget(), 0, &ref);
            logmsg("  %s hot key %s (%d)\n", keys[i].name, st == noErr ? "registered" : "FAILED", (int)st);
            ok += st == noErr;
        }
        startInsertTap();
        if (!ok && !insertTap) return 1;
        [NSApp run];
    }
    return 0;
}
