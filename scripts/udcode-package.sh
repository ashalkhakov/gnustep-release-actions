#!/bin/bash
# UDCode with a repository's extensions in it, for those who want the tools
# and not an editor to install them into: UDCode's own release package for
# this platform, the .udcx files udcode-extension.sh wrote put in its
# Resources/Extensions, which UDCode installs the first time it starts
# (UDCode's docs/extensions.md, Shipped with UDCode). From then on the
# extensions update from their own feeds and UDCode from its own. Made when
# .github/release/udcode.conf names one:
#
#   UDCODE_PACKAGE=UDCode-UDQuakeTools    the packages' name; the app in them
#                                         is UDCode still
#
# UDCode's release is the one .github/pins.env's UDCODEKIT_VERSION names
# (ashalkhakov/UDCodeKit, or $UDCODE_REPOSITORY):
#
#   udcode-package.sh <version> <out>
#
#   macOS    UDCode-macOS-<v>.zip       -> <name>-macOS-<version>.zip, the app
#            signed again as udcode-extension.sh signed the packages (adding
#            to an app breaks its seal) and notarized, when a release is; its
#            one package universal (the bundle is), so either Mac loads it
#   Linux    UDCode-<v>-x86_64.AppImage -> <name>-<version>-x86_64.AppImage,
#            repacked by linuxdeploy (appimage-tools), with this
#            repository's update information on a release
#   Windows  UDCode-<v>-win64-portable.zip -> <name>-<version>-win64-portable.zip
#
# The packages it adds are this run's, in <out>, for this platform.
set -euo pipefail
version=${1:?version}
out=${2:?out}
conf=.github/release/udcode.conf
[ -f "$conf" ] || { echo "no $conf: no UDCode package"; exit 0; }
name=$(. "$conf"; echo "${UDCODE_PACKAGE:-}")
[ -n "$name" ] || { echo "$conf names no UDCODE_PACKAGE: no UDCode package"; exit 0; }
udcode=$(. .github/pins.env 2>/dev/null; echo "${UDCODEKIT_VERSION:-}")
[ -n "$udcode" ] || { echo "::error::.github/pins.env names no UDCODEKIT_VERSION: no UDCode to put the extensions in"; exit 1; }
repository=${UDCODE_REPOSITORY:-ashalkhakov/UDCodeKit}
release=https://github.com/$repository/releases/download/v$udcode

work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/udcode-package.XXXXXX")
trap 'rm -rf "$work"' EXIT
fetch() { curl -fsSL --retry 3 -o "$work/$1" "$release/$1"; echo "UDCode $udcode: $1"; }

case "$(uname -s)" in
  Darwin)
    packages=$(ls "$out"/*-darwin-arm64.udcx 2>/dev/null || true)
    [ -n "$packages" ] || { echo "::error::no darwin .udcx in $out"; exit 1; }
    fetch "UDCode-macOS-$udcode.zip"
    ditto -x -k "$work/UDCode-macOS-$udcode.zip" "$work/app"
    app=$work/app/UDCode.app
    [ -d "$app" ] || { echo "::error::UDCode-macOS-$udcode.zip holds no UDCode.app"; exit 1; }
    mkdir -p "$app/Contents/Resources/Extensions"
    for udcx in $packages; do
      # universal: TargetPlatform taken out of its manifest
      shipped=$app/Contents/Resources/Extensions/$(basename "$udcx" -darwin-arm64.udcx).udcx
      mkdir "$work/udcx"
      (cd "$work/udcx" && unzip -q "$udcx" && sed -i '' 's/ TargetPlatform="[^"]*"//' extension.vsixmanifest \
        && zip -qry "$shipped" extension extension.vsixmanifest)
      rm -rf "$work/udcx"
    done
    identity=${RUNNER_TEMP:-/tmp}/gnustep-release-actions.identity
    suffix=""
    if [ -f "$identity" ]; then
      # the app alone: what it embeds keeps the signatures it came with
      codesign --force --timestamp --options runtime --preserve-metadata=entitlements,requirements,flags \
        --sign "$(cat "$identity")" "$app"
      codesign --verify --deep --strict "$app"
      APP=$app GITHUB_OUTPUT=/dev/null "$(dirname "$0")/../macos-notarize/notarize.sh"
    else
      echo "::warning::no signing identity: $name is UDCode's app with its seal broken; shipped -unsigned"
      suffix=-unsigned
    fi
    ditto -c -k --keepParent "$app" "$out/$name-macOS-$version$suffix.zip"
    ls -la "$out/$name-macOS-$version$suffix.zip"
    ;;

  Linux)
    [ "$(uname -m)" = x86_64 ] || { echo "UDCode has no AppImage for $(uname -m)"; exit 0; }
    packages=$(ls "$out"/*-linux-x64.udcx 2>/dev/null || true)
    [ -n "$packages" ] || { echo "::error::no linux-x64 .udcx in $out"; exit 1; }
    fetch "UDCode-$udcode-x86_64.AppImage"
    chmod +x "$work/UDCode-$udcode-x86_64.AppImage"
    (cd "$work" && "./UDCode-$udcode-x86_64.AppImage" --appimage-extract > /dev/null)
    resources=$(find "$work/squashfs-root" -type d -path '*/UDCode.app/Resources' | head -n 1)
    [ -n "$resources" ] || { echo "::error::UDCode's AppImage holds no UDCode.app/Resources"; exit 1; }
    mkdir -p "$resources/Extensions"
    cp $packages "$resources/Extensions/"
    LINUXDEPLOY=${LINUXDEPLOY:-${RUNNER_TEMP:-/tmp}/linuxdeploy/AppRun}
    [ -x "$LINUXDEPLOY" ] || { echo "::error::no linuxdeploy at $LINUXDEPLOY (appimage-tools)"; exit 1; }
    # what it holds is deployed already: repacked as it is, symbols kept
    (cd "$work" && OUTPUT="$name-$version-x86_64.AppImage" APPIMAGE_EXTRACT_AND_RUN=1 NO_VALIDATE=1 NO_STRIP=1 \
      LDAI_RUNTIME_FILE="${LDAI_RUNTIME_FILE:-${RUNNER_TEMP:-/tmp}/appimage-runtime/runtime-x86_64}" \
      "$LINUXDEPLOY" --appdir squashfs-root --output appimage)
    mv "$work/$name-$version-x86_64.AppImage" "$out/"
    if [ -f "$work/$name-$version-x86_64.AppImage.zsync" ]; then mv "$work/$name-$version-x86_64.AppImage.zsync" "$out/"; fi
    if [ -n "${LDAI_UPDATE_INFORMATION:-}" ] && [ ! -f "$out/$name-$version-x86_64.AppImage.zsync" ]; then
      echo "::error::a release's AppImage has no .zsync beside it"; exit 1
    fi
    # what was put in is in what came out
    (cd "$work" && rm -rf squashfs-root && "$out/$name-$version-x86_64.AppImage" --appimage-extract > /dev/null)
    for udcx in $packages; do
      find "$work/squashfs-root" -path "*/UDCode.app/Resources/Extensions/$(basename "$udcx")" | grep -q . \
        || { echo "::error::$name's AppImage does not carry $(basename "$udcx")"; exit 1; }
    done
    ls -la "$out/$name-$version-x86_64.AppImage"
    ;;

  MINGW*|MSYS*)
    packages=$(ls "$out"/*-win32-x64.udcx 2>/dev/null || true)
    [ -n "$packages" ] || { echo "::error::no win32-x64 .udcx in $out"; exit 1; }
    fetch "UDCode-$udcode-win64-portable.zip"
    mkdir "$work/portable"
    (cd "$work/portable" && unzip -q "../UDCode-$udcode-win64-portable.zip")
    resources=$(find "$work/portable" -type d -path '*/UDCode.app/Resources' | head -n 1)
    [ -n "$resources" ] || { echo "::error::UDCode's portable zip holds no UDCode.app/Resources"; exit 1; }
    mkdir -p "$resources/Extensions"
    cp $packages "$resources/Extensions/"
    rm -f "$out/$name-$version-win64-portable.zip"
    (cd "$work/portable" && zip -qr "$out/$name-$version-win64-portable.zip" .)
    ls -la "$out/$name-$version-win64-portable.zip"
    ;;

  *) echo "no UDCode package for $(uname -s)"; exit 0 ;;
esac
