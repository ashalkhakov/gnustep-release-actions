#!/bin/bash
# What a failed Windows check ran, to run again under Wine on Linux: the
# repository as it was built (its tests, and what they wrote), the GNUstep
# stack (C:\GNUstep) and CLANG64's DLLs, with a script that runs one of its
# programs. In an MSYS2 shell, from the repository's directory:
#
#   wine-bundle.sh <out> <repository>   <out>/<repository>-windows-wine.tar.xz
#
# On Linux (Wine 9 or later; a display, or xvfb-run, for what draws):
#
#   tar xf <repository>-windows-wine.tar.xz && cd <repository>-windows-wine
#   ./run-under-wine.sh source/Tests/obj/SomeTest.exe [arguments]
#
# Without the compiler's own DLLs (LLVM's, clang's), which nothing built
# loads, and the repository's history.
set -euo pipefail
out=$1
name=${2##*/}-windows-wine
work=$(mktemp -d)
root=$work/$name
mkdir -p "$root/drive_c/GNUstep" "$root/drive_c/clang64/bin" "$root/source"

tar -C "${PREFIX:-/c/GNUstep}" -cf - . | tar -C "$root/drive_c/GNUstep" -xf -
find /clang64/bin -maxdepth 1 -name '*.dll' \
  ! -name 'libLLVM*' ! -name 'libclang*' ! -name 'liblldb*' ! -name 'libMLIR*' \
  -exec cp {} "$root/drive_c/clang64/bin/" \;
tar -cf - --exclude=.git . | tar -C "$root/source" -xf -

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
export WINEPATH='C:\GNUstep\bin;C:\GNUstep\Local\Tools;C:\GNUstep\System\Tools;C:\GNUstep\Local\Library\Libraries;C:\GNUstep\System\Library\Libraries;C:\clang64\bin'
exec wine "$@"
EOF
chmod +x "$root/run-under-wine.sh"

mkdir -p "$out"
tar -C "$work" -cJf "$out/$name.tar.xz" "$name"
rm -rf "$work"
ls -l "$out/$name.tar.xz"
