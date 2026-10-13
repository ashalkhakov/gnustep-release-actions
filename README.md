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

Each says what it takes and what it gives in its `action.yml`.

## In a release workflow

Pinned to a major version; `v1` moves with fixes that change no input.

```yaml
# macOS
- id: sign
  uses: ashalkhakov/gnustep-release-actions/macos-sign@v1
  with:
    app: ${{ env.APP }}
    certificate: ${{ secrets.MACOS_CERTIFICATE }}
    certificate-password: ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
    identity: ${{ secrets.MACOS_SIGN_IDENTITY }}
- if: steps.sign.outputs.signed == 'true'
  uses: ashalkhakov/gnustep-release-actions/macos-notarize@v1
  with:
    app: ${{ env.APP }}
    apple-id: ${{ secrets.NOTARY_APPLE_ID }}
    team-id: ${{ secrets.NOTARY_TEAM_ID }}
    password: ${{ secrets.NOTARY_PASSWORD }}
- run: ditto -c -k --keepParent "$APP" "App-macOS-$APP_VERSION.zip"
- if: steps.sign.outputs.signed == 'true'
  uses: ashalkhakov/gnustep-release-actions/sparkle-appcast@v1
  with:
    archive: App-macOS-${{ env.APP_VERSION }}.zip
    tag: ${{ env.TAG }}
    private-key: ${{ secrets.SPARKLE_PRIVATE_KEY }}

# Linux
- uses: ashalkhakov/gnustep-release-actions/gnustep-stack@v1
  with:
    patches: ${{ github.workspace }}/gnustep-patches
    extra-packages: libsqlite3-dev
- uses: ashalkhakov/gnustep-release-actions/appimage-tools@v1
- uses: ashalkhakov/gnustep-release-actions/appimage-update-info@v1
  with:
    tag: ${{ env.TAG }}
    zsync: App-*x86_64.AppImage.zsync
- run: ./Scripts/package-appimage.sh   # linuxdeploy --output appimage, as each repository has it
```

The release then attaches the zip, `appcast.xml`, the AppImage and its
`.zsync`.

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
