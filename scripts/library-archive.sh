#!/bin/bash
# A library's archive, of what make install put under <root>/<top>, for
# what builds on it (deps.sh unpacks it):
#
#   library-archive.sh <root> <top> <out-dir> <name> <suffix>
#
# writes <out-dir>/<name>-<suffix>.tar.xz. A library with parts an app need
# not carry (FreeCoreData's PostgreSQL and MySQL stores, which link their
# databases' client libraries) names them in .github/release/parts.conf, a
# shell file:
#
#   PARTS="postgresql mysql"
#   PART_postgresql="CDPostgreSQLStore CDSQLStore"
#   PART_mysql="CDMySQLStore CDSQLStore"
#
# Every installed file whose path holds one of a part's names goes into
# <name>-<part>-<suffix>.tar.xz instead (into each part that names it), and
# an app asks for the part in its pins.env (FREECOREDATA_PARTS="postgresql").
# Run from the repository's root.
set -euo pipefail
root=${1:?usage: library-archive.sh <root> <top> <out-dir> <name> <suffix>}
top=${2:?} out=${3:?} name=${4:?} suffix=${5:?}
conf=.github/release/parts.conf
PARTS=""
[ -f "$conf" ] && . "$conf"

work=$(mktemp -d)
(cd "$root" && find "$top" \( -type f -o -type l \) | sort) > "$work/all"
cp "$work/all" "$work/main"
for part in $PARTS; do
  var=PART_$part
  names=${!var:-}
  [ -n "$names" ] || { echo "::error::$conf names the part $part, and no PART_$part"; exit 1; }
  for n in $names; do grep -F -- "$n" "$work/all" || true; done | sort -u > "$work/$part"
  [ -s "$work/$part" ] || { echo "::error::the part $part ($names) is nothing make install put under $top"; exit 1; }
  tar -C "$root" -cJf "$out/$name-$part-$suffix.tar.xz" -T "$work/$part"
  grep -vxF -f "$work/$part" "$work/main" > "$work/rest" || true
  mv "$work/rest" "$work/main"
  echo "$name-$part-$suffix.tar.xz: $(wc -l < "$work/$part") files"
done
tar -C "$root" -cJf "$out/$name-$suffix.tar.xz" -T "$work/main"
echo "$name-$suffix.tar.xz: $(wc -l < "$work/main") files"
rm -rf "$work"
