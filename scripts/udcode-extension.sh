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
# And beside each package, the feed UDCode updates the extension from
# (UDCode's docs/extensions.md, Updates): <id>-<platform>.json, this
# release's version of it for that platform, its package's URL in this
# release (v<version>) and SHA-256. An extension names it in its
# package.json: "updates": "https://github.com/<owner>/<repo>/releases/latest/download/<id>-{platform}.json".
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

# A package's extension/package.json, on the standard output.
manifest_of() {
  if command -v unzip >/dev/null 2>&1; then unzip -p "$1" extension/package.json
  elif command -v bsdtar >/dev/null 2>&1; then bsdtar -xOf "$1" extension/package.json
  else "${SYSTEMROOT:-C:/Windows}/System32/tar.exe" -xOf "$(cygpath -w "$1" 2>/dev/null || echo "$1")" extension/package.json
  fi
}
# A string field's value in a manifest (a package.json udcx.sh wrote: one
# "key": "value" a line, or all on one).
field_of() {
  printf '%s' "$1" | tr -d '\r\n' | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

repository=${GITHUB_REPOSITORY:-}
for udcx in $made; do
  case " $(echo $before) " in *" $udcx "*) continue ;; esac
  file=$(basename "$udcx")
  # <name>-<version>-<platform>.udcx (universal: no platform)
  platform=${file%.udcx}
  platform=${platform#*-"$version"}
  platform=${platform#-}
  [ -n "$platform" ] || platform=universal
  json=$(manifest_of "$udcx") || { echo "::error::$file has no extension/package.json"; exit 1; }
  name=$(field_of "$json" name)
  publisher=$(field_of "$json" publisher)
  engine=$(printf '%s' "$json" | tr -d '\r\n' | sed -n 's/.*"engines"[[:space:]]*:[[:space:]]*{[^}]*"udcode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -n "$name" ] && [ -n "$publisher" ] && [ -n "$engine" ] \
    || { echo "::error::$file's package.json has no name, publisher or engines.udcode"; exit 1; }
  id=$(echo "$publisher.$name" | tr 'A-Z' 'a-z')
  if [ -z "$repository" ]; then
    echo "no GITHUB_REPOSITORY: no feed for $file"
    continue
  fi
  url="https://github.com/$repository/releases/download/v$version/$file"
  feed="$out/$id-$platform.json"
  printf '{\n  "name": "%s",\n  "versions": [\n    { "version": "%s", "engines": { "udcode": "%s" },\n      "packages": { "%s": { "url": "%s", "sha256": "%s" } } }\n  ]\n}\n' \
    "$id" "$version" "$engine" "$platform" "$url" "$(sha256_of "$udcx")" > "$feed"
  echo "$(basename "$feed"):"
  cat "$feed"
done

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
