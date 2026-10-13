# The sample's image, as a repository's Dockerfile takes what it builds on:
# the GNUstep stack's archive, by the version .github/pins.env names (passed
# as a build argument by gnustep-release-actions' docker.yml), unpacked at /.
# It builds the library and runs its test.
FROM ubuntu:22.04
ARG GNUSTEP_PATCHES_VERSION
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
 && arch=$(uname -m) \
 && curl -fsSL "https://github.com/ashalkhakov/gnustep-patches/releases/download/v$GNUSTEP_PATCHES_VERSION/gnustep-patches-$GNUSTEP_PATCHES_VERSION-ubuntu22.04-$arch.tar.xz" \
    | tar -C / -xJ \
 && grep -v '^#' /opt/gnustep/share/gnustep-patches/packages-ubuntu.txt | xargs apt-get install -y --no-install-recommends \
 && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 10 \
 && rm -rf /var/lib/apt/lists/*
ENV CC=clang CXX=clang++ LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0 LD_LIBRARY_PATH=/opt/gnustep/lib
COPY . /src
WORKDIR /src
RUN bash -c '. /opt/gnustep/System/Library/Makefiles/GNUstep.sh && make -C SampleKit && make -C Tests'
CMD ["bash", "-c", "LD_LIBRARY_PATH=/src/SampleKit/obj:/opt/gnustep/lib:/opt/gnustep/Local/Library/Libraries:/opt/gnustep/System/Library/Libraries /src/Tests/obj/samplekit-test"]
