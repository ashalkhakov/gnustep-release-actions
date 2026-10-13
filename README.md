# gnustep-release-actions

The release steps that are the same in every app built on the patched
GNUstep stack and on macOS: TopoText's SimpleNotes, ODataKit's Workbench,
FreeCoreData's ModelBuilder, HomeRow, XFormsKit, UDCalc. Each repository
keeps its own build; everything around it is here, once, and a fix made
here reaches every repository when it moves to the new version.

| Action | What it does |
|---|---|
| [`macos-sign`](macos-sign/action.yml) | Signs an .app with the Developer ID identity in a .p12, inside out (Sparkle's helpers, embedded frameworks, the app), hardened runtime, timestamped |
| [`macos-notarize`](macos-notarize/action.yml) | Notarizes it (Apple's log on rejection), staples the ticket with retries, Gatekeeper's check |
| [`sparkle-appcast`](sparkle-appcast/action.yml) | A release's Sparkle appcast, signed with the EdDSA key |
| [`appimage-update-info`](appimage-update-info/action.yml) | A release's AppImage update information, so the image updates itself from the newest release |
| [`appimage-tools`](appimage-tools/action.yml) | linuxdeploy (pinned) and the AppImage runtime |
| [`gnustep-stack`](gnustep-stack/action.yml) | The patched GNUstep stack (gnustep-patches' `build-gnustep.sh`), cached by its recipe |
| [`pins`](pins/action.yml) | Loads the repository's pins (`.github/pins.env`) into the job's environment |

Each says what it takes and what it gives in its `action.yml`.

## A repository's release: the same everywhere

A repository does not assemble its release from these actions: it calls the
two release workflows, which hold the whole of each job, and gives them
names. Its `.github/workflows/release.yml` is this, with only the names its
own:

```yaml
name: Release
on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      tag:
        description: 'A v* tag to build and attach to its release (empty: this branch, artifacts only)'
        default: ''
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
      appimage: SimpleNotes                  # SimpleNotes-<version>-x86_64.AppImage
      dependencies: FreeCoreData ODataKit
      extra-packages: libsqlite3-dev libpq-dev libmariadb-dev
```

What differs between apps lives in hooks, scripts at fixed paths, run from
the repository's root:

| Hook | Does |
|---|---|
| `.github/release/macos-build.sh` | Builds; leaves each app, by bundle name, in `$RELEASE_DIR` |
| `.github/release/macos-test.sh <app>` | Tests an app, before signing and again once signed (optional) |
| `.github/release/linux-build.sh` | Builds the dependencies and the app on the stack in `$PREFIX` |
| `.github/release/linux-package.sh` | Makes `<appimage>-<version>-x86_64.AppImage` in the root, with `$LINUXDEPLOY` |
| `.github/release/linux-test.sh <image>` | Exercises the AppImage, in a clean Ubuntu 22.04 container (optional) |

They see `TAG`, `APP_VERSION` (`1.2.3`, or `0.0.0-build<n>` without a tag),
`BUILD_NUMBER` (the run's; CFBundleVersion, which Sparkle compares) and the
repository's pins. The workflows do the rest the same way for everyone:
checkout, pins and dependencies, a universal binary and Sparkle checked,
signing, notarizing, zips named `<Name>-macOS-<version>.zip`, appcasts
(`appcast.xml`, or `appcast-<Name>.xml` for several apps), the GNUstep stack,
update information and the `.zsync`, uploads, and a tag's release (a
pre-release when the tag has a `-`).

The actions below are what the workflows are made of; a repository uses them
directly only for something that is not a release (its CI's stack, its pins).

## Pins: one place per repository

Every commit a repository builds on (gnustep-patches, FreeCoreData,
ODataKit, ...) is named once, in `.github/pins.env`:

```sh
# What this repository builds on; moved here and nowhere else.
GNUSTEP_PATCHES_REF=dcbad8f6db6db7054bc9152aad3e8686a233809d
FREECOREDATA_REF=5bfd5a87179cff43e0a8a55622fc00f01951c88a
```

Each workflow job loads it right after checking the repository out, and
uses the names from there on (`ref: ${{ env.GNUSTEP_PATCHES_REF }}`); a
script reads the same file for its defaults (`. .github/pins.env`). A pin is
a full commit hash: the action refuses a branch or a short hash.

```yaml
- uses: actions/checkout@v4
  with: { path: source }
- uses: ashalkhakov/gnustep-release-actions/pins@v1
  with: { file: source/.github/pins.env }
- uses: actions/checkout@v4
  with:
    repository: ashalkhakov/gnustep-patches
    ref: ${{ env.GNUSTEP_PATCHES_REF }}
    path: gnustep-patches
```

## In the app

- **macOS:** Sparkle 2 (the same version as `sparkle-appcast`'s), a *Check
  for Updates…* menu item, and in `Info.plist` `SUFeedURL`
  (`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`)
  and `SUPublicEDKey`. TopoText's `Examples/SimpleNotes/AppKit/SNUpdater.h`
  is the pattern: Sparkle on macOS, nothing on GNUstep, where the AppImage
  is updated from outside.
- **Secrets**, in the repository's `production` environment:
  `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`
  (optional), `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` and
  `SPARKLE_PRIVATE_KEY`. Each is optional: without it, its step is skipped,
  and says so.

## License

LGPL 2.1 or later (`LICENSE`).
