#!/bin/bash
# A Windows build to run elsewhere: the repository as it was built (its
# tests, and what a check wrote), the GNUstep stack (C:\GNUstep) and
# CLANG64's DLLs, with a script that runs one of its programs. In an MSYS2
# shell, from the repository's directory:
#
#   build-bundle.sh <out> <repository>   <out>/<repository>-windows-build.tar.xz
#
# On Windows (tar xf it, or 7-Zip), from its directory:
#
#   run.bat source\Tests\obj\SomeTest.exe [arguments]
#
# On Linux, under Wine 9 or later (a display, or xvfb-run, for what draws):
#
#   ./run-under-wine.sh source/Tests/obj/SomeTest.exe [arguments]
#
# Without the compiler's own DLLs (LLVM's, clang's), which nothing built
# loads, and the repository's history.
set -euo pipefail
out=$1
name=${2##*/}-windows-build
work=$(mktemp -d)
root=$work/$name
mkdir -p "$root/drive_c/GNUstep" "$root/drive_c/clang64/bin" "$root/source"

tar -C "${PREFIX:-/c/GNUstep}" -cf - . | tar -C "$root/drive_c/GNUstep" -xf -
find /clang64/bin -maxdepth 1 -name '*.dll' \
  ! -name 'libLLVM*' ! -name 'libclang*' ! -name 'liblldb*' ! -name 'libMLIR*' \
  -exec cp {} "$root/drive_c/clang64/bin/" \;
tar -cf - --exclude=.git . | tar -C "$root/source" -xf -
# Fontconfig's configuration (cairo finds fonts through it), as the
# installer carries it.
mkdir -p "$root/drive_c/clang64/etc" && cp -a /clang64/etc/fonts "$root/drive_c/clang64/etc/"

cat > "$root/run-under-wine.sh" <<'EOF'
#!/bin/sh
# Runs one of the repository's programs under Wine, as the check ran it:
# GNUstep's and CLANG64's DLLs found on Windows' PATH, GNUstep's paths as
# they were (C:\GNUstep). The Wine prefix is this directory's own.
set -e
here=$(cd "$(dirname "$0")" && pwd)
export WINEPREFIX="${WINEPREFIX:-$here/prefix}"
export WINEDEBUG="${WINEDEBUG:--all}"
[ -d "$WINEPREFIX" ] || wineboot -i >/dev/null 2>&1
for d in GNUstep clang64; do
  [ -e "$WINEPREFIX/drive_c/$d" ] || ln -s "$here/drive_c/$d" "$WINEPREFIX/drive_c/$d"
done
# The repository's own DLLs (a framework's, a library's) where it built
# them, as its check finds them on PATH: Wine's Z: is /.
own=$(find "$here/source" -name '*.dll' -exec dirname {} \; | sort -u | sed 's|/|\\|g; s|^|Z:|' | tr '\n' ';')
export WINEPATH="${own}C:\\GNUstep\\bin;C:\\GNUstep\\Local\\Tools;C:\\GNUstep\\System\\Tools;C:\\GNUstep\\Local\\Library\\Libraries;C:\\GNUstep\\System\\Library\\Libraries;C:\\clang64\\bin"
exec wine "$@"
EOF
chmod +x "$root/run-under-wine.sh"

# The same on Windows: the repository's DLL directories, then the stack's
# and CLANG64's, from this directory.
{
  echo '@echo off'
  echo 'rem Runs one of the repository'"'"'s programs with the DLLs it was built on.'
  echo 'set "H=%~dp0"'
  printf 'set "PATH='
  (cd "$root" && find source -name '*.dll' -exec dirname {} \; | sort -u | sed 's|/|\\|g; s|^|%H%|' | tr '\n' ';')
  echo '%H%drive_c\GNUstep\bin;%H%drive_c\GNUstep\Local\Tools;%H%drive_c\GNUstep\System\Tools;%H%drive_c\GNUstep\Local\Library\Libraries;%H%drive_c\GNUstep\System\Library\Libraries;%H%drive_c\clang64\bin;%PATH%"'
  echo 'set "FONTCONFIG_PATH=%H%drive_c\clang64\etc\fonts"'
  echo 'set "FONTCONFIG_FILE=%H%drive_c\clang64\etc\fonts\fonts.conf"'
  echo '%*'
} | sed 's/$/\r/' > "$root/run.bat"

mkdir -p "$out"
tar -C "$work" -cJf "$out/$name.tar.xz" "$name"
rm -rf "$work"
ls -l "$out/$name.tar.xz"
