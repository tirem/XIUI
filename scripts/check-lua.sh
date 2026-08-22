#!/usr/bin/env bash

set -u

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

if ! command -v luajit >/dev/null 2>&1; then
    echo 'LuaJIT is required to check XIUI Lua files.' >&2
    exit 2
fi

mapfile -d '' lua_files < <(find "${repository_root}/XIUI" -type f -name '*.lua' -print0 | sort -z)

failure_count=0
for lua_file in "${lua_files[@]}"; do
    if ! luajit -b "${lua_file}" "${temporary_directory}/output.ljbc"; then
        failure_count=$((failure_count + 1))
    fi
done

if (( failure_count > 0 )); then
    echo "LuaJIT parse failures: ${failure_count}" >&2
    exit 1
fi

echo "LuaJIT parsed ${#lua_files[@]} files."
