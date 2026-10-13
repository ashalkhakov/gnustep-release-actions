#!/bin/bash
# The release workflows' first step: the repository's pins
# (source/.github/pins.env, if it has one) into the environment, and each
# dependency (DEPENDENCIES, space-separated ashalkhakov repositories)
# checked out beside source/ at its pin: ODataKit at ODATAKIT_REF,
# gnustep-patches at GNUSTEP_PATCHES_REF.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pins=$GITHUB_WORKSPACE/source/.github/pins.env
if [ -f "$pins" ]; then
  FILE=$pins "$here/pins.sh"
  set -a; . "$pins"; set +a
fi
for repo in ${DEPENDENCIES:-}; do
  var=$(printf '%s' "$repo" | tr 'a-z-' 'A-Z_')_REF
  ref=${!var:-}
  [ -n "$ref" ] || { echo "::error::$repo is a dependency, but .github/pins.env has no $var"; exit 1; }
  dest=$GITHUB_WORKSPACE/$repo
  git init -q "$dest"
  git -C "$dest" remote add origin "https://github.com/ashalkhakov/$repo.git"
  git -C "$dest" fetch -q --depth 1 origin "$ref"
  git -C "$dest" checkout -q FETCH_HEAD
  echo "$repo at $ref"
done
