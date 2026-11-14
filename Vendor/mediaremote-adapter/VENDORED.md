# mediaremote-adapter

- Upstream: https://github.com/ungive/mediaremote-adapter
- Version: v0.7.7 (commit e3ff502)
- License: BSD-3-Clause, see `LICENSE`
- Copied: `src/`, `include/`, `bin/mediaremote-adapter.pl`, `LICENSE`.
- One local change, marked "Symbiodock patch" in `src/test/main.m`: the test client exits
  when its standard input closes. Upstream keeps running when its parent is killed, which
  left a fake "Unknown Title" Now Playing session behind that took over the media keys.
  Re-apply it after updating from upstream (or drop it if upstream fixes this).

Symbiodock builds the framework and the test client from these sources with Xcode
(see `project.yml`) instead of upstream's CMake build. The framework is bundled with
the app and loaded by `/usr/bin/perl`; the app never links against it.

The license text ships inside the app as `Symbiodock/Resources/ThirdPartyNotices.txt`
(BSD-3-Clause requires it to accompany binaries).

To update: replace the copied files from a newer tag, change the version above, and
refresh `ThirdPartyNotices.txt` if the license or version changed.
