#!/bin/bash
# The release workflows' version: APP_VERSION (the tag less its v, or
# 0.0.0-build<run> without one), BUILD_NUMBER, and RELEASE_DIR, where a
# build leaves what it built.
#
# BUILD_NUMBER is CFBundleVersion, what Sparkle compares to tell a newer
# release from an older one: 1000 and the number of commits up to the one
# built (git rev-list --count). The same commit has the same number whatever
# workflow or machine builds it, and it only goes up along the branch
# releases are made from. It was the workflow's run number, which starts
# again at 1 when a repository's workflow changes (SimpleNotes 0.4.5 was
# build 11 after 0.4.4's 36, and Sparkle offered it to nobody); the 1000 is
# above every run number a release was published with, and never changes.
# Run in the repository's checkout, with its whole history (fetch-depth: 0).
set -euo pipefail
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
  echo "::error::the checkout is shallow: the build number is the commit count, which needs the whole history (fetch-depth: 0)"
  exit 1
fi
build=$((1000 + $(git rev-list --count HEAD)))
if [ -n "${TAG:-}" ]; then
  version=${TAG#v}
else
  version=0.0.0-build$GITHUB_RUN_NUMBER
fi
{
  echo "APP_VERSION=$version"
  echo "BUILD_NUMBER=$build"
  echo "RELEASE_DIR=$RUNNER_TEMP/release-apps"
} >> "$GITHUB_ENV"
echo "version $version, build $build"
