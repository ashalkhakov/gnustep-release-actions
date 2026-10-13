# The sample

What gnustep-release-actions' own test (`.github/workflows/test.yml`) builds:
the smallest repository that has everything the workflows handle, laid out
as an application's is. Its makefiles are the contract every repository
follows:

| | Linux (`GNUmakefile`) | macOS (`Makefile.apple`) |
|---|---|---|
| build | `make` | `make -f Makefile.apple` (and `ios`) |
| test | `make check` | `make -f Makefile.apple check` (and `ios-check`) |
| install | `make install DESTDIR=…` | `make -f Makefile.apple install DESTDIR=…` (and `ios-install`) |
| test what was installed | | `installcheck`, `ios-installcheck` |

- `SampleKit/`: a library. On Linux it is installed into the GNUstep
  prefix; on macOS `install` makes `SampleKit.xcframework` (macOS, iOS and
  the simulator).
- `SampleApp/`: an application on it: a GNUstep app (and its AppImage,
  `.github/release/appimage.conf`), a Mac app (universal, with Sparkle, from
  `.deps/`) and an iOS app. `--self-test` checks it runs and exits 0.
- `.github/pins.env`: what it builds on: the GNUstep stack and Sparkle.
