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
#   BUILD_NUMBER  the build (version.sh's), which the updater compares
#   SPARKLE_PRIVATE_KEY  the Mac's Sparkle key (generate_keys -x), whose
#                 public half the installed app checks its feed with
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
#   ICON          the shortcut's and installer's icon: an .ico, or a PNG of
#                 at most 256x256, which goes into one as it is
#   MANUFACTURER  who makes it (default: the repository's owner)
#   SUMMARY       one line on what it is
#   SMOKE         the installed app's smoke test: the arguments to start it
#                 with (--self-test); it must exit 0
#   SMOKE_STAYS_UP  for an app with no self-test, a smoke test of another
#                 kind: started bare, it must still be running this many
#                 seconds later, its nibs loaded
#   THEME         its look (default: WinUXTheme, the native one)
set -euo pipefail

conf=${1:?usage: msi.sh <windows.conf> <out-dir>}
out=${2:?usage: msi.sh <windows.conf> <out-dir>}
NAME="" APPS="" DEFAULT="" ICON="" MANUFACTURER="" SUMMARY="" SMOKE="" SMOKE_STAYS_UP="" THEME=""
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

# Fontconfig's configuration (cairo finds fonts through it), MSYS2's, which
# reads Windows' own fonts folder: the launcher points FONTCONFIG_FILE at
# runtime\etc\fonts\fonts.conf when it is there.
mkdir -p "$stage/runtime/etc"
cp -a "${MINGW_PREFIX:-/clang64}/etc/fonts" "$stage/runtime/etc/"

# The certificate authorities HTTPS is checked against, MSYS2's: libcurl
# (gnustep-base's NSURLSession) reads them from ..\etc\ssl\certs beside its
# own DLL, and without them no secure connection is made at all.
mkdir -p "$stage/runtime/etc/ssl/certs"
cp "${MINGW_PREFIX:-/clang64}/etc/ssl/certs/ca-bundle.crt" "$stage/runtime/etc/ssl/certs/"

# WinSparkle, which the stack's GSUpdater loads (deps.sh put it in .deps),
# and its licence.
if [ -f .deps/WinSparkle/WinSparkle.dll ]; then
  cp .deps/WinSparkle/WinSparkle.dll "$stage/runtime/bin/"
  cp .deps/WinSparkle/COPYING "$stage/metadata/licenses/WinSparkle.txt"
fi

# What GSUpdater reads from each app's Info-gnustep.plist, so that no app
# keeps it: the build (CFBundleVersion, which the feed's sparkle:version is
# compared with) and, with the Sparkle key, the feed (the latest release's
# appcast-windows.xml, which windows.yml writes) and the key's public half.
# An app's own SUWindowsFeedURL or SUPublicEDKey is kept. Without the key
# there is no feed, and GSUpdater gives no updates.
for app in $APPS; do
  plist="$stage/app/$app.app/Resources/Info-gnustep.plist"
  [ -f "$plist" ] || continue
  FEED="https://github.com/$repository/releases/latest/download/appcast-windows.xml" \
    python3 - "$(dirname "$0")" "$plist" <<'PY'
import base64, os, re, sys
sys.path.insert(0, sys.argv[1])
from appcast import public_key, seed_of

path = sys.argv[2]
text = open(path, encoding="utf-8").read()
xml = "<plist" in text

def has(key):
    return re.search((r"<key>%s</key>" if xml else r"(?<![\w.])\"?%s\"?\s*=") % key, text)

def put(key, value):
    global text
    if xml:
        entry = "<key>%s</key>\n\t<string>%s</string>" % (key, value)
        found = re.search(r"<key>%s</key>\s*<[^>]*>[^<]*</[^>]*>" % key, text)
        if found:
            text = text[:found.start()] + entry + text[found.end():]
        else:
            at = text.rindex("</dict>")
            text = text[:at] + "\t" + entry + "\n" + text[at:]
    else:
        entry = '%s = "%s";' % (key, value)
        found = re.search(r"(?<![\w.])\"?%s\"?\s*=\s*(\"[^\"]*\"|[^;]*);" % key, text)
        if found:
            text = text[:found.start()] + entry + text[found.end():]
        else:
            at = text.rindex("}")
            text = text[:at].rstrip() + "\n  " + entry + "\n" + text[at:]

said = []
put("CFBundleVersion", os.environ.get("BUILD_NUMBER") or "0")
said.append("build %s" % (os.environ.get("BUILD_NUMBER") or "0"))
key = os.environ.get("SPARKLE_PRIVATE_KEY", "")
if key:
    if not has("SUWindowsFeedURL"):
        put("SUWindowsFeedURL", os.environ["FEED"])
    if not has("SUPublicEDKey"):
        put("SUPublicEDKey", base64.b64encode(public_key(seed_of(key))).decode())
    said.append("its updates from %s" % re.search(
        (r"<key>SUWindowsFeedURL</key>\s*<string>([^<]*)" if xml
         else r"SUWindowsFeedURL\"?\s*=\s*\"?([^\";]*)"), text).group(1))
else:
    said.append("no updates (no SPARKLE_PRIVATE_KEY)")
open(path, "w", encoding="utf-8").write(text)
print("%s: %s" % (path, ", ".join(said)))
PY
done

if [ -n "$ICON" ]; then
  [ -f "$ICON" ] || { echo "::error::$conf names ICON $ICON, which is not there" >&2; exit 1; }
  case "$ICON" in
    *.png|*.PNG)
      # An .ico of one image, the PNG itself (Windows Vista on): a width or
      # height of 256 is written 0.
      python3 - "$ICON" "$stage/metadata/icons/app.ico" <<'PY'
import struct, sys
png = open(sys.argv[1], 'rb').read()
w, h = struct.unpack('>II', png[16:24])
if png[:8] != b'\x89PNG\r\n\x1a\n' or w > 256 or h > 256:
    sys.exit(f"{sys.argv[1]}: not a PNG of at most 256x256")
open(sys.argv[2], 'wb').write(struct.pack('<HHH', 0, 1, 1)
    + struct.pack('<BBBBHHII', w % 256, h % 256, 0, 0, 1, 32, len(png), 22) + png)
PY
      ;;
    *) cp "$ICON" "$stage/metadata/icons/app.ico" ;;
  esac
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
    # The theme as an argument: a default the launcher seeds goes into one
    # domain of the package's name, which an app reads only if its bundle
    # identifier is that; an argument every app reads.
    "arguments": ["-GSTheme", "$THEME"],
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
    # Part of every Windows, missing from the packager's list of system
    # DLLs: LDAP, which libcurl links; WinINet, WinSparkle's.
    "ignoredRuntimeDependencies": ["WLDAP32.dll", "WININET.dll"],
  }},
}
if "$ICON":
    manifest["backends"]["msi"]["iconRelativePath"] = "metadata/icons/app.ico"
json.dump(manifest, open(sys.argv[1], "w"), indent=2)
print("%s %s: upgrade code %s, apps %s" % (name, version, upgrade, " ".join(apps)))
EOF
echo "runtime: $(find "$stage/runtime" -type f | wc -l) files; PATH: $path_dirs"
