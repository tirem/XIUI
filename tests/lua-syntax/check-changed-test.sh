#!/usr/bin/env bash

set -euo pipefail

MOONJIT_BIN=${1:?Usage: check-changed-test.sh /path/to/moonjit}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECKER="$SCRIPT_DIR/check-changed.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

REPOSITORY="$TEST_ROOT/repository"
mkdir -p "$REPOSITORY/source"
git -C "$REPOSITORY" init --quiet
git -C "$REPOSITORY" config user.email tests@example.invalid
git -C "$REPOSITORY" config user.name "Lua Syntax Tests"

printf 'if true then; return true; end\n' > "$REPOSITORY/source/existing.lua"
printf 'local value =\n' > "$REPOSITORY/source/unchanged-invalid.lua"
ln -s existing.lua "$REPOSITORY/source/type-change.lua"
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit --quiet -m base
BASE_SHA=$(git -C "$REPOSITORY" rev-parse HEAD)

printf 'if true then; return true; end\n' > "$REPOSITORY/source/added.lua"
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit --quiet -m valid
VALID_SHA=$(git -C "$REPOSITORY" rev-parse HEAD)

VALID_OUTPUT=$("$CHECKER" "$MOONJIT_BIN" "$REPOSITORY" "$BASE_SHA" "$VALID_SHA")
[[ "$VALID_OUTPUT" == 'MoonJIT parsed 1 changed Lua file.' ]]

if "$CHECKER" "$MOONJIT_BIN" "$REPOSITORY" missing-base "$VALID_SHA" \
    > "$TEST_ROOT/missing-base.log" 2>&1; then
    printf 'Expected an unavailable base revision to fail.\n' >&2
    exit 1
fi

unlink "$REPOSITORY/source/type-change.lua"
printf 'local changed_type =\n' > "$REPOSITORY/source/type-change.lua"
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit --quiet -m type-change
TYPE_CHANGE_SHA=$(git -C "$REPOSITORY" rev-parse HEAD)

if TYPE_CHANGE_OUTPUT=$("$CHECKER" "$MOONJIT_BIN" "$REPOSITORY" \
    "$VALID_SHA" "$TYPE_CHANGE_SHA" 2>&1); then
    printf 'Expected an invalid Lua type change to fail.\n' >&2
    exit 1
fi
[[ "$TYPE_CHANGE_OUTPUT" == *'source/type-change.lua'* ]]

BYTECODE_PATH="$REPOSITORY/source/bytecode.lua"
XIUI_BYTECODE_PATH="$BYTECODE_PATH" "$MOONJIT_BIN" -e \
    "local path = os.getenv('XIUI_BYTECODE_PATH'); local output = assert(io.open(path, 'wb')); output:write(string.dump(function () return true end)); assert(output:close())"
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit --quiet -m bytecode
BYTECODE_SHA=$(git -C "$REPOSITORY" rev-parse HEAD)

if "$CHECKER" "$MOONJIT_BIN" "$REPOSITORY" "$TYPE_CHANGE_SHA" "$BYTECODE_SHA" \
    > "$TEST_ROOT/bytecode.log" 2>&1; then
    printf 'Expected Lua bytecode disguised as source to fail.\n' >&2
    exit 1
fi

printf 'local first =\n' > "$REPOSITORY/source/a-first-invalid.lua"
printf 'local second =\n' > "$REPOSITORY/source/z-second-invalid.lua"
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit --quiet -m invalid
INVALID_SHA=$(git -C "$REPOSITORY" rev-parse HEAD)

if INVALID_OUTPUT=$("$CHECKER" "$MOONJIT_BIN" "$REPOSITORY" \
    "$BYTECODE_SHA" "$INVALID_SHA" 2>&1); then
    printf 'Expected changed invalid Lua to fail.\n' >&2
    exit 1
fi
[[ "$INVALID_OUTPUT" == *'source/a-first-invalid.lua'* ]]
[[ "$INVALID_OUTPUT" != *'source/z-second-invalid.lua'* ]]

git -C "$REPOSITORY" mv source/existing.lua source/renamed.lua
git -C "$REPOSITORY" commit --quiet -m renamed
RENAMED_SHA=$(git -C "$REPOSITORY" rev-parse HEAD)

RENAMED_OUTPUT=$("$CHECKER" "$MOONJIT_BIN" "$REPOSITORY" \
    "$INVALID_SHA" "$RENAMED_SHA")
[[ "$RENAMED_OUTPUT" == 'MoonJIT parsed 1 changed Lua file.' ]]

printf 'documentation only\n' > "$REPOSITORY/README.md"
git -C "$REPOSITORY" add README.md
git -C "$REPOSITORY" commit --quiet -m documentation
DOCUMENTATION_SHA=$(git -C "$REPOSITORY" rev-parse HEAD)

DOCUMENTATION_OUTPUT=$("$CHECKER" "$MOONJIT_BIN" "$REPOSITORY" \
    "$RENAMED_SHA" "$DOCUMENTATION_SHA")
[[ "$DOCUMENTATION_OUTPUT" == 'No changed Lua files to check.' ]]

printf 'All changed-Lua selector tests passed.\n'
