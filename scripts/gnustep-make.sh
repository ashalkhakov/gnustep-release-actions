#!/bin/bash
# make, with GNUstep's environment (the stack in $PREFIX, /opt/gnustep): what
# the Linux workflow runs for each phase, `gnustep-make.sh check`, the same as
# a developer types after sourcing GNUstep.sh.
set -eo pipefail
# GNUstep.sh reads variables it has not set, so set -u comes after it.
. "${PREFIX:-/opt/gnustep}/System/Library/Makefiles/GNUstep.sh"
set -u
# On Windows, libobjc's and libdispatch's DLLs are in the prefix's bin, and
# Windows finds DLLs on PATH.
case "$(uname -s)" in
  MINGW*|MSYS*) export PATH="${PREFIX}/bin:$PATH" ;;
esac
exec make -j"$(nproc)" "$@"
