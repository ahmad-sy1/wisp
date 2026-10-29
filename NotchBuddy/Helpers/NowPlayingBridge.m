// NowPlayingBridge — tiny dylib loaded by /usr/bin/perl (see NowPlayingService.swift).
//
// Since macOS 15.4, MediaRemote only answers Apple-signed processes, so Coucou can't
// ask it directly. The system perl is Apple-signed: it loads this dylib, which streams
// "now playing" changes (any app: Spotify, YouTube in a browser, Music…) as JSON lines
// on stdout and reads commands ("toggle", "next", "previous") on stdin.
// Event-driven: no polling. Exits when stdin closes (Coucou quit or crashed).

#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientStringFn)(id);
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);

static MRGetInfoFn getInfo;
static MRGetIsPlayingFn getIsPlaying;
static MRGetClientFn getClient;
static MRClientStringFn clientBundleId, clientParentBundleId;
static MRSendCommandFn sendCommand;
static NSString *lastArtworkKey;
static BOOL emitScheduled;

static void writeLine(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void emit(void) {
    dispatch_queue_t q = dispatch_get_main_queue();
    getInfo(q, ^(NSDictionary *info) {
        getIsPlaying(q, ^(Boolean playing) {
            getClient(q, ^(id client) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"playing"] = playing ? @YES : @NO;
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if (title.length) out[@"title"] = title;
                NSString *artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
                if (artist.length) out[@"artist"] = artist;
                NSString *album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
                if (album.length) out[@"album"] = album;
                NSNumber *duration = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
                if (duration) out[@"duration"] = duration;
                // Position = elapsed at `timestamp`, advancing at `rate` while playing.
                NSNumber *elapsed = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
                if (elapsed) out[@"elapsed"] = elapsed;
                NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if ([stamp isKindOfClass:NSDate.class]) out[@"timestamp"] = @(stamp.timeIntervalSince1970);
                NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                if (rate) out[@"rate"] = rate;
                if (client && clientBundleId) {
                    NSString *bid = (__bridge NSString *)clientBundleId(client);
                    if (bid) out[@"bundle"] = bid;
                    NSString *parent = clientParentBundleId ? (__bridge NSString *)clientParentBundleId(client) : nil;
                    if (parent) out[@"parent"] = parent;
                }
                // Artwork only when it changes: it is the heavy part of the line.
                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSString *artKey = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"]
                    ?: (art ? [NSString stringWithFormat:@"%@|%lu", title, (unsigned long)art.length] : @"");
                if (![artKey isEqualToString:lastArtworkKey ?: @"\x01"]) {
                    lastArtworkKey = artKey;
                    out[@"artwork"] = art ? [art base64EncodedStringWithOptions:0] : @"";
                }
                writeLine(out);
            });
        });
    });
}

/// Coalesces bursts of notifications (a track change fires several) into one line.
static void scheduleEmit(void) {
    if (emitScheduled) return;
    emitScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        emitScheduled = NO;
        emit();
    });
}

static NSString *constant(void *mr, const char *name) {
    CFStringRef *p = dlsym(mr, name);
    return p ? (__bridge NSString *)*p : [NSString stringWithUTF8String:name];
}

__attribute__((visibility("default"))) void nb_now_playing_run(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { fprintf(stderr, "MediaRemote unavailable\n"); exit(2); }
    MRRegisterFn reg = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    getInfo        = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying   = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient      = dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    clientBundleId = dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundleId = dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    sendCommand    = dlsym(mr, "MRMediaRemoteSendCommand");
    if (!reg || !getInfo || !getIsPlaying || !getClient) { fprintf(stderr, "MediaRemote symbols missing\n"); exit(2); }

    reg(dispatch_get_main_queue());
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    const char *names[] = {
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(*names); i++) {
        [nc addObserverForName:constant(mr, names[i]) object:nil queue:nil
                    usingBlock:^(NSNotification *n) { scheduleEmit(); }];
    }

    // Commands from Coucou, one per line. EOF means Coucou is gone: quit with it.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char line[64];
        while (fgets(line, sizeof line, stdin)) {
            NSString *cmd = [[NSString stringWithUTF8String:line]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            int code = [cmd isEqualToString:@"toggle"] ? 2
                     : [cmd isEqualToString:@"next"] ? 4
                     : [cmd isEqualToString:@"previous"] ? 5 : -1;
            if (code >= 0 && sendCommand) {
                dispatch_async(dispatch_get_main_queue(), ^{ sendCommand(code, nil); });
            }
        }
        exit(0);
    });

    emit();
    CFRunLoopRun();
}
