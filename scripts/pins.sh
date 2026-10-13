#!/bin/bash
# A repository's pins (.github/pins.env: NAME=<full commit hash>, # for
# comments) into the job's environment (GITHUB_ENV), each checked. Used by
# the pins action and the release workflows.
#
#   FILE=source/.github/pins.env scripts/pins.sh
set -euo pipefail
[ -f "$FILE" ] || { echo "::error::no pins file at $FILE"; exit 1; }
names=()
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  line=$(printf '%s' "$line" | tr -d '[:space:]')
  [ -n "$line" ] || continue
  name=${line%%=*}
  value=${line#*=}
  if ! [[ "$name" =~ ^[A-Z][A-Z0-9_]*$ ]] || ! [[ "$value" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error file=$FILE::'$line' is not NAME=<full 40-character commit hash>"
    exit 1
  fi
  echo "$name=$value" >> "$GITHUB_ENV"
  echo "$name=$value"
  names+=("$name")
done < "$FILE"
echo "names=${names[*]}" >> "${GITHUB_OUTPUT:-/dev/null}"
