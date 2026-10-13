# gnustep-release-actions

The build, test and release steps that are the same in every app built on
the patched GNUstep stack and on macOS: TopoText's SimpleNotes, ODataKit's
Workbench, FreeCoreData's ModelBuilder, HomeRow, XFormsKit, UDCalc,
UDQuakeTools. Each repository
keeps its own build; everything around it is here, once, and a fix made
here reaches every repository when it moves to the new version.

| Action | What it does |
|---|---|
| [`macos-sign`](macos-sign/action.yml) | Signs an .app with the Developer ID identity in a .p12, inside out (Sparkle's helpers, embedded frameworks, the app), hardened runtime, timestamped |
| [`macos-notarize`](macos-notarize/action.yml) | Notarizes it (Apple's log on rejection), staples the ticket with retries, Gatekeeper's check |
| [`sparkle-appcast`](sparkle-appcast/action.yml) | A release's Sparkle appcast, signed with the EdDSA key |
| [`appimage-update-info`](appimage-update-info/action.yml) | A release's AppImage update information, so the image updates itself from the newest release |
| [`appimage`](appimage/action.yml) | A GNUstep app's AppImage from its `appimage.conf`: the runtime, theme, fonts, opener and the shared launcher ([`AppRun`](appimage/AppRun)), the same in every app's image |
| [`appimage-test`](appimage-test/action.yml) | Runs the repository's `linux-test.sh` against an AppImage on a clean Ubuntu (no GNUstep, no fonts), in a container |
| [`appimage-tools`](appimage-tools/action.yml) | linuxdeploy (pinned) and the AppImage runtime |
| [`gnustep-stack`](gnustep-stack/action.yml) | The patched GNUstep stack, from the image gnustep-patches publishes (`ghcr.io/ashalkhakov/gnustep`, the newest), with the packages building on it needs |
| [`pins`](pins/action.yml) | Loads the repository's pins (`.github/pins.env`) into the job's environment |

Each says what it takes and what it gives in its `action.yml`. They are the
pieces the workflows are made of, used from the workflows' own checkout; a
repository calls the workflows, not these.

## A repository's workflow: one, the same everywhere

A repository has one workflow, `.github/workflows/build.yml`, that builds,
tests and packages every push and pull request, and releases a tag. It calls
the workflows here (macOS, the AppImage, and iOS where it has an iOS app),
which hold the whole of each job, and gives them names; nothing else in it is
its own:

```yaml
name: Build
on:
  push:
    branches: ['**']
    tags: ['v*']
  pull_request:
  workflow_dispatch:
    inputs:
      tag:
        description: 'A v* tag to build and release (empty: this branch, as artifacts)'
        default: ''
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref_name }}
  cancel-in-progress: ${{ github.ref_type != 'tag' }}
permissions:
  contents: write
jobs:
  macos:
    uses: ashalkhakov/gnustep-release-actions/.github/workflows/macos-release.yml@v1
    with:
      tag: ${{ inputs.tag }}
      apps: SimpleNotes=SimpleNotes          # Name=Bundle, space-separated
      dependencies: ODataKit                 # checked out beside it, at its pin
    secrets: inherit
  appimage:
    uses: ashalkhakov/gnustep-release-actions/.github/workflows/appimage-release.yml@v1
    with:
      tag: ${{ inputs.tag }}
      dependencies: FreeCoreData ODataKit
      extra-packages: libsqlite3-dev libpq-dev libmariadb-dev
```

Every run is the same three steps:

1. **Build**, by the repository's build hook: the app, and its unit tests.
2. **Test**, by its test hook: the built app, or the AppImage on a clean
   Ubuntu with no GNUstep and no fonts.
3. **Release**: without a tag, the artifacts, uploaded to the run, unsigned;
   for a `v*` tag (pushed, or given to a run started by hand), the Mac apps
   signed, tested again signed, notarized, their Sparkle appcasts written, the
   AppImage with its update information, all attached to the tag's release (a
   pre-release when the tag has a `-`).

What differs between apps lives in hooks, scripts at fixed paths, run from
the repository's root:

| Hook | Does |
|---|---|
| `.github/release/macos-build.sh` | Builds and runs the unit tests; leaves each app, by bundle name, in `$RELEASE_DIR` |
| `.github/release/macos-test.sh <app>` | Tests an app; for a tag, again once signed (optional) |
| `.github/release/linux-build.sh` | Builds the dependencies and the app on the stack in `$PREFIX`, and runs the unit tests (optional) |
| `.github/release/linux-install.sh` | Installs its apps and tools into `$PREFIX` (`GNUSTEP_INSTALLATION_DOMAIN=SYSTEM`), where the image takes them from |
| `.github/release/appimage.conf` | What the AppImage carries and starts (below) |
| `.github/release/linux-test.sh <image>` | Exercises the AppImage, in a clean Ubuntu 22.04 container (optional) |
| `.github/release/ios-build.sh` | Builds the iOS app(s) into `$RELEASE_DIR/iphoneos` and `$RELEASE_DIR/iphonesimulator` |
| `.github/release/ios-test.sh <app>` | Tests a simulator build (optional) |

The workflows write the version before the build hooks run
([`scripts/stamp-version.sh`](scripts/stamp-version.sh)), by key, into every
Xcode project, `.xcconfig`, Info.plist and app GNUmakefile the repository
has, so a hook passes no version to its build and a repository keeps no
stamping script. The hooks see `TAG`, `APP_VERSION` (`1.2.3`, or
`0.0.0-build<n>` without a tag), `BUILD_NUMBER` (the run's; CFBundleVersion,
which Sparkle compares), `RELEASE_DIR`, `PREFIX` (Linux) and the repository's
pins. The workflows do the rest the same way for everyone: checkout, pins and
dependencies, a universal binary and Sparkle checked, zips named
`<Name>-macOS-<version>.zip`, appcasts (`appcast.xml`, or
`appcast-<Name>.xml` for several apps), the GNUstep stack, the AppImage, and
the uploads.

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
    uses: ashalkhakov/gnustep-release-actions/.github/workflows/docker-release.yml@v1
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
pre-release). The Dockerfiles build on the stack's image, `FROM
ghcr.io/ashalkhakov/gnustep:latest`, rather than building GNUstep.

## GNUstep: one stack, gnustep-patches'

Every app builds on the same patched GNUstep: the stack gnustep-patches
publishes, versioned by its own tags (the date, `v2026.10.13`), as
`ghcr.io/ashalkhakov/gnustep:<version>` and `:latest`, on Ubuntu 22.04 (the
oldest LTS in support, so an AppImage built on it runs on anything newer),
with every component any app uses. The Linux job takes the newest; its log
says which (the stack's VERSION and MANIFEST, the commit of each component).
A fix to GNUstep reaches every app as one new stack, released in one place.

## Pins: one place per repository

Every commit of ours a repository builds on (FreeCoreData, ODataKit, ...)
is named once, in `.github/pins.env`:

```sh
# What this repository builds on; moved here and nowhere else.
FREECOREDATA_REF=5bfd5a87179cff43e0a8a55622fc00f01951c88a
ODATAKIT_REF=de46fce6bd0bd1c7f2c7a5a59a1fcae0e5a9f5c8
```

The workflows load it right after checking the repository out, check each
dependency out beside it at its pin (`<NAME>_REF`: ODataKit's is
`ODATAKIT_REF`), and give the pins to the hooks; a script reads the same file
for its defaults (`. .github/pins.env`). A pin is a full commit hash: a
branch or a short hash is refused.

## In the app

- **macOS:** Sparkle 2 (the same version as `sparkle-appcast`'s), a *Check
  for Updates…* menu item, and in `Info.plist` `SUFeedURL`
  (`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`)
  and `SUPublicEDKey`. TopoText's `Examples/SimpleNotes/AppKit/SNUpdater.h`
  is the pattern: Sparkle on macOS, nothing on GNUstep, where the AppImage
  is updated from outside.
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
pull request against real apps at pinned commits (UDCalc for macOS and the
AppImage, TopoText for iOS), with no tag: nothing signed, nothing released.
Move those pins when an app's hooks change. A merge is released by tagging it
`v1.<n>.0` and moving `v1` to it.

## License

LGPL 2.1 or later (`LICENSE`).
