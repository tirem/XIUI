#!/usr/bin/env bash

set -euo pipefail

MOONJIT_BIN=${1:?Usage: check-changed.sh /path/to/moonjit repository base-sha head-sha}
REPOSITORY=${2:?Usage: check-changed.sh /path/to/moonjit repository base-sha head-sha}
BASE_SHA=${3:?Usage: check-changed.sh /path/to/moonjit repository base-sha head-sha}
HEAD_SHA=${4:?Usage: check-changed.sh /path/to/moonjit repository base-sha head-sha}

CHANGED_FILES=$(mktemp)
trap 'rm -f "$CHANGED_FILES"' EXIT
git -C "$REPOSITORY" diff --find-renames --diff-filter=ACMRT \
    --name-only -z "$BASE_SHA...$HEAD_SHA" -- '*.lua' > "$CHANGED_FILES"

count=0
while IFS= read -r -d '' lua_file; do
    XIUI_LUA_FILE="$REPOSITORY/$lua_file" "$MOONJIT_BIN" -e \
        "local path = os.getenv('XIUI_LUA_FILE'); local chunk, err = loadfile(path, 't'); assert(chunk, err)"
    count=$((count + 1))
done < "$CHANGED_FILES"

if ((count == 0)); then
    printf 'No changed Lua files to check.\n'
elif ((count == 1)); then
    printf 'MoonJIT parsed 1 changed Lua file.\n'
else
    printf 'MoonJIT parsed %d changed Lua files.\n' "$count"
fi
