#!/bin/bash
# What a repository builds on, fetched by the exact versions its
# .github/pins.env names, from those releases:
#
#   GNUSTEP_PATCHES_VERSION=2026.10.13   ashalkhakov/gnustep-patches, tag v2026.10.13
#   FREECOREDATA_VERSION=0.5.0           ashalkhakov/freecoredata, tag v0.5.0
#   SPARKLE_VERSION=2.10.0               sparkle-project/Sparkle, tag 2.10.0 (Apple)
#
#   deps.sh linux   each one's <name>-<version>-ubuntu22.04-<arch>.tar.xz, unpacked
#                   at / (they hold opt/gnustep), the stack first
#   deps.sh windows each one's <name>-<version>-windows-clang64-x86_64.tar.xz,
#                   unpacked at C:\ (they hold GNUstep), the stack first; in
#                   an MSYS2 shell
#   deps.sh apple   each one's <name>-<version>-apple.zip (its XCFrameworks), and
#                   Sparkle's, unpacked into .deps/ in the repository's root; a
#                   release with no such zip has nothing for Apple (FreeCoreData:
#                   Apple's Core Data is the system's) and is passed over
#
# <NAME> is the repository's name in capitals, '-' as '_'. Run from the
# repository's root; a repository with no pins.env builds on nothing of ours.
set -euo pipefail
platform=${1:?usage: deps.sh linux|windows|apple}
pins=.github/pins.env
[ -f "$pins" ] || { echo "no $pins: nothing to fetch"; exit 0; }

# NAME=version, the stack's first, in the order the file gives the rest.
entries=$(sed -n 's/^\([A-Z0-9_]*\)_VERSION=\(.*\)$/\1 \2/p' "$pins" \
          | awk '$1 == "GNUSTEP_PATCHES" { print; next } { rest = rest $0 "\n" } END { printf "%s", rest }')
[ -n "$entries" ] || { echo "$pins names no *_VERSION: nothing to fetch"; exit 0; }

fetch() {  # fetch <url> <file>; 2 when the release has no such file
  local status
  for i in 1 2 3; do
    status=$(curl -sSL -o "$2" -w '%{http_code}' "$1") || status=000
    [ "$status" = 200 ] && return 0
    [ "$status" = 404 ] && return 2
    sleep 5
  done
  echo "::error::could not fetch $1 (HTTP $status)"; return 1
}

work=$(mktemp -d)
arch=$(uname -m)
while read -r name version; do
  [ -n "$name" ] || continue
  repo=$(echo "$name" | tr 'A-Z_' 'a-z-')
  case "$platform:$name" in
    linux:SPARKLE|windows:SPARKLE) continue ;;
    apple:GNUSTEP_PATCHES) continue ;;
    apple:SPARKLE)
      # The XCFramework is in the zip Sparkle publishes for SwiftPM; it is
      # unpacked here like any other, no SwiftPM involved.
      fetch "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-for-Swift-Package-Manager.zip" "$work/sparkle.zip" \
        || { echo "::error::no Sparkle $version"; exit 1; }
      mkdir -p .deps "$work/sparkle"
      ditto -x -k "$work/sparkle.zip" "$work/sparkle"
      rm -rf .deps/Sparkle.xcframework
      cp -R "$work/sparkle/Sparkle.xcframework" .deps/
      echo "Sparkle $version: .deps/Sparkle.xcframework"
      ;;
    linux:*)
      file=$repo-$version-ubuntu22.04-$arch.tar.xz
      fetch "https://github.com/ashalkhakov/$repo/releases/download/v$version/$file" "$work/$file" \
        || { echo "::error::no $file in $repo's v$version release"; exit 1; }
      sudo mkdir -p /opt/gnustep && sudo chown "$(id -u):$(id -g)" /opt/gnustep
      # Into directories already there (/opt is root's) without setting
      # their times and modes, which only their owner may.
      tar -C / --no-overwrite-dir -xJf "$work/$file"
      echo "$repo $version: $(tar -tJf "$work/$file" | wc -l) files into /opt/gnustep"
      ;;
    windows:*)
      file=$repo-$version-windows-clang64-x86_64.tar.xz
      fetch "https://github.com/ashalkhakov/$repo/releases/download/v$version/$file" "$work/$file" \
        || { echo "::error::no $file in $repo's v$version release"; exit 1; }
      tar -C /c -xJf "$work/$file"
      echo "$repo $version: $(tar -tJf "$work/$file" | wc -l) files into C:\\GNUstep"
      ;;
    apple:*)
      file=$repo-$version-apple.zip
      status=0; fetch "https://github.com/ashalkhakov/$repo/releases/download/v$version/$file" "$work/$file" || status=$?
      if [ "$status" = 2 ]; then echo "$repo $version: nothing for Apple"; continue; fi
      [ "$status" = 0 ] || exit 1
      mkdir -p .deps
      ditto -x -k "$work/$file" .deps/
      echo "$repo $version: $(cd .deps && ls -d *.xcframework | tr '\n' ' ')"
      ;;
  esac
done <<< "$entries"
rm -rf "$work"
