# mediaremote-adapter

- Upstream: https://github.com/ungive/mediaremote-adapter
- Version: v0.7.7 (commit e3ff502)
- License: BSD-3-Clause, see `LICENSE`
- Copied: `src/`, `include/`, `bin/mediaremote-adapter.pl`, `LICENSE`. Nothing is modified.

Symbiodock builds the framework and the test client from these sources with Xcode
(see `project.yml`) instead of upstream's CMake build. The framework is bundled with
the app and loaded by `/usr/bin/perl`; the app never links against it.

To update: replace the copied files from a newer tag and change the version above.
