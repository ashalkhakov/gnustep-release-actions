#!/bin/bash
# A GNUstep app's Windows installer, staged the same for every app: its apps
# as make install put them, the GNUstep prefix they run on (the stack, the
# libraries pins.env names, the repository's own), and the manifest
# gnustep-packager's MSI backend makes the installer from (package.json).
#
#   msi.sh .github/release/windows.conf <out-dir>
#
# Run from the repository's root in an MSYS2 shell, after `make install` has
# installed into a staging directory. The environment:
#   PREFIX        the GNUstep prefix, /c/GNUstep (the stack and pins.env's)
#   STAGE         make install's staging directory (it holds c/GNUstep)
#   APP_VERSION   the version (version.sh's)
#
# The prefix is staged as the installed app's runtime with its layout kept:
# gnustep-base reads its GNUstep.conf from beside its DLL, every path in it
# relative, so the runtime works wherever the installer puts it.
#
# The configuration, a shell file, is the app's whole say in it:
#   NAME          the installer's name: NAME-<version>-win64.msi, and the
#                 product's, its Start menu shortcut's and its directory's
#   APPS          the .app wrappers it carries
#   DEFAULT       what the shortcut starts
#   ICON          the shortcut's and installer's icon, an .ico
#   MANUFACTURER  who makes it (default: the repository's owner)
#   SUMMARY       one line on what it is
#   SMOKE         the installed app's smoke test: the arguments to start it
#                 with (--self-test); it must exit 0
#   THEME         its look (default: WinUXTheme, the native one)
set -euo pipefail

conf=${1:?usage: msi.sh <windows.conf> <out-dir>}
out=${2:?usage: msi.sh <windows.conf> <out-dir>}
NAME="" APPS="" DEFAULT="" ICON="" MANUFACTURER="" SUMMARY="" SMOKE="" THEME=""
. "$conf"
: "${NAME:?$conf names no NAME}" "${APPS:?$conf names no APPS}" "${DEFAULT:?$conf names no DEFAULT}"
PREFIX=${PREFIX:?PREFIX, the GNUstep prefix, is not set}
STAGE=${STAGE:?STAGE, the staging directory make install filled, is not set}
THEME=${THEME:-WinUXTheme}
repository=${GITHUB_REPOSITORY:-local/$NAME}
MANUFACTURER=${MANUFACTURER:-${repository%%/*}}

stage=$out/stage
rm -rf "$out"
mkdir -p "$stage/app" "$stage/runtime" "$stage/metadata/icons" "$stage/metadata/licenses"

# The runtime: the prefix and what make install added to it, less what only
# building on it needs.
cp -a "$PREFIX/." "$stage/runtime/"
[ -d "$STAGE/c/GNUstep" ] && cp -a "$STAGE/c/GNUstep/." "$stage/runtime/"
rm -rf "$stage/runtime/include" "$stage/runtime/share/man" "$stage/runtime/share/gnustep-patches" \
       "$stage/runtime/lib/cmake" "$stage/runtime/lib/pkgconfig" "$stage/runtime/System/Library/Makefiles"
find "$stage/runtime" -depth -type d \( -name Headers -o -name Documentation \) -path '*/Library/*' -exec rm -rf {} +
find "$stage/runtime" -type f \( -name '*.dll.a' -o -name '*.a' -o -name '*.exe.a' \) -delete

# The apps, out of the runtime's Applications.
for app in $APPS; do
  found=$(find "$stage/runtime" -maxdepth 3 -type d -name "$app.app" | head -n 1)
  [ -n "$found" ] || { echo "::error::$conf names $app, which make install did not install" >&2; exit 1; }
  mv "$found" "$stage/app/"
done
[ -f "$stage/app/$DEFAULT.app/$DEFAULT.exe" ] || { echo "::error::no $DEFAULT.app/$DEFAULT.exe" >&2; exit 1; }

# The defaults tool, where the launcher seeds the app's first-run defaults
# (the theme) with it.
base_dll=$(find "$stage/runtime" -iname 'gnustep-base*.dll' | head -n 1)
[ -n "$base_dll" ] || { echo "::error::no gnustep-base DLL in the runtime" >&2; exit 1; }
[ -f "$(dirname "$base_dll")/GNUstep.conf" ] || { echo "::error::no GNUstep.conf beside $base_dll: the stack is older than gnustep-patches' relocatable one" >&2; exit 1; }
tools=$(dirname "$(find "$stage/runtime" -name defaults.exe | head -n 1)")
mkdir -p "$stage/runtime/bin"
cp "$tools/defaults.exe" "$stage/runtime/bin/"

# WinSparkle, for an app that updates itself (deps.sh put it in .deps when
# pins.env names WINSPARKLE_VERSION), and its licence.
if [ -f .deps/WinSparkle/WinSparkle.dll ]; then
  cp .deps/WinSparkle/WinSparkle.dll "$stage/runtime/bin/"
  cp .deps/WinSparkle/COPYING "$stage/metadata/licenses/WinSparkle.txt"
fi

if [ -n "$ICON" ]; then
  [ -f "$ICON" ] || { echo "::error::$conf names ICON $ICON, which is not there" >&2; exit 1; }
  cp "$ICON" "$stage/metadata/icons/app.ico"
fi

# What it carries, under which licences.
cat > "$stage/metadata/licenses/GNUstep.txt" <<EOF
$NAME runs on GNUstep, built from source with gnustep-patches
(https://github.com/ashalkhakov/gnustep-patches): gnustep-base, -gui and
-back (LGPL-2.1-or-later), libs-corebase and libs-opal (LGPL-2.1-or-later),
libobjc2 (MIT), libdispatch (Apache-2.0 with the Runtime Library Exception),
and MSYS2's CLANG64 libraries they link (https://packages.msys2.org).
$(cat "$PREFIX/share/gnustep-patches/MANIFEST" 2>/dev/null || true)
EOF

# Where the runtime's DLLs are, for the launcher's PATH: every directory in
# it that holds one.
path_dirs=$(cd "$stage" && find runtime -iname '*.dll' -printf '%h\n' | sort -u | grep -v -i '\.bundle\|\.theme\|\.nssound' || true)

# Where the packager looks for the DLLs the runtime links but does not hold
# (MSYS2's), copying them in.
msys_bin=$(cygpath -w "${MINGW_PREFIX:-/clang64}/bin")

python3 - "$out/package.json" <<EOF
import json, sys, uuid

name, version = "$NAME", "${APP_VERSION:-0.0.0}"
apps, default = "$APPS".split(), "$DEFAULT"
path_dirs = """$path_dirs""".split()
# One per product, stable for good: the MSI upgrade code that makes a new
# version replace the old one.
upgrade = str(uuid.uuid5(uuid.NAMESPACE_URL, "https://github.com/$repository#" + name)).upper()

manifest = {
  "schemaVersion": 1,
  "package": {
    "id": "io.github.$repository".replace("/", ".") + "." + name,
    "name": name,
    "displayName": name,
    "version": version,
    "manufacturer": "$MANUFACTURER",
    "summary": "$SUMMARY" or name,
    "homepage": "https://github.com/$repository",
  },
  "pipeline": {
    "workingDirectory": ".",
    "shell": {"kind": "bash", "bootstrapCommands": [], "environment": {}},
    "build": {"command": "true"},
    "stage": {"command": "true", "outputRoot": "stage"},
  },
  "payload": {
    "layoutVersion": 1,
    "stageRoot": "stage",
    "appRoot": "app",
    "runtimeRoot": "runtime",
    "metadataRoot": "metadata",
    "runtimeSeedPaths": ["runtime/bin/defaults.exe"],
  },
  "launch": {
    "entryRelativePath": "app/%s.app/%s.exe" % (default, default),
    "workingDirectory": ".",
    "arguments": [],
    "pathPrepend": path_dirs,
    "env": {},
  },
  "packagedDefaults": {"defaultTheme": "$THEME"},
  "outputs": {
    "root": ".",
    "packageRoot": "packages",
    "logRoot": "logs",
    "tempRoot": "tmp",
    "validationRoot": "validation",
  },
  "validation": {
    "smoke": {"enabled": True, "kind": "staged-layout", "requiredPaths": [], "timeoutSeconds": 60, "stayAliveSeconds": 5},
    "logs": {"retainOnSuccess": True},
    # No bundled-theme contract: the packager looks for themes in the System
    # domain and MSYS2's trees, and the stack's is in Local; the stack's
    # verify and the installed smoke test check it instead.
  },
  "integrations": {"shortcutName": name, "fileAssociations": []},
  "compliance": {"runtimeNotices": [{
    "name": "GNUstep",
    "license": "LGPL-2.1-or-later",
    "source": "https://github.com/ashalkhakov/gnustep-patches",
    "stageRelativePath": "metadata/licenses/GNUstep.txt",
  }]},
  "backends": {"msi": {
    "enabled": True,
    "upgradeCode": upgrade,
    "installScope": "perUser",
    "productName": name,
    "shortcutName": name,
    "installDirectoryName": name,
    "launcherFileName": name + ".exe",
    "runtimeSearchRoots": [r"$msys_bin"],
    # Part of every Windows (LDAP, which libcurl links), missing from the
    # packager's list of system DLLs.
    "ignoredRuntimeDependencies": ["WLDAP32.dll"],
  }},
}
if "$ICON":
    manifest["backends"]["msi"]["iconRelativePath"] = "metadata/icons/app.ico"
json.dump(manifest, open(sys.argv[1], "w"), indent=2)
print("%s %s: upgrade code %s, apps %s" % (name, version, upgrade, " ".join(apps)))
EOF
echo "runtime: $(find "$stage/runtime" -type f | wc -l) files; PATH: $path_dirs"
