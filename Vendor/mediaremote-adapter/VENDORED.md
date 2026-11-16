# mediaremote-adapter

- Upstream: https://github.com/ungive/mediaremote-adapter
- Version: v0.7.7 (commit e3ff502)
- License: BSD-3-Clause, see `LICENSE`
- Copied: `src/`, `include/`, `bin/mediaremote-adapter.pl`, `LICENSE`.
- Two local changes, both marked "Symbiodock patch". Re-apply them after updating from
  upstream (or drop one if upstream gains the same thing).
  1. `src/test/main.m`: the test client exits when its standard input closes. Upstream keeps
     running when its parent is killed, which left a fake "Unknown Title" Now Playing session
     behind that took over the media keys.
  2. Every now playing client, not only the elected one. `get` and `stream` describe the
     client MediaRemote elects, so a second app playing at the same time (a stream in Safari
     while Music is elected) was never reported. New commands, in Symbiodock's own
     `src/adapter/clients.m`:
     - `get-clients`: a JSON array, one object per local client that has a title (not the
       adapter's test client), with the keys `get` prints plus `elected`; artwork comes from
       `MRNowPlayingRequest`, its MIME type from the data's first bytes. 2 s overall timeout.
     - `stream-clients`: that array as one line at start and whenever it changes (debounced
       150 ms). A position that moves as predicted is not a change; a jump over 2 s is.
     - `send-to <command id> <pid>`: a command to one client through `MRNowPlayingRequest`;
       exits 1 when no client has that pid.
     The calls they need are declared and looked up at run time in `src/private/MediaRemote.h/.m`
     (`MRMediaRemoteGetNowPlayingClients`, `…GetLocalOrigin`, `…GetNowPlayingInfoForPlayer`,
     `…GetPlaybackStateForPlayer`, the `MRPlayerPath` and `MRNowPlayingRequest` classes and
     six notification names). When one is missing, the list commands print `[]` and exit 0
     and `send-to` exits 1. Signatures are the ones seen on macOS 27.0.1.
     `bin/mediaremote-adapter.pl` accepts the three commands; `include/MediaRemoteAdapter.h`
     declares their entry points.

Symbiodock builds the framework and the test client from these sources with Xcode
(see `project.yml`) instead of upstream's CMake build. The framework is bundled with
the app and loaded by `/usr/bin/perl`; the app never links against it.

The license text ships inside the app as `Symbiodock/Resources/ThirdPartyNotices.txt`
(BSD-3-Clause requires it to accompany binaries).

To update: replace the copied files from a newer tag, change the version above, and
refresh `ThirdPartyNotices.txt` if the license or version changed.
