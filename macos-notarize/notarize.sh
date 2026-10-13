#!/bin/bash
# The signed app notarized and its ticket stapled (macos-notarize/action.yml).
# From TopoText's release.yml.
#
#   APP=...  NOTARY_APPLE_ID=...  NOTARY_TEAM_ID=...  NOTARY_PASSWORD=...
set -euo pipefail

name=$(basename "$APP" .app)
if [ -z "${NOTARY_APPLE_ID:-}" ] || [ -z "${NOTARY_TEAM_ID:-}" ] || [ -z "${NOTARY_PASSWORD:-}" ]; then
  echo "::warning::NOTARY_* secrets not set; $name is signed but not notarized"
  echo "notarized=false" >> "$GITHUB_OUTPUT"
  echo "stapled=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/$name-notarize.zip"
# A submission Apple finds invalid still ends the wait: the status says
# whether it was accepted, and the log says why not.
xcrun notarytool submit "$RUNNER_TEMP/$name-notarize.zip" \
  --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
  --password "$NOTARY_PASSWORD" --wait --output-format json > "$RUNNER_TEMP/$name-notary.json" || true
cat "$RUNNER_TEMP/$name-notary.json"
id=$(plutil -extract id raw -o - "$RUNNER_TEMP/$name-notary.json" 2>/dev/null || true)
status=$(plutil -extract status raw -o - "$RUNNER_TEMP/$name-notary.json" 2>/dev/null || true)
if [ "$status" != "Accepted" ]; then
  [ -n "$id" ] && xcrun notarytool log "$id" \
    --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" || true
  echo "::error::notarization of $name was not accepted (status: ${status:-none})"
  exit 1
fi
echo "notarized=true" >> "$GITHUB_OUTPUT"

# Stapling fetches the ticket from Apple's CloudKit service, whose
# connection the runner has lost mid-release, again and again ("The network
# connection was lost", error 68). Tried three times; then the app ships
# notarized but unstapled, which Gatekeeper accepts by fetching the ticket
# itself when the app is first opened.
stapled=false
for attempt in 1 2 3; do
  if xcrun stapler staple "$APP" && xcrun stapler validate "$APP"; then
    stapled=true
    break
  fi
  [ "$attempt" = 3 ] || { echo "::warning::stapling $name failed (attempt $attempt of 3); trying again in 60 s"; sleep 60; }
done
echo "stapled=$stapled" >> "$GITHUB_OUTPUT"
if [ "$stapled" = true ]; then
  # What a downloaded copy meets: Gatekeeper's own assessment.
  spctl --assess --type execute --verbose=2 "$APP"
else
  echo "::warning::the ticket could not be stapled to $name; shipping it notarized but unstapled (Gatekeeper fetches the ticket online)"
fi
