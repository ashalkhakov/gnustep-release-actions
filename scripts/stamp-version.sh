#!/bin/bash
# Writes a build's version into everything in the repository that carries
# one, the same way for every app: what each app's Scripts/stamp-version.sh
# did with its own list of files (ported from XFormsKit's, FreeCoreData's,
# HomeRow's, UDCalc's and TopoText's), done here by key across the tracked
# files, so that no app keeps a list.
#
#   stamp-version.sh [<version> [<build>]]     from the repository's root
#
# The version defaults to APP_VERSION and the build to BUILD_NUMBER (both
# version.sh's). Two forms of the version go in, because Apple parses some
# keys and GNUstep does not: the display form, the version less a leading
# "v" (0.4.3-rc1, 0.0.0-build57), which GNUstep's About panel shows; and the
# numeric form, its leading dotted number (0.4.3), where Apple requires one.
#
#   project.pbxproj, an .xcconfig
#                     MARKETING_VERSION = numeric,
#                     CURRENT_PROJECT_VERSION = build: CFBundleVersion, which
#                     Sparkle compares, so it only goes up
#   an XML plist      CFBundleShortVersionString = numeric,
#                     CFBundleVersion = build, ApplicationRelease and
#                     FullVersionID = display; only the keys it has, and not
#                     a $(VARIABLE), which Xcode fills from the project
#   an old-style one  ApplicationRelease = display, and FullVersionID beside it
#   an app's GNUmakefile (one with APP_NAME)   VERSION = display; a library's
#                     VERSION is its soname's, and is left alone
#
# Files under ThirdParty/ are not the repository's to stamp.
set -euo pipefail

version=${1:-${APP_VERSION:?usage: stamp-version.sh <version> [<build>], or APP_VERSION set}}
build=${2:-${BUILD_NUMBER:-1}}

git ls-files -z -- '*.pbxproj' '*.xcconfig' '*.plist' '*GNUmakefile' ':!:**/ThirdParty/**' \
  | python3 -c '
import re, sys
version, build = sys.argv[1], sys.argv[2]
display = version[1:] if version.startswith("v") else version
m = re.match(r"[0-9][0-9.]*", display)
numeric = m.group(0).rstrip(".") if m else "0.0.0"
stamped = []

def sub(text, pattern, value):
    # Replaces each match group 2 by value, unless it is a $(VARIABLE).
    def one(m):
        return m.group(0) if m.group(2).startswith("$(") else m.group(1) + value + m.group(3)
    return re.subn(pattern, one, text)

for path in sys.stdin.read().split("\0"):
    if not path:
        continue
    try:
        text = open(path, encoding="utf-8").read()
    except (UnicodeDecodeError, FileNotFoundError):
        continue
    before = text
    if path.endswith(".xcconfig"):
        text, _ = sub(text, r"(?m)(^\s*MARKETING_VERSION\s*=\s*)([^\n/]*?)(\s*)$", numeric)
        text, _ = sub(text, r"(?m)(^\s*CURRENT_PROJECT_VERSION\s*=\s*)([^\n/]*?)(\s*)$", build)
    elif path.endswith(".pbxproj"):
        text, _ = sub(text, r"(\bMARKETING_VERSION = )([^;]*)(;)", numeric)
        text, _ = sub(text, r"(\bCURRENT_PROJECT_VERSION = )([^;]*)(;)", build)
    elif path.endswith(".plist") and "<plist" in text:
        for key, value in (("CFBundleShortVersionString", numeric), ("CFBundleVersion", build),
                           ("ApplicationRelease", display), ("FullVersionID", display)):
            text, _ = sub(text, r"(<key>%s</key>\s*<string>)([^<]*)(</string>)" % key, value)
    elif path.endswith(".plist") and re.search(r"^\s*ApplicationRelease\s*=", text, re.M):
        text, _ = sub(text, r"(?m)(^\s*ApplicationRelease\s*=\s*\")([^\"]*)(\";)", display)
        if re.search(r"^\s*FullVersionID\s*=", text, re.M):
            text, _ = sub(text, r"(?m)(^\s*FullVersionID\s*=\s*\")([^\"]*)(\";)", display)
        else:
            text = re.sub(r"^(\s*)(ApplicationRelease\s*=\s*\"[^\"]*\";)",
                          lambda m: "%s%s\n%sFullVersionID = \"%s\";" % (m.group(1), m.group(2), m.group(1), display),
                          text, count=1, flags=re.M)
    elif path.endswith("GNUmakefile") and re.search(r"^APP_NAME\s*[+:]?=", text, re.M):
        text, _ = sub(text, r"(?m)(^VERSION\s*=\s*)(.*)()$", display)
    if text != before:
        open(path, "w", encoding="utf-8").write(text)
        stamped.append(path)

print("stamped %s (Apple: %s, build %s) into:" % (display, numeric, build))
for path in stamped:
    print("  " + path)
' "$version" "$build"
