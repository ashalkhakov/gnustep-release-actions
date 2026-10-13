#!/bin/bash
# The release workflows' version: APP_VERSION (the tag less its v, or
# 0.0.0-build<run> without one), BUILD_NUMBER (the run's, which only goes
# up: CFBundleVersion, what Sparkle compares), and RELEASE_DIR, where a
# build hook leaves what it built.
set -euo pipefail
if [ -n "${TAG:-}" ]; then
  version=${TAG#v}
else
  version=0.0.0-build$GITHUB_RUN_NUMBER
fi
{
  echo "APP_VERSION=$version"
  echo "BUILD_NUMBER=$GITHUB_RUN_NUMBER"
  echo "RELEASE_DIR=$RUNNER_TEMP/release-apps"
} >> "$GITHUB_ENV"
echo "version $version, build $GITHUB_RUN_NUMBER"
