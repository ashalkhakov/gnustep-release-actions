#!/bin/bash
# The sample's image runs its library's test (gnustep-release-actions'
# docker.yml: given the target and the image built and loaded).
set -euo pipefail
docker run --rm "$2" | tee /dev/stderr | grep -q "check: passed"
