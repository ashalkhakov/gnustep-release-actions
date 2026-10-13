#!/bin/bash
# A GNUstep app's AppImage, the same for every app: its apps and tools, as
# installed into the GNUstep prefix, the GNUstep runtime they run on, the
# Eau theme, fonts, the opener and the launcher (AppRun), traced for
# libraries by linuxdeploy and made into one file. Ported from TopoText's
# Scripts/prepare-appdir.sh and package-appimage.sh (after ODataKit's,
# XFormsKit's, RDLKit's and UDQuakeTools').
#
#   appimage.sh .github/release/appimage.conf
#
# Run from the repository's root, after its build has installed its apps and
# tools into the prefix (GNUSTEP_INSTALLATION_DOMAIN=SYSTEM). The environment:
#   PREFIX             the GNUstep prefix (gnustep-stack sets it)
#   APP_VERSION        in the image's name (default: dev)
#   LINUXDEPLOY, LDAI_RUNTIME_FILE      as appimage-tools sets them
#   LDAI_UPDATE_INFORMATION             for a release (appimage-update-info):
#                                       embedded, and a .zsync written beside
#
# The configuration, a shell file, is the app's whole say in it:
#   IMAGE              the image's name: IMAGE-<version>-<arch>.AppImage
#   NAME               the app's name, for its caches and temporary files
#   APPS               the .app wrappers it carries (each is checked, traced
#                      and given the defaults AppRun sets)
#   TOOLS              the command-line tools it carries
#   DEFAULT            what runs when the image is opened
#   ROUTES             "keyword,keyword=Target ...": what a first argument or
#                      a symlink's name starts (see AppRun)
#   WITH_ARGUMENTS     what arguments go to when no keyword starts anything
#   WITH_FILE          what a path goes to (default: WITH_ARGUMENTS)
#   FIXED_PITCH_FONT   NSUserFixedPitchFont (default: LiberationMono)
#   ENTRIES            "file.desktop=icon.png ...": the first is the image's
#                      own; each icon is installed under its entry's Icon=
#   METAINFO           the AppStream file software centres show
#   LOADED             globs of what is loaded at run time rather than linked
#                      (plug-ins, stores): their libraries are bundled too
#   REQUIRE            paths that must be in the image, as the end of a path
#                      under it (SimpleNotes.app/Resources/MainMenu.xib)
set -euo pipefail

conf=${1:?usage: appimage.sh <appimage.conf>}
here=$(cd "$(dirname "$0")" && pwd)
IMAGE="" NAME="" APPS="" TOOLS="" DEFAULT="" ROUTES="" WITH_ARGUMENTS="" WITH_FILE=""
FIXED_PITCH_FONT="" ENTRIES="" METAINFO="" LOADED="" REQUIRE=""
. "$conf"
: "${IMAGE:?$conf names no IMAGE}" "${NAME:?$conf names no NAME}" "${DEFAULT:?$conf names no DEFAULT}"
[ -n "$ENTRIES" ] || { echo "$conf names no ENTRIES" >&2; exit 1; }

PREFIX=${PREFIX:-${GNUSTEP_PREFIX:?PREFIX, the GNUstep prefix, is not set}}
LINUXDEPLOY=${LINUXDEPLOY:-${RUNNER_TEMP:-/tmp}/linuxdeploy/AppRun}
arch=$(uname -m)
root=$(pwd)

rm -rf AppDir
mkdir -p AppDir/usr/bin AppDir/usr/lib AppDir/usr/share/gnustep-appimage

# The prefix's GNUstep hierarchies: the apps, the libraries, the backend
# bundle, the theme, the tools GNUstep starts (gdnc, gpbs, make_services).
for domain in System Local; do
  if [ -d "$PREFIX/$domain" ]; then
    mkdir -p "AppDir/usr/$domain"
    cp -Rp "$PREFIX/$domain/"* "AppDir/usr/$domain/"
  fi
done
# What a GNUstep image does not need at run time.
rm -rf AppDir/usr/System/Library/Headers AppDir/usr/Local/Library/Headers \
       AppDir/usr/System/Library/Makefiles AppDir/usr/System/Library/Documentation

# libobjc2 and libdispatch live in the prefix's plain lib/, outside the
# GNUstep layout.
for lib in "$PREFIX"/lib/libobjc.so.*.*; do
  [ -f "$lib" ] || continue
  soname=$(basename "$lib")
  cp -p "$lib" AppDir/usr/lib/
  ln -sf "$soname" "AppDir/usr/lib/${soname%.*}"
  ln -sf "$soname" AppDir/usr/lib/libobjc.so
done
for dir in lib lib64; do
  if ls "$PREFIX/$dir"/libdispatch.so* > /dev/null 2>&1; then
    cp -p "$PREFIX/$dir"/libdispatch.so* AppDir/usr/lib/
    cp -p "$PREFIX/$dir"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
    break
  fi
done

# The backend bundle under the names gnustep-gui looks for.
backend=$(find AppDir/usr -name "libgnustep-back-*.bundle" 2>/dev/null | head -n 1 || true)
[ -n "$backend" ] || { echo "MISSING: gnustep-back's bundle (is libs-back in the stack?)" >&2; exit 1; }
ln -sfn "$(basename "$backend")" "$(dirname "$backend")/libgnustep-back.bundle"
ln -sfn "$(basename "$backend")" "$(dirname "$backend")/back.bundle"

# The opener, under both names GNUstep asks for: "open" is what the
# GSUnknownFileTool default (AppRun) names, "xdg-open" is NSWorkspace's
# built-in fallback. In the bundle's GNUstep Tools, which
# [NSTask launchPathForTool:] searches before $PATH, and in usr/bin.
mkdir -p AppDir/usr/System/Tools
for name in open xdg-open; do
  install -m 0755 "$here/open" "AppDir/usr/System/Tools/$name"
  install -m 0755 "$here/open" "AppDir/usr/bin/$name"
done

# Fonts, so the window lays out the same on a machine that has none (AppRun
# writes the fontconfig that finds them, and selects Liberation).
for dir in /usr/share/fonts/truetype/dejavu /usr/share/fonts/truetype/liberation \
           /usr/share/fonts/truetype/msttcorefonts; do
  if [ -d "$dir" ]; then
    mkdir -p "AppDir/usr/share/fonts/truetype/$(basename "$dir")"
    cp -Rp "$dir"/* "AppDir/usr/share/fonts/truetype/$(basename "$dir")/"
  fi
done
ls AppDir/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf > /dev/null 2>&1 \
  || { echo "MISSING: the Liberation fonts AppRun selects (fonts-liberation on the build machine)" >&2; exit 1; }

# The theme AppRun selects: without it GNUstep falls back to its own look.
theme=$(find AppDir/usr -maxdepth 5 -name "Eau.theme" -type d | head -n 1)
[ -n "$theme" ] || { echo "MISSING: Eau.theme (is eau in the GNUstep stack's components?)" >&2; exit 1; }

# The apps and tools, each where AppRun looks; the defaults domains AppRun
# writes are each app's name and its bundle identifier.
EXEC_ARGS=()
DOMAINS=""
for app in $APPS; do
  bin=""
  for domain in System Local; do
    [ -x "AppDir/usr/$domain/Applications/$app.app/$app" ] && bin="AppDir/usr/$domain/Applications/$app.app/$app" && break
  done
  [ -n "$bin" ] || { echo "MISSING: $app.app (installed into the prefix, GNUSTEP_INSTALLATION_DOMAIN=SYSTEM?)" >&2; exit 1; }
  EXEC_ARGS+=(--executable "$bin")
  DOMAINS="$DOMAINS $app"
  id=$(sed -n 's/^[[:space:]]*CFBundleIdentifier[[:space:]]*=[[:space:]]*"\{0,1\}\([^";]*\)"\{0,1\};.*/\1/p' \
         "$(dirname "$bin")/Resources/Info-gnustep.plist" 2>/dev/null | head -n 1)
  [ -z "$id" ] || DOMAINS="$DOMAINS $id"
done
for tool in $TOOLS; do
  bin=$(find AppDir/usr/System/Tools AppDir/usr/Local/Tools -type f -name "$tool" -perm -111 2>/dev/null | head -n 1)
  [ -n "$bin" ] || { echo "MISSING: the $tool tool" >&2; exit 1; }
  EXEC_ARGS+=(--executable "$bin")
done
for path in $REQUIRE; do
  found=$(find AppDir/usr -path "*/$path" 2>/dev/null | head -n 1)
  [ -n "$found" ] || { echo "MISSING: $path" >&2; exit 1; }
done

# The launcher and its configuration: the repository's, and what was found.
install -m 0755 "$here/AppRun" AppDir/AppRun
{
  cat "$conf"
  echo
  echo "# Found when the image was made."
  echo "DOMAINS=\"${DOMAINS# }\""
} > AppDir/usr/share/gnustep-appimage/appimage.conf

# What linuxdeploy insists on: one desktop entry at the top, and its icon;
# every entry in usr/share/applications, each icon under its entry's name.
mkdir -p AppDir/usr/share/applications AppDir/usr/share/icons/hicolor/256x256/apps
top=1
for entry in $ENTRIES; do
  desktop=${entry%%=*}
  icon=${entry#*=}
  [ "$icon" != "$entry" ] || { echo "ENTRIES: $entry has no =icon.png" >&2; exit 1; }
  iconname=$(sed -n 's/^Icon=//p' "$desktop" | head -n 1)
  [ -n "$iconname" ] || { echo "$desktop has no Icon=" >&2; exit 1; }
  install -m 0644 "$desktop" "AppDir/usr/share/applications/$(basename "$desktop")"
  install -m 0644 "$icon" "AppDir/usr/share/icons/hicolor/256x256/apps/$iconname.png"
  if [ $top = 1 ]; then
    install -m 0644 "$desktop" "AppDir/$(basename "$desktop")"
    install -m 0644 "$icon" "AppDir/$iconname.png"
    top=0
  fi
done
# What software centres and the AppImage catalog show of it.
if [ -n "$METAINFO" ]; then
  mkdir -p AppDir/usr/share/metainfo
  install -m 0644 "$METAINFO" AppDir/usr/share/metainfo/
fi

du -sh AppDir

# What is loaded at run time rather than linked -- gnustep-gui's backend and
# sound bundles, the app's own LOADED -- and the tools GNUstep starts (gpbs,
# gdnc): their libraries too, not the files themselves, which are in place.
DEPS_ARGS=()
while IFS= read -r elf; do
  DEPS_ARGS+=(--deploy-deps-only "$elf")
done < <( {
    find AppDir/usr/System/Library/Bundles AppDir/usr/Local/Library/Bundles \
         AppDir/usr/System/Tools AppDir/usr/Local/Tools -type f -perm -111 2>/dev/null
    for glob in $LOADED; do find AppDir/usr -name "$glob" -type f 2>/dev/null; done
  } | sort -u | xargs -r file | awk -F: '/ELF/{print $1}')

export OUTPUT="$IMAGE-${APP_VERSION:-dev}-$arch.AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_VALIDATE=1
# Keep the symbol tables: Objective-C methods are named only in .symtab, which
# linuxdeploy's strip would remove, and a backtrace from a user's crash is
# worth far more with them.
export NO_STRIP="${NO_STRIP:-1}"
export LDAI_RUNTIME_FILE="${LDAI_RUNTIME_FILE:-${RUNNER_TEMP:-/tmp}/appimage-runtime/runtime-$arch}"

# Local before System, as GNUstep.sh orders them: a library installed in
# both (one updated) is the Local one.
LD_LIBRARY_PATH="$PREFIX/Local/Library/Libraries:$PREFIX/System/Library/Libraries:$PREFIX/lib:$root/AppDir/usr/lib:${LD_LIBRARY_PATH:-}" \
  "$LINUXDEPLOY" --appdir AppDir "${EXEC_ARGS[@]}" "${DEPS_ARGS[@]}" --output appimage

echo "built $OUTPUT"
