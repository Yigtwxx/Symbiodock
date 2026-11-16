// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_H
#define MEDIAREMOTEADAPTER_ADAPTER_H

#import <Foundation/Foundation.h>

// Methods suffixed with "_env" read its parameters from the environment.
// Parameters must have the format:
// MEDIAREMOTEADAPTER_<FUNC_NAME>_<PARAM_INDEX>_<PARAM_NAME>
// Example: MEDIAREMOTEADAPTER_adapter_send_0_command

extern NSString *kMRAProcessIdentifier;
extern NSString *kMRABundleIdentifier;
extern NSString *kMRAParentApplicationBundleIdentifier;
extern NSString *kMRAPlaying;

extern NSString *kMRADurationMicros;
extern NSString *kMRAElapsedTimeMicros;
extern NSString *kMRATimestampEpochMicros;

extern NSString *kMRAElapsedTimeNow;
extern NSString *kMRAElapsedTimeNowMicros;

extern NSString *kMRATitle;
extern NSString *kMRAArtist;
extern NSString *kMRAAlbum;
extern NSString *kMRADuration;
extern NSString *kMRAElapsedTime;
extern NSString *kMRATimestamp;
extern NSString *kMRAArtworkMimeType;
extern NSString *kMRAArtworkData;

extern NSString *kMRAChapterNumber;
extern NSString *kMRAComposer;
extern NSString *kMRAGenre;
extern NSString *kMRAIsAdvertisement;
extern NSString *kMRAIsBanned;
extern NSString *kMRAIsInWishList;
extern NSString *kMRAIsLiked;
extern NSString *kMRAIsMusicApp;
extern NSString *kMRAPlaybackRate;
extern NSString *kMRAProhibitsSkip;
extern NSString *kMRAQueueIndex;
extern NSString *kMRARadioStationIdentifier;
extern NSString *kMRARepeatMode;
extern NSString *kMRAShuffleMode;
extern NSString *kMRAStartTime;
extern NSString *kMRASupportsFastForward15Seconds;
extern NSString *kMRASupportsIsBanned;
extern NSString *kMRASupportsIsLiked;
extern NSString *kMRASupportsRewind15Seconds;
extern NSString *kMRATotalChapterCount;
extern NSString *kMRATotalDiscCount;
extern NSString *kMRATotalQueueCount;
extern NSString *kMRATotalTrackCount;
extern NSString *kMRATrackNumber;
extern NSString *kMRAUniqueIdentifier;
extern NSString *kMRAContentItemIdentifier;
extern NSString *kMRARadioStationHash;
extern NSString *kMRAMediaType;

// Prints the current MediaRemote now playing information to stdout.
// Data is encoded as a JSON dictionary or "null" when there is no information.
extern void adapter_get();
extern void adapter_get_env();

// Streams MediaRemote now playing updates to stdout.
// Each update is printed on a separate lined, encoded as a JSON dictionary.
// Exits when the process receives a SIGTERM signal.
extern void adapter_stream();
extern void adapter_stream_env();

typedef enum {
    kMRAPlay = 0,
    kMRAPause = 1,
    kMRATogglePlayPause = 2,
    kMRAStop = 3,
    kMRANextTrack = 4,
    kMRAPreviousTrack = 5,
    kMRAToggleShuffle = 6,
    kMRAToggleRepeat = 7,
    kMRAStartForwardSeek = 8,
    kMRAEndForwardSeek = 9,
    kMRAStartBackwardSeek = 10,
    kMRAEndBackwardSeek = 11,
    kMRAGoBackFifteenSeconds = 12,
    kMRASkipFifteenSeconds = 13,
} MRACommand;

// Sends the given MediaRemote command to the current now playing application.
extern void adapter_send(MRACommand command);
extern void adapter_send_env();

// Seeks the timeline of the nowplaying application to the given position.
// The position must be given in microseconds.
extern void adapter_seek(long position);
extern void adapter_seek_env();

typedef enum {
    kMRAShuffleDisabled = 1,
    kMRAShuffleAlbums = 2,
    kMRAShuffleTracks = 3,
} MRAShuffleMode;

extern void adapter_shuffle(MRAShuffleMode mode);
extern void adapter_shuffle_env();

typedef enum {
    kMRARepeatDisabled = 1,
    kMRARepeatTrack = 2,
    kMRARepeatPlaylist = 3,
} MRARepeatMode;

extern void adapter_repeat(MRARepeatMode mode);
extern void adapter_repeat_env();

extern void adapter_speed(int speed);
extern void adapter_speed_env();

// Tests whether the process is entitled to use the MediaRemote framework.
// Exits with exit code 0, if it is. Any other exit code means it is not.
extern void adapter_test();

// Symbiodock patch: every local now playing client, not only the elected one.

// Prints a JSON array with one dictionary per now playing client that has a title.
// Each holds the keys "get" prints, plus "elected" (the client "get" describes).
// Prints "[]" when this macOS lacks any of the calls it needs.
extern void adapter_get_clients();
extern void adapter_get_clients_env();

// Prints that array as one line at start and whenever it changes.
// Exits when the process receives a SIGTERM signal.
extern void adapter_stream_clients();
extern void adapter_stream_clients_env();

// Sends the given command to the now playing client with the given process
// identifier. Exits with 1 when no such client exists.
extern void adapter_send_to(MRACommand command, int pid);
extern void adapter_send_to_env();

#endif // MEDIAREMOTEADAPTER_ADAPTER_H
