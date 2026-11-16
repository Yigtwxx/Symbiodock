// Symbiodock patch, not part of upstream mediaremote-adapter.
//
// "get" and "stream" describe only the client the system elects, so a second app that
// plays at the same time is invisible: while Music is elected, a stream in Safari is not
// reported at all. These commands list every local now playing client and can send a
// command to one of them.

#include <math.h>
#include <string.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#import "MediaRemoteAdapter.h"
#import "adapter/env.h"
#import "adapter/globals.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"
#import "private/MediaRemote.h"
#import "utility/Debounce.h"
#import "utility/helpers.h"

#define CLIENTS_TIMEOUT_MILLIS 2000
#define CLIENTS_DEBOUNCE_MILLIS 150
// A position this far from where the previous line said playback would be is a seek.
#define CLIENTS_SEEK_TOLERANCE_SECONDS 2.0

static NSString *const kMRAElected = @"elected";
static NSString *const kMRATestClientServiceIdentifier =
    @"com.vandenbe.MediaRemoteAdapter.TestClient";

// Methods of private MediaRemote classes (MRPlayerPath, MRNowPlayingRequest, MRArtwork),
// declared so calls are typed and ARC knows the init family. Every call is preceded by a
// respondsToSelector: check, since nothing here is linked.
@interface NSObject (MRAPrivateMediaRemote)
- (instancetype)initWithOrigin:(id)origin client:(id)client player:(id)player;
- (instancetype)initWithPlayerPath:(id)playerPath;
- (void)requestNowPlayingItemArtworkOnQueue:(dispatch_queue_t)queue
                                 completion:(void (^)(id artwork, NSError *error))completion;
- (void)sendCommand:(uint32_t)command
            options:(NSDictionary *)options
              queue:(dispatch_queue_t)queue
         completion:(void (^)(id result))completion;
- (NSData *)imageData;
@end

#pragma mark - Replies

// Gives the reply to one request, from any thread: runs `record` on the group's queue,
// unless the waiter gave up. Only the first call counts, so a completion that MediaRemote
// calls twice cannot leave the group twice (libdispatch crashes on an unbalanced leave).
typedef void (^MRAReply)(dispatch_block_t record);

// The replies to one read, counted with a dispatch group whose waiter may give up after
// a deadline. Replies that arrive later are dropped, and the group is balanced on giving
// up: libdispatch crashes when a group is released while still entered, which would
// happen if MediaRemote let go of a completion block without calling it.
@interface MRAReplyGroup : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
// On the group's queue only: one more reply to wait for, and the block that gives it.
- (MRAReply)enter;
// Not on the group's queue. YES when every reply arrived in time; once this returns,
// nothing recorded by the replies changes any more.
- (BOOL)waitWithTimeoutMillis:(int)millis;
@end

@implementation MRAReplyGroup {
    dispatch_queue_t _queue;
    dispatch_group_t _group;
    NSInteger _pending; // on _queue
    BOOL _closed;       // on _queue
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    if ((self = [super init])) {
        _queue = queue;
        _group = dispatch_group_create();
    }
    return self;
}

- (MRAReply)enter {
    _pending++;
    dispatch_group_enter(_group);
    __block BOOL replied = NO; // on _queue
    return ^(dispatch_block_t record) {
      dispatch_async(self->_queue, ^{
        if (replied || self->_closed) {
            return;
        }
        replied = YES;
        record();
        self->_pending--;
        dispatch_group_leave(self->_group);
      });
    };
}

- (BOOL)waitWithTimeoutMillis:(int)millis {
    dispatch_group_wait(
        _group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)millis * NSEC_PER_MSEC));
    __block BOOL complete = NO;
    dispatch_sync(_queue, ^{
      complete = self->_pending == 0;
      for (; self->_pending > 0; self->_pending--) {
          dispatch_group_leave(self->_group);
      }
      self->_closed = YES;
    });
    return complete;
}

@end

#pragma mark - Reading

// The signatures of the per-player calls (MRMediaRemoteGetNowPlayingInfoForPlayer takes
// four arguments, MRMediaRemoteGetPlaybackStateForPlayer three) were verified on macOS
// 27.0.1 only. A symbol that exists with another arity on an older system would crash the
// helper instead of failing, so older systems are not asked at all.
static BOOL clientsSupportedByOperatingSystem(void) {
    NSOperatingSystemVersion verified = {
        .majorVersion = 27, .minorVersion = 0, .patchVersion = 0};
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:verified];
}

static BOOL clientsSupported(void) {
    SEL initPath = @selector(initWithOrigin:client:player:);
    SEL initRequest = @selector(initWithPlayerPath:);
    return clientsSupportedByOperatingSystem() &&
           g_mediaRemote.getNowPlayingClients != NULL &&
           g_mediaRemote.getNowPlayingClient != NULL &&
           g_mediaRemote.getLocalOrigin != NULL &&
           g_mediaRemote.getNowPlayingInfoForPlayer != NULL &&
           g_mediaRemote.getPlaybackStateForPlayer != NULL &&
           [g_mediaRemote.playerPathClass instancesRespondToSelector:initPath] &&
           [g_mediaRemote.nowPlayingRequestClass
               instancesRespondToSelector:initRequest];
}

static NSString *nonEmptyString(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value
                                                                         : nil;
}

static NSString *clientBundleIdentifier(id client) {
    return [client respondsToSelector:@selector(bundleIdentifier)]
               ? nonEmptyString([client bundleIdentifier])
               : nil;
}

// A browser's client is its media helper (com.apple.WebKit.GPU); this is the browser.
static NSString *clientParentBundleIdentifier(id client) {
    return [client respondsToSelector:@selector(parentApplicationBundleIdentifier)]
               ? nonEmptyString([client parentApplicationBundleIdentifier])
               : nil;
}

static int clientPID(id client) {
    return [client respondsToSelector:@selector(processIdentifier)]
               ? [client processIdentifier]
               : 0;
}

static BOOL isSameClient(id a, id b) {
    if (a == nil || b == nil || clientPID(a) != clientPID(b)) {
        return NO;
    }
    NSString *left = clientBundleIdentifier(a) ?: @"";
    NSString *right = clientBundleIdentifier(b) ?: @"";
    return [left isEqualToString:right];
}

static id newPlayerPath(id origin, id client) {
    return [[g_mediaRemote.playerPathClass alloc] initWithOrigin:origin
                                                          client:client
                                                          player:nil];
}

// MediaRemote does not say which format an artwork is in; its first bytes do.
static NSString *artworkMimeType(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return @"image/jpeg";
    }
    if (length >= 8 && memcmp(bytes, "\x89PNG\r\n\x1a\n", 8) == 0) {
        return @"image/png";
    }
    if (length >= 4 &&
        (memcmp(bytes, "II*\0", 4) == 0 || memcmp(bytes, "MM\0*", 4) == 0)) {
        return @"image/tiff";
    }
    return nil;
}

// Asks for one client's playback state, information and artwork. Results go into
// `entry` under "state", "info" and "artwork". Runs on the group's queue.
static void requestClient(id client, id origin, NSMutableDictionary *entry,
                          dispatch_queue_t queue, MRAReplyGroup *replies,
                          NSMutableArray *requests) {
    id path = newPlayerPath(origin, client);
    if (path == nil) {
        return;
    }

    MRAReply stateReply = [replies enter];
    g_mediaRemote.getPlaybackStateForPlayer(path, queue, ^(uint32_t state) {
      stateReply(^{
        entry[@"state"] = @(state);
      });
    });

    // The artwork flag is passed as NO: on macOS 27 the info comes back without artwork
    // for Music either way, while the request below has it.
    MRAReply infoReply = [replies enter];
    g_mediaRemote.getNowPlayingInfoForPlayer(
        path, NO, queue, ^(NSDictionary *information) {
          infoReply(^{
            if ([information isKindOfClass:[NSDictionary class]]) {
                entry[@"info"] = information;
            }
          });
        });

    id request =
        [[g_mediaRemote.nowPlayingRequestClass alloc] initWithPlayerPath:path];
    SEL requestArtwork = @selector(requestNowPlayingItemArtworkOnQueue:completion:);
    if (![request respondsToSelector:requestArtwork]) {
        return;
    }
    // Kept until the read is over, so the request is not released while it waits.
    [requests addObject:request];
    MRAReply artworkReply = [replies enter];
    void (^artworkReceived)(id, NSError *) = ^(id artwork, NSError *error) {
      artworkReply(^{
        if (![artwork respondsToSelector:@selector(imageData)]) {
            return;
        }
        NSData *data = [artwork imageData];
        if ([data isKindOfClass:[NSData class]] && data.length > 0) {
            entry[@"artwork"] = data;
        }
      });
    };
    [request requestNowPlayingItemArtworkOnQueue:queue completion:artworkReceived];
}

// Turns what the replies recorded into the payloads that are printed.
static NSArray<NSDictionary *> *clientPayloads(NSArray<NSDictionary *> *entries,
                                               id electedClient) {
    NSMutableArray<NSDictionary *> *payloads = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        id client = entry[@"client"];
        NSDictionary *information = entry[@"info"];
        if (client == nil || information == nil) {
            continue;
        }
        NSString *serviceIdentifier =
            information[kMRMediaRemoteNowPlayingInfoServiceIdentifier];
        if ([serviceIdentifier isKindOfClass:[NSString class]] &&
            [serviceIdentifier isEqualToString:kMRATestClientServiceIdentifier]) {
            continue;
        }
        NSMutableDictionary *payload =
            convertNowPlayingInformation(information, false, false, true);
        id title = payload[kMRATitle];
        if (![title isKindOfClass:[NSString class]] || [title length] == 0) {
            continue;
        }
        NSString *bundleIdentifier = clientBundleIdentifier(client);
        if (bundleIdentifier != nil) {
            payload[kMRABundleIdentifier] = bundleIdentifier;
        }
        NSString *parentBundleIdentifier = clientParentBundleIdentifier(client);
        if (parentBundleIdentifier != nil) {
            payload[kMRAParentApplicationBundleIdentifier] = parentBundleIdentifier;
        }
        payload[kMRAProcessIdentifier] = @(clientPID(client));
        // Typed BOOL so JSON says true/false, as "get" does.
        BOOL playing =
            [entry[@"state"] unsignedIntValue] == kMRPlaybackStatePlaying;
        payload[kMRAPlaying] = @(playing);
        payload[kMRAElected] = @(isSameClient(client, electedClient));
        NSData *artwork = entry[@"artwork"];
        if (artwork != nil) {
            payload[kMRAArtworkData] = artwork;
            NSString *mimeType = artworkMimeType(artwork);
            if (mimeType != nil) {
                payload[kMRAArtworkMimeType] = mimeType;
            }
        }
        [payloads addObject:payload];
    }
    return payloads;
}

// Every local now playing client with a title, in MediaRemote's order. Waits at most
// CLIENTS_TIMEOUT_MILLIS overall; what has not replied by then is left out.
static NSArray<NSDictionary *> *readClients(void) {
    if (!clientsSupported()) {
        return @[];
    }
    id origin = g_mediaRemote.getLocalOrigin();
    if (origin == nil) {
        return @[];
    }

    // A queue per read, so a late reply to an earlier read cannot touch this one.
    dispatch_queue_t queue = dispatch_queue_create(
        "mediaremote-adapter.clients", DISPATCH_QUEUE_SERIAL);
    MRAReplyGroup *replies = [[MRAReplyGroup alloc] initWithQueue:queue];
    // Written on `queue` by the replies only.
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSMutableArray *requests NS_VALID_UNTIL_END_OF_SCOPE = [NSMutableArray array];
    __block id electedClient = nil;

    dispatch_sync(queue, ^{
      MRAReply electedReply = [replies enter];
      g_mediaRemote.getNowPlayingClient(queue, ^(id client) {
        electedReply(^{
          electedClient = client;
        });
      });
      MRAReply clientsReply = [replies enter];
      g_mediaRemote.getNowPlayingClients(queue, ^(NSArray *clients) {
        clientsReply(^{
          if (![clients isKindOfClass:[NSArray class]]) {
              return;
          }
          for (id client in clients) {
              NSMutableDictionary *entry =
                  [NSMutableDictionary dictionaryWithObject:client
                                                     forKey:@"client"];
              [entries addObject:entry];
              requestClient(client, origin, entry, queue, replies, requests);
          }
        });
      });
    });

    if (![replies waitWithTimeoutMillis:CLIENTS_TIMEOUT_MILLIS]) {
        printErrf(@"Reading now playing clients timed out after %d milliseconds",
                  CLIENTS_TIMEOUT_MILLIS);
    }
    return clientPayloads(entries, electedClient);
}

static NSString *serializeClients(NSArray<NSDictionary *> *payloads) {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSDictionary *payload in payloads) {
        NSString *item = serializeJsonDictionarySafe(payload, false);
        if (item != nil) {
            [items addObject:item];
        }
    }
    return [NSString
        stringWithFormat:@"[%@]", [items componentsJoinedByString:@","]];
}

#pragma mark - get-clients

void adapter_get_clients() { printOut(serializeClients(readClients())); }

extern void adapter_get_clients_env() { adapter_get_clients(); }

#pragma mark - stream-clients

// Whether the position moved other than the previous payload said it would: a seek.
static BOOL positionJumped(NSDictionary *previous, NSDictionary *next) {
    id from = previous[kMRAElapsedTime];
    id to = next[kMRAElapsedTime];
    BOOL hadPosition = [from isKindOfClass:[NSNumber class]];
    BOOL hasPosition = [to isKindOfClass:[NSNumber class]];
    if (!hadPosition || !hasPosition) {
        return hadPosition != hasPosition;
    }
    NSTimeInterval passed = 0;
    id since = previous[kMRATimestamp];
    id until = next[kMRATimestamp];
    if ([since isKindOfClass:[NSDate class]] &&
        [until isKindOfClass:[NSDate class]]) {
        passed = [(NSDate *)until timeIntervalSinceDate:since];
    }
    double rate = 0;
    if ([previous[kMRAPlaying] boolValue]) {
        id playbackRate = previous[kMRAPlaybackRate];
        rate = [playbackRate isKindOfClass:[NSNumber class]]
                   ? [playbackRate doubleValue]
                   : 1;
    }
    double predicted = [from doubleValue] + passed * rate;
    return fabs([to doubleValue] - predicted) > CLIENTS_SEEK_TOLERANCE_SECONDS;
}

// Whether `next` tells the reader of `previous` anything new. A playing track's
// position moves on by itself, which the reader can work out; a jump is news.
static BOOL clientsDiffer(NSArray<NSDictionary *> *previous,
                          NSArray<NSDictionary *> *next) {
    if (previous.count != next.count) {
        return YES;
    }
    NSArray<NSString *> *movingKeys = @[ kMRAElapsedTime, kMRATimestamp ];
    for (NSUInteger index = 0; index < next.count; index++) {
        NSMutableDictionary *before = [previous[index] mutableCopy];
        NSMutableDictionary *after = [next[index] mutableCopy];
        [before removeObjectsForKeys:movingKeys];
        [after removeObjectsForKeys:movingKeys];
        if (![before isEqualToDictionary:after] ||
            positionJumped(previous[index], next[index])) {
            return YES;
        }
    }
    return NO;
}

void adapter_stream_clients() {
    NSArray<NSString *> *names = g_mediaRemote.clientNotificationNames;
    if (!clientsSupported() || names.count == 0 ||
        g_mediaRemote.registerForNowPlayingNotifications == NULL ||
        g_mediaRemote.unregisterForNowPlayingNotifications == NULL) {
        printOut(@"[]");
        return;
    }

    // Reads block for up to two seconds; they must not run on the queue MediaRemote
    // posts its notifications on (g_serialdispatchQueue).
    dispatch_queue_t queue = dispatch_queue_create(
        "mediaremote-adapter.stream-clients", DISPATCH_QUEUE_SERIAL);
    Debounce *debounce =
        [[Debounce alloc] initWithDelay:(CLIENTS_DEBOUNCE_MILLIS / 1000.0)
                                  queue:queue];
    __block NSArray<NSDictionary *> *printed = nil; // on `queue`

    void (^refresh)(void) = ^{
      NSArray<NSDictionary *> *clients = readClients();
      if (printed != nil && !clientsDiffer(printed, clients)) {
          return;
      }
      printOut(serializeClients(clients));
      printed = clients;
    };
    // Debounce is not thread-safe; it is only touched on `queue`.
    void (^schedule)(void) = ^{
      dispatch_async(queue, ^{
        [debounce call:refresh];
      });
    };

    dispatch_async(queue, refresh);

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSMutableArray *observers = [NSMutableArray array];
    for (NSString *name in names) {
        [observers addObject:[center addObserverForName:name
                                                 object:nil
                                                  queue:nil
                                             usingBlock:^(NSNotification *note) {
                                               schedule();
                                             }]];
    }
    // A client whose app quits is not always announced before it is gone.
    NSNotificationCenter *workspaceCenter =
        [[NSWorkspace sharedWorkspace] notificationCenter];
    id terminationObserver = [workspaceCenter
        addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
                  schedule();
                }];

    g_mediaRemote.registerForNowPlayingNotifications(g_serialdispatchQueue);

    // Stopped by the SIGINT/SIGTERM handler that stream.m installs for this run loop.
    CFRunLoopRun();

    g_mediaRemote.unregisterForNowPlayingNotifications();
    for (id observer in observers) {
        [center removeObserver:observer];
    }
    [workspaceCenter removeObserver:terminationObserver];
}

extern void adapter_stream_clients_env() { adapter_stream_clients(); }

#pragma mark - send-to

// The client with that process identifier, or nil.
static id findClient(int pid) {
    dispatch_queue_t queue = dispatch_queue_create(
        "mediaremote-adapter.send-to", DISPATCH_QUEUE_SERIAL);
    MRAReplyGroup *replies = [[MRAReplyGroup alloc] initWithQueue:queue];
    __block id found = nil;
    dispatch_sync(queue, ^{
      MRAReply clientsReply = [replies enter];
      g_mediaRemote.getNowPlayingClients(queue, ^(NSArray *clients) {
        clientsReply(^{
          if (![clients isKindOfClass:[NSArray class]]) {
              return;
          }
          for (id client in clients) {
              if (clientPID(client) == pid) {
                  found = client;
                  return;
              }
          }
        });
      });
    });
    [replies waitWithTimeoutMillis:CLIENTS_TIMEOUT_MILLIS];
    return found;
}

void adapter_send_to(MRACommand command, int pid) {
    int value = (int)command;
    if (value < (int)kMRAPlay || value > (int)kMRASkipFifteenSeconds) {
        failf(@"Invalid command: %d", value);
    }
    if (!clientsSupported() || pid <= 0) {
        failf(@"No now playing client with process identifier %d", pid);
    }
    id client = findClient(pid);
    if (client == nil) {
        failf(@"No now playing client with process identifier %d", pid);
    }
    id origin = g_mediaRemote.getLocalOrigin();
    id path = origin != nil ? newPlayerPath(origin, client) : nil;
    id request NS_VALID_UNTIL_END_OF_SCOPE =
        path != nil
            ? [[g_mediaRemote.nowPlayingRequestClass alloc] initWithPlayerPath:path]
            : nil;
    if (![request
            respondsToSelector:@selector(sendCommand:options:queue:completion:)]) {
        failf(@"Cannot send commands to process identifier %d", pid);
    }

    // Wait for the reply so the process lives until the command is on its way.
    // A semaphore created at 0 may be signalled after the wait gave up.
    dispatch_semaphore_t sent = dispatch_semaphore_create(0);
    [request sendCommand:(uint32_t)value
                 options:nil
                   queue:g_serialdispatchQueue
              completion:^(id result) {
                dispatch_semaphore_signal(sent);
              }];
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, CLIENTS_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    if (dispatch_semaphore_wait(sent, timeout) != 0) {
        printErrf(@"Sending command %d to process identifier %d was not "
                  @"confirmed within %d milliseconds",
                  value, pid, CLIENTS_TIMEOUT_MILLIS);
    }
}

extern void adapter_send_to_env() {
    int command = getEnvFuncParamIntSafe(@"adapter_send_to", 0, @"command");
    int pid = getEnvFuncParamIntSafe(@"adapter_send_to", 1, @"pid");
    adapter_send_to((MRACommand)command, pid);
}
