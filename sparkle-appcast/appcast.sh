#!/bin/bash
# A release's appcast (sparkle-appcast/action.yml). From TopoText's
# release.yml.
#
#   ARCHIVE=<zip> TAG=v1.2.3 SPARKLE_PRIVATE_KEY=... [OUTPUT=appcast.xml]
#   [SPARKLE_VERSION=2.10.0] [DOWNLOAD_URL_PREFIX=...]
set -euo pipefail

if [ -z "${TAG:-}" ] || [[ "$TAG" == *-* ]]; then
  echo "not a release (tag '${TAG:-}'): no appcast; a pre-release is offered to no one"
  exit 0
fi
if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "::warning::SPARKLE_PRIVATE_KEY not set; no appcast, so the Mac app will not be offered this release"
  exit 0
fi
output=${OUTPUT:-appcast.xml}
prefix=${DOWNLOAD_URL_PREFIX:-https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/}

work=$RUNNER_TEMP/sparkle-appcast-$(basename "$output" .xml)
mkdir -p "$work/sparkle" "$work/updates"
curl -fsSL -o "$work/sparkle.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
tar -xf "$work/sparkle.tar.xz" -C "$work/sparkle"
cp "$ARCHIVE" "$work/updates/"
# The key goes in on stdin, never to a file.
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$work/sparkle/bin/generate_appcast" --ed-key-file - \
  --download-url-prefix "$prefix" -o "$output" "$work/updates"
cat "$output"
# A key that does not match the app's SUPublicEDKey leaves the update
# unsigned, which every installed copy would refuse.
grep -q 'sparkle:edSignature' "$output" || { echo "::error::the update in $output is not signed (does SPARKLE_PRIVATE_KEY match the app's SUPublicEDKey?)"; exit 1; }
echo "appcast=$output" >> "$GITHUB_OUTPUT"
