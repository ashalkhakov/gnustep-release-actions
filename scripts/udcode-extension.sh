#!/bin/bash
# A repository's UDCode extensions, packaged (.udcx: UDCode's
# docs/extensions.md, laid out as VS Code's .vsix), when it has
# .github/release/udcode.conf:
#
#   PACKAGE=Scripts/udcx.sh     the repository's own packaging script, run as
#                               <script> <version> <out>, from its root, after
#                               make install; it writes this platform's .udcx
#                               files into <out>
#
#   udcode-extension.sh <version> <out>
#
# On Linux and Windows it runs with GNUstep's environment, as make does. On
# a Mac, $CODESIGN_IDENTITY is the identity the apps were signed with (the
# Sign step's, when a release is signed): UDCode loads only its own team's
# code. Each package is then notarized as the zip it is, when the NOTARY_*
# secrets are set: a downloaded package is quarantined, and so is what
# UDCode unpacks of it.
set -euo pipefail
version=${1:?version}
out=${2:?out}
conf=.github/release/udcode.conf
[ -f "$conf" ] || { echo "no $conf: no UDCode extension"; exit 0; }
package=$(. "$conf"; echo "${PACKAGE:-}")
[ -n "$package" ] || { echo "::error::$conf names no PACKAGE"; exit 1; }
mkdir -p "$out"
before=$(ls "$out"/*.udcx 2>/dev/null || true)

case "$(uname -s)" in
  Darwin)
    identity=${RUNNER_TEMP:-/tmp}/gnustep-release-actions.identity
    if [ -f "$identity" ]; then
      export CODESIGN_IDENTITY
      CODESIGN_IDENTITY=$(cat "$identity")
    fi
    "./$package" "$version" "$out"
    ;;
  *)
    set +u
    . "${PREFIX:-/opt/gnustep}/System/Library/Makefiles/GNUstep.sh"
    set -u
    case "$(uname -s)" in
      MINGW*|MSYS*) export PATH="${PREFIX}/bin:$PATH" ;;
    esac
    "./$package" "$version" "$out"
    ;;
esac

made=$(ls "$out"/*.udcx 2>/dev/null || true)
[ "$made" != "$before" ] || { echo "::error::$package wrote no .udcx into $out"; exit 1; }
ls -la "$out"/*.udcx

if [ "$(uname -s)" = Darwin ] && [ -n "${CODESIGN_IDENTITY:-}" ]; then
  if [ -z "${NOTARY_APPLE_ID:-}" ] || [ -z "${NOTARY_TEAM_ID:-}" ] || [ -z "${NOTARY_PASSWORD:-}" ]; then
    echo "::warning::NOTARY_* secrets not set; the extensions are signed but not notarized"
    exit 0
  fi
  for udcx in "$out"/*.udcx; do
    zip=${RUNNER_TEMP:-/tmp}/$(basename "$udcx" .udcx)-notarize.zip
    cp "$udcx" "$zip"
    result=$(xcrun notarytool submit "$zip" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_PASSWORD" --wait --output-format json || true)
    echo "$result"
    status=$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)
    [ "$status" = Accepted ] || { echo "::error::notarization of $(basename "$udcx") was not accepted (status: ${status:-none})"; exit 1; }
  done
fi
