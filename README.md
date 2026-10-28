# gnustep-release-actions

The build, test and release steps that are the same in every app built on
the patched GNUstep stack and on macOS: TopoText's SimpleNotes, ODataKit's
Workbench, FreeCoreData's ModelBuilder, HomeRow, XFormsKit, UDCalc,
UDQuakeTools, and the libraries they build on (FreeCoreData, ODataKit).
Each repository keeps its own build, in its makefiles; everything around it
is here, once, and a fix made here reaches every repository at once.

| Action | What it does |
|---|---|
| [`macos-sign`](macos-sign/action.yml) | Signs an .app with the Developer ID identity in a .p12, inside out (Sparkle's helpers, embedded frameworks, the app), hardened runtime, timestamped |
| [`macos-notarize`](macos-notarize/action.yml) | Notarizes it (Apple's log on rejection), staples the ticket with retries, Gatekeeper's check |
| [`sparkle-appcast`](sparkle-appcast/action.yml) | A release's Sparkle appcast, signed with the EdDSA key |
| [`appimage-update-info`](appimage-update-info/action.yml) | A release's AppImage update information, so the image updates itself from the newest release |
| [`appimage`](appimage/action.yml) | A GNUstep app's AppImage from its `appimage.conf`: the runtime, theme, fonts, opener and the shared launcher ([`AppRun`](appimage/AppRun)), the same in every app's image |
| [`appimage-test`](appimage-test/action.yml) | The AppImage's smoke test (`SMOKE` or `SMOKE_SCRIPT` in its `appimage.conf`) on a clean Ubuntu (no GNUstep, no fonts), in a container |
| [`appimage-tools`](appimage-tools/action.yml) | linuxdeploy (pinned) and the AppImage runtime |

Each says what it takes and what it gives in its `action.yml`. They are the
pieces the workflows are made of, used from the workflows' own checkout; a
repository calls the workflows, not these.

## A repository: built, tested and installed the familiar way

Every repository, a library or an application, is built the same way, by
its own makefiles; the workflows here only call them, and package what they
install:

| | Linux: `GNUmakefile` | macOS: `Makefile.apple` |
|---|---|---|
| build | `make` | `make -f Makefile.apple` |
| test | `make check` | `make -f Makefile.apple check` |
| install | `make install DESTDIR=<dir>` | `make -f Makefile.apple install DESTDIR=<dir>` |
| test what was installed (optional) | | `make -f Makefile.apple installcheck DESTDIR=<dir>` |
| iOS (where it has an iOS app) | | `ios`, `ios-check`, `ios-install DESTDIR=<dir>`, `ios-installcheck` |

`install` puts into `DESTDIR`:
- on Linux, what the repository installs into the GNUstep prefix
  (`DESTDIR/opt/gnustep/...`, gnustep-make's own `DESTDIR`);
- on macOS, each app by its bundle name (`DESTDIR/SimpleNotes.app`), and a
  library's XCFrameworks (`DESTDIR/ODataKit.xcframework`);
- for iOS, each app in `DESTDIR/iphoneos` and `DESTDIR/iphonesimulator`.

[`test/sample`](test/sample) is the smallest repository that does all of it,
and what this repository's own test builds.

### What it builds on: `.github/pins.env`, exact versions

```sh
GNUSTEP_PATCHES_VERSION=2026.10.13   # the GNUstep stack (gnustep-patches' release)
FREECOREDATA_VERSION=0.5.0           # our libraries, each a release
SPARKLE_VERSION=2.10.0               # Sparkle (Apple)
```

Each `<NAME>_VERSION` is a release of `ashalkhakov/<name>` (the name in
capitals, `-` as `_`), fetched by [`scripts/deps.sh`](scripts/deps.sh): on
Linux its `<name>-<version>-ubuntu22.04-<arch>.tar.xz`, unpacked into
`/opt/gnustep`, the stack first; on Apple its `<name>-<version>-apple.zip`
(its XCFrameworks), and Sparkle's, unpacked into `.deps/`, where the Xcode
projects find them. On your own machine, the same script does the same
(`scripts/deps.sh linux` or `apple`, from the repository's root). A library
publishes exactly those files for each of its releases.

A library's optional parts, which most apps need not carry, are archives of
their own: FreeCoreData's PostgreSQL and MySQL stores link their databases'
client libraries, and only a server wants them. The library names them in
`.github/release/parts.conf` ([`scripts/library-archive.sh`](scripts/library-archive.sh)),
and an app asks for the ones it uses:

```sh
FREECOREDATA_VERSION=0.11.0
FREECOREDATA_PARTS="postgresql mysql"  # freecoredata-postgresql-<version>-..., and mysql's
```

### `.github/workflows/build.yml`: names only

```yaml
name: Build
on:
  push:
    branches: ['**']
    tags: ['v*']
  workflow_dispatch:
    inputs:
      tag:
        description: 'A v* tag to build and release (empty: this branch, as artifacts)'
        default: ''
concurrency:
  group: ${{ github.workflow }}-${{ github.ref_name }}
  cancel-in-progress: ${{ github.ref_type != 'tag' }}
permissions:
  contents: write
jobs:
  linux:
    uses: ashalkhakov/gnustep-release-actions/.github/workflows/linux.yml@v1
    with:
      tag: ${{ inputs.tag }}
      library: true                          # a library: publish its archives (x86_64, aarch64)
      extra-packages: libsqlite3-dev libpq-dev
      databases: postgres mysql mariadb      # for make check: POSTGRES_URL, ...
  windows:
    uses: ashalkhakov/gnustep-release-actions/.github/workflows/windows.yml@v1
    with:
      tag: ${{ inputs.tag }}
      library: true                          # a library: publish its archive
      extra-packages: sqlite3 postgresql     # MSYS2 CLANG64 packages, short names
      databases: postgres mysql mariadb      # the same variables as on Linux
    secrets: inherit                         # the Sparkle key, for updates
  macos:
    uses: ashalkhakov/gnustep-release-actions/.github/workflows/macos.yml@v1
    with:
      tag: ${{ inputs.tag }}
      apps: SimpleNotes=SimpleNotes          # an app: Name=Bundle, space-separated
      library: true                          # a library: publish its XCFrameworks
    secrets: inherit
```

It runs on pushes, not on pull requests too: a push to a branch already shows
its checks on the branch's pull request. Every run builds, tests, installs and
uploads; without a tag, unsigned, kept two weeks. A `v*` tag (pushed, or given
to a run started by hand) also releases: the Mac apps signed, checked again
signed, notarized, their Sparkle appcasts written; the AppImage with its
update information; a library's archives and XCFrameworks; all attached to
the tag's release (a pre-release when the tag has a `-`).

The workflows write the version first ([`scripts/stamp-version.sh`](scripts/stamp-version.sh)),
by key, into every Xcode project, `.xcconfig`, Info.plist and app GNUmakefile,
so a repository keeps no stamping of its own: `APP_VERSION` (`1.2.3`, or
`0.0.0-build<n>`) and `BUILD_NUMBER` (CFBundleVersion, which Sparkle
compares: 1000 and the commit count, so the same commit has the same number
whatever workflow builds it, and it only goes up; the workflows check out the
whole history for it, [`scripts/version.sh`](scripts/version.sh)). `databases:` starts PostgreSQL, MySQL and MariaDB for `make
check`, and hands it `POSTGRES_URL`, `MYSQL_URL`, `MARIADB_URL`
([`scripts/databases.sh`](scripts/databases.sh)); `CI` is set, so a test that
was not given its service fails rather than skips. On Windows the same
servers run on the runner itself, with the same ports, users and variables
([`scripts/databases-windows.ps1`](scripts/databases-windows.ps1)): its
Docker runs Windows containers only.

An application with an AppImage has `.github/release/appimage.conf` (below);
one with Docker images, `docker.yml` and, optionally,
`.github/release/docker-test.sh <target> <image>`, which exercises an image
it is given.

## The Windows installer

[`windows.yml`](.github/workflows/windows.yml) builds in MSYS2's CLANG64 on
the GNUstep stack, as Linux does. An application with
`.github/release/windows.conf` also gets an installer,
`<NAME>-<version>-win64.msi`, made by [`msi/`](msi/msi.sh) with
gnustep-packager: its apps, the GNUstep runtime beside them, WinUXTheme
(Windows' own look, menus in the window). `NAME`, `APPS` and `DEFAULT` are
needed; `ICON` is an `.ico` or a PNG of at most 256x256. The installed app is
smoke-tested with only Windows and its runtime on `PATH`: `SMOKE` starts it
with arguments it must exit 0 from (a self-test), or, for an app with none,
`SMOKE_STAYS_UP` the seconds it must still be running, its nibs loaded.

`keep-build: true` uploads the build before `make check` (with
`keep-build-make`, the checks' programs built first): a `.tar.xz` with the
stack and CLANG64's DLLs and a `run.bat`, to run any of its programs on a
Windows machine, or `run-under-wine.sh` under Wine. `make check` has 45
minutes; one that fails or hangs leaves the same bundle for a week.

## The AppImage: one launcher, one packager

An app does not carry its own `AppRun`, opener, fontconfig or packaging
scripts: those are [`appimage/`](appimage/)'s, and a fix there reaches every
app's next image. What is the app's own is a few names, in
`.github/release/appimage.conf`:

```sh
IMAGE=SimpleNotes                         # SimpleNotes-<version>-x86_64.AppImage
NAME=SimpleNotes                          # its caches and temporary files
APPS="SimpleNotes"                        # the .app wrappers it carries
TOOLS="simplenotes-server"                # the command-line tools
DEFAULT=SimpleNotes                       # what opening the image starts
ROUTES="server,--server,simplenotes-server=simplenotes-server app,simplenotes=SimpleNotes"
ENTRIES="Scripts/appimage/simplenotes.desktop=Examples/SimpleNotes/Icons/SimpleNotes.png"
METAINFO=Scripts/appimage/io.github.ashalkhakov.SimpleNotes.appdata.xml
LOADED="libCD*Store.so"                   # loaded at run time, not linked
REQUIRE="SimpleNotes.momd"                # must be in the image
```

[`appimage.sh`](appimage/appimage.sh) lists every name and what it does
(`WITH_ARGUMENTS`, `WITH_FILE` and `FIXED_PITCH_FONT` too). The image's
launcher gives every app the Eau theme, the fonts it carries (with a
fontconfig written at launch), the opener for URLs, Ctrl as Command, and
`APPIMAGE_GDB=1` to run under gdb.

## Docker images

A repository that publishes images (SimpleNotes' server, ODataKit's SDK and
services) adds one more job to its `build.yml`:

```yaml
  docker:
    uses: ashalkhakov/gnustep-release-actions/.github/workflows/docker.yml@v1
    with:
      tag: ${{ inputs.tag }}
      dockerfile: Docker/server.Dockerfile
      images: =simplenotes-server            # target=name, space-separated
      description: SimpleNotes' server
    permissions:
      contents: read
      packages: write
```

Each image is built for amd64 and arm64 on runners of their own, with the
version stamped first, and checked by `.github/release/docker-test.sh
<target> <image>` when the repository has one; a tag pushes them to
`ghcr.io/<owner>/<name>:<version>` (and `:latest` for a release that is not a
pre-release). The Dockerfiles take what they build on as CI does: the
stack's and the libraries' archives, by the versions in `.github/pins.env`,
which arrive as build arguments of the same names (`GNUSTEP_PATCHES_VERSION`,
...), with `VERSION`, the version being built.

## GNUstep: one stack, gnustep-patches'

Every repository builds on the same patched GNUstep: the stack gnustep-patches
publishes for each of its releases (the date, `v2026.10.13`), an archive of
`/opt/gnustep` on Ubuntu 22.04 (the oldest LTS in support, so an AppImage
built on it runs on anything newer), for x86_64 and aarch64, with every
component any repository uses, and in `/opt/gnustep/share/gnustep-patches`
what it is: its VERSION, MANIFEST (the commit of each component) and the
packages building on it needs. A fix to GNUstep reaches a repository when its
`GNUSTEP_PATCHES_VERSION` moves to the release that carries it.

## In the app

- **macOS:** Sparkle 2 (the same version as `sparkle-appcast`'s), a *Check
  for Updates…* menu item, and in `Info.plist` `SUFeedURL`
  (`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`)
  and `SUPublicEDKey`. TopoText's `Examples/SimpleNotes/AppKit/SNUpdater.h`
  is the pattern: Sparkle on macOS, nothing on GNUstep, where the AppImage
  is updated from outside.
- **Windows:** the stack's `GSUpdater` (`#import <GSUpdater/GSUpdater.h>`,
  `-lGSUpdater`): `initStarting:YES` at launch, and a *Check for Updates…*
  menu item sent `checkForUpdates:` and shown when `available`. It is
  WinSparkle, which `deps.sh` fetches (0.9.4 unless `pins.env` names a
  `WINSPARKLE_VERSION`) and the installer carries; the installer writes what
  it reads into each app's `Info-gnustep.plist`: `CFBundleVersion` (the
  build), `SUWindowsFeedURL` (the latest release's `appcast-windows.xml`,
  which a tag's run writes and signs) and `SUPublicEDKey` (the Sparkle key's
  public half). On Linux `GSUpdater` is never `available`. The caller passes
  `secrets: inherit` to `windows.yml` as to `macos.yml`.
- **Secrets**, in the repository's `production` environment, read by a
  tag's run only: `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PASSWORD`,
  `MACOS_SIGN_IDENTITY` (optional), `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`,
  `NOTARY_PASSWORD` and `SPARKLE_PRIVATE_KEY`. Without them a tag's Mac apps
  are released unsigned, named so, and the run says why.

## Changing this repository

The workflows check this repository out at their own commit
(`job.workflow_sha`) and take every script and action from there, whatever
ref the caller named: a branch here is tested as a whole, and `v1` is exactly
what `v1` holds. [`test.yml`](.github/workflows/test.yml) runs them on every
pull request on [`test/sample`](test/sample), with no tag: nothing signed,
nothing released. A merge is released by tagging it `v1.<n>.0` and moving
`v1` to it.

## License

LGPL 2.1 or later (`LICENSE`).
