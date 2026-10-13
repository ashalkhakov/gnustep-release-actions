#!/bin/bash
# The app signed for notarization (macos-sign/action.yml). From TopoText's
# release.yml, after ODataKit's and RDLKit's.
#
#   APP=...  CERTIFICATE=<base64 .p12>  CERTIFICATE_PASSWORD=...  [IDENTITY=...]
set -euo pipefail

if [ -z "${CERTIFICATE:-}" ]; then
  echo "::warning::no certificate (MACOS_CERTIFICATE); shipping $(basename "$APP") unsigned"
  echo "signed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# One keychain for the job: a second app (XFormsKit's viewer and designer)
# is signed by the identity chosen for the first.
keychain=$RUNNER_TEMP/gnustep-release-actions.keychain-db
chosen_file=$RUNNER_TEMP/gnustep-release-actions.identity
if [ ! -e "$keychain" ]; then
  password=$(uuidgen)
  security create-keychain -p "$password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  echo "$CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/cert.p12"
  security import "$RUNNER_TEMP/cert.p12" -k "$keychain" \
    -P "${CERTIFICATE_PASSWORD:-}" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$password" "$keychain" > /dev/null
  security list-keychain -d user -s "$keychain" login.keychain-db
  rm -f "$RUNNER_TEMP/cert.p12"
  # codesign takes only an identity it can chain to Apple's root, and a
  # runner need not have the Developer ID intermediate.
  curl -fsSL -o "$RUNNER_TEMP/DeveloperIDG2CA.cer" https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
  security import "$RUNNER_TEMP/DeveloperIDG2CA.cer" -k "$keychain" || true

  # The identity is read out of the keychain, not matched by name: only a
  # Developer ID Application certificate can be notarized; IDENTITY, if
  # set, chooses between several. Signed by hash, which is unambiguous.
  echo "identities in the signing keychain:"
  security find-identity -p codesigning "$keychain"
  valid=$(security find-identity -v -p codesigning "$keychain")
  candidates=$(printf '%s\n' "$valid" | awk -F'"' '/"Developer ID Application: /{print $2}' | sort -u)
  if [ -z "$candidates" ]; then
    echo "::error::the certificate holds no valid Developer ID Application identity (listed above); notarization accepts no other kind"
    exit 1
  fi
  chosen=$(printf '%s\n' "$candidates" | { [ -n "${IDENTITY:-}" ] && grep -Fx "$IDENTITY" || true; } | head -1)
  if [ -z "$chosen" ]; then
    [ -z "${IDENTITY:-}" ] || echo "::warning::MACOS_SIGN_IDENTITY names no Developer ID identity in the certificate; signing with the one it holds"
    chosen=$(printf '%s\n' "$candidates" | head -1)
  fi
  echo "signing as: $chosen"
  printf '%s\n' "$valid" | grep -F "\"$chosen\"" | head -1 | awk '{print $2}' > "$chosen_file"
fi
hash=$(cat "$chosen_file")

sign() {
  codesign --force --timestamp --options runtime --sign "$hash" "$@"
}

# --timestamp and --options runtime are what notarization requires. Signed
# inside out: Sparkle's helpers first, as its documentation has it for a
# Developer ID app (the downloader keeps its entitlements); then every
# framework embedded (what is there, not a list); then the app, whose
# signature seals theirs. Not --deep, which Apple deprecates and which signs
# the helpers without what they need.
sparkle="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ -d "$sparkle" ]; then
  sign "$sparkle/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
  sign "$sparkle/Autoupdate"
  sign "$sparkle/Updater.app"
fi
shopt -s nullglob
for fw in "$APP"/Contents/Frameworks/*.framework; do
  sign "$fw"
done
sign "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "signed=true" >> "$GITHUB_OUTPUT"
