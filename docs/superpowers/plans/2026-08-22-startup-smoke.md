# XIUI Startup Smoke Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic MoonJIT harness that loads the real XIUI entry point and runs its registered load callback without FFXI.

**Architecture:** Keep every XIUI-owned module real and replace only Ashita-owned globals, modules, managers, storage, graphics, time, packets, and optional WinMM loading. Compose those strict fakes through one isolated environment that restores globals and `package` state after every test case.

**Tech Stack:** MoonJIT commit `a2a39ea7184f3c8cab9474c6e41f6541265fb362`, `LUAJIT_ENABLE_LUA52COMPAT`, Lua, LuaJIT FFI, Bash, GitHub Actions, Ruby Psych for local YAML parsing, ZIP inspection.

**Spec:** `docs/superpowers/specs/2026-08-22-startup-smoke-design.md`

## Global Constraints

- Base the branch on `beta-1.8.4-tanyrus` at `9153145`.
- Keep production modules real. Use `package.preload` only for host-owned `common`, `chat`, `settings`, `imgui`, `d3d8`, `struct`, `bitreader`, `win32types`, and the FFI wrapper.
- Keep every test and fixture under `tests/startup/`, outside `XIUI/`.
- Run tests with the pinned MoonJIT revision built using `LUAJIT_ENABLE_LUA52COMPAT`.
- Do not launch FFXI and do not claim Windows, Wine, Proton, D3D, or WinMM runtime validation.
- Do not add dependencies.
- Do not use catch-all host fakes. Unknown host operations must identify the missing operation and fail.
- Do not touch user files. All profile, settings, packet, and filesystem effects stay in memory.
- Do not change production source unless the real startup graph reveals a separate defect and the user approves that fix.
- For each observable contract, record the expected red result, pass the smallest implementation, deliberately mutate the behavior, observe red again, then restore green.
- Audit tests before handoff and remove cases that catch no distinct production mutation.
- Do not open a pull request until explicitly requested.

---

## File Map

| File | Responsibility |
|---|---|
| `tests/startup/run.lua` | Test runner, assertions, four startup behavior cases, and four harness-boundary cases |
| `tests/startup/support/host.lua` | Environment composition, addon loading, callback dispatch, initializer observation, state restoration |
| `tests/startup/support/fake_common.lua` | Ashita `common` table/string helpers and `T` constructor |
| `tests/startup/support/fake_ashita.lua` | Event registry, AshitaCore managers, memory/resource/chat/task boundaries |
| `tests/startup/support/fake_imgui.lua` | Explicit ImGui import and initialization surface |
| `tests/startup/support/fake_d3d8.lua` | Explicit neutral texture, device, and draw-list values used during initialization |
| `tests/startup/support/fake_filesystem.lua` | Existing virtual profile, XIUI source loading, rejected unknown reads, and mutation logs |
| `tests/startup/support/fake_clock.lua` | Deterministic `os.time` and `os.clock` installation and restoration |
| `tests/startup/support/fake_packets.lua` | Packet manager and exact outgoing-packet capture |
| `.github/workflows/startup-smoke.yml` | Five-minute, path-scoped compatible-MoonJIT CI job |

---

### Task 1: Load the Real Entry Graph and Capture Events

**Files:**

- Create: `tests/startup/run.lua`
- Create: `tests/startup/support/host.lua`
- Create: `tests/startup/support/fake_common.lua`
- Create: `tests/startup/support/fake_ashita.lua`
- Create: `tests/startup/support/fake_imgui.lua`
- Create: `tests/startup/support/fake_d3d8.lua`
- Create: `tests/startup/support/fake_filesystem.lua`
- Create: `tests/startup/support/fake_clock.lua`
- Create: `tests/startup/support/fake_packets.lua`

**Interfaces:**

- Produces: `host.with_environment(options, run)`
- Produces: `environment.load_addon()`
- Produces: `environment.get_event(event_name, callback_key)`
- Produces: `environment.invoke_event(event_name, callback_key, event)`
- Produces: `environment.logs` containing `events`, `invoked_events`, `winmm_loads`, `packets`, `filesystem_mutations`, `settings_saves`, `initializer_calls`, `memory_scans`, and `host_calls`
- Guarantees: `with_environment` restores process state through protected finalization before returning or rethrowing an error

- [x] **Step 1: Write the first failing startup case**

Create `tests/startup/run.lua` with the test path first, a small exact-output runner, and this first case:

```lua
local ORIGINAL_PACKAGE_PATH = package.path;
package.path = 'tests/startup/?.lua;tests/startup/?/init.lua;XIUI/?.lua;XIUI/?/init.lua;' .. package.path;

local host = require('support.host');

local function expect_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)), 2);
    end
end

local function expect_type(actual, expected, message)
    expect_equal(type(actual), expected, message);
end

local tests = {
    {
        name = 'real addon graph registers the load callback',
        run = function()
            host.with_environment({ winmm_available = false }, function(environment)
                environment.load_addon();
                expect_type(environment.get_event('load', 'load_cb'), 'function', 'registered load callback');
            end);
        end,
    },
};

local failed = 0;
for _, test in ipairs(tests) do
    local ok, err = xpcall(test.run, debug.traceback);
    if ok then
        io.write('PASS ', test.name, '\n');
    else
        failed = failed + 1;
        io.stderr:write('FAIL ', test.name, '\n', err, '\n');
    end
end

package.path = ORIGINAL_PACKAGE_PATH;
if failed ~= 0 then
    error(string.format('%d startup test(s) failed', failed));
end
io.write(string.format('%d startup tests passed\n', #tests));
```

- [x] **Step 2: Run the case and record RED**

Run:

```bash
test -x "$MOONJIT_BIN"
"$MOONJIT_BIN" tests/startup/run.lua
```

Expected: FAIL because `support.host` does not exist. Record the exact missing-module error in the implementation notes.

- [x] **Step 3: Implement Ashita common helpers**

Create `tests/startup/support/fake_common.lua` with `install()` returning a restore function. Install only the helpers used by XIUI startup:

```lua
local M = {};

local function contains(values, wanted)
    for _, value in ipairs(values) do
        if value == wanted then return true; end
    end
    return false;
end

local function any(value, ...)
    for index = 1, select('#', ...) do
        if value == select(index, ...) then return true; end
    end
    return false;
end

local table_methods = {
    append = function(self, value)
        self[#self + 1] = value;
        return self;
    end,
    contains = contains,
};

local table_metatable = { __index = table_methods };

local function T(value)
    return setmetatable(value or {}, table_metatable);
end

function M.install()
    local previous_T = rawget(_G, 'T');
    local previous_contains = table.contains;
    local string_index = getmetatable('').__index;
    local previous_any = string_index.any;
    table.contains = contains;
    string_index.any = any;
    _G.T = T;
    return function()
        _G.T = previous_T;
        table.contains = previous_contains;
        string_index.any = previous_any;
    end;
end

return M;
```

Keep chat chaining separate: each `chat.header`, `chat.message`, `chat.success`, and `chat.error` returns an object whose `append` method concatenates `tostring(value)` and returns itself.

- [x] **Step 4: Implement deterministic clock and packet boundaries**

Create `fake_clock.lua`:

```lua
local M = {};

function M.install(epoch, monotonic)
    local original_time = os.time;
    local original_clock = os.clock;
    os.time = function() return epoch; end;
    os.clock = function() return monotonic; end;
    return function()
        os.time = original_time;
        os.clock = original_clock;
    end;
end

return M;
```

Create `fake_packets.lua` with `new(log)` returning a manager that implements both `AddOutgoingPacket(id, data)` and `AddIncomingPacket(id, data)`. Append exact records `{ direction = 'out'|'in', id = id, data = data }` to `log` and return `true`.

- [x] **Step 5: Implement the virtual startup filesystem**

Create `fake_filesystem.lua` with:

```lua
local INSTALL_PATH = 'C:\\Ashita\\';
local CONFIG_PATH = INSTALL_PATH .. 'config\\addons\\xiui\\';
local PROFILES_PATH = CONFIG_PATH .. 'profiles\\';
local PROFILE_LIST_PATH = PROFILES_PATH .. 'profilelist.lua';
local DEFAULT_PROFILE_PATH = PROFILES_PATH .. 'Default.lua';

local initial_files = {
    [PROFILE_LIST_PATH] = {
        value = { version = '1.8.4', names = { 'Default' }, order = { 'Default' } },
    },
    [DEFAULT_PROFILE_PATH] = { value = {} },
};
```

Expose `new(mutation_log)` returning:

- `install_path = INSTALL_PATH`
- `ashita_fs.exists(path)` for the config, profiles, backups directories and the two files
- `ashita_fs.get_directory(path, pattern)` returning `{ 'profilelist.lua', 'Default.lua' }` only for `PROFILES_PATH`, otherwise `{}`
- `ashita_fs.get_dir` as the same function
- `ashita_fs.create_directory(path)` and `create_dir(path)` that append `{ operation = 'mkdir', path = path }`
- `loadfile(path)` returning a function that deep-copies the virtual `value` for known virtual files, delegating only paths below `XIUI/` to the original loader, and rejecting every other path
- `dofile(path)` using the restricted `loadfile` boundary
- `io.open(path, mode)` rejecting reads and recording any mode containing `w`, `a`, or `+`
- `os.remove(path)` and `os.rename(source, destination)` recording exact mutations and returning success without changing disk
- `restore()` restoring `loadfile`, `dofile`, `io.open`, `os.remove`, and `os.rename`

Do not make unknown files exist or delegate unknown reads to the host filesystem. This keeps migrations and backups inactive for the valid 1.8.4 fixture and prevents tests from reading repository or user files accidentally.

- [x] **Step 6: Implement explicit ImGui and D3D import surfaces**

Create `fake_imgui.lua` with `install()` returning an `imgui` table plus a restore function. Define these import and initialization functions explicitly:

```lua
local imgui = {
    BeginChild = function() return true; end,
    BeginDisabled = function() end,
    EndDisabled = function() end,
    GetIO = function()
        return { DisplaySize = { x = 1920, y = 1080 }, FontGlobalScale = 1 };
    end,
    GetStyle = function() return { Alpha = 1 }; end,
    GetFont = function() return { FontSize = 13 }; end,
    PushStyleVar = function() end,
    PopStyleVar = function() end,
    GetColorU32 = function() return 0; end,
};
```

Install explicit numeric globals needed while modules are imported: `ImGuiChildFlags_None`, `ImGuiCol_Header`, `ImGuiCol_HeaderHovered`, `ImGuiCol_HeaderActive`, `ImGuiCol_ScrollbarGrab`, `ImGuiCol_ScrollbarGrabActive`, `ImGuiStyleVar_Alpha`, and the main-branch `ImDrawCornerFlags_*` values. Leave `ImGuiChildFlags_Borders` nil so the harness follows the supported main compatibility route.

Create `fake_d3d8.lua` with `new()` returning neutral objects:

- `texture.image = nil`, so texture dimension probes take their existing nil/fallback paths
- `device = nil`, so `libs.memory` and texture loading remain unavailable instead of exposing fake native pointers
- font atlas methods `AddFontFromFileTTF` and `Build` return nil and true respectively only when called through the explicit ImGui IO font atlas fake

- [x] **Step 7: Implement the Ashita event and manager boundary**

Create `fake_ashita.lua` with `install(options, logs, filesystem, packets)`. Provide:

```lua
local callbacks = {};

local events = {
    register = function(event_name, callback_key, callback)
        callbacks[event_name] = callbacks[event_name] or {};
        callbacks[event_name][callback_key] = callback;
        logs.events[#logs.events + 1] = { event = event_name, key = callback_key };
    end,
    unregister = function(event_name, callback_key)
        if callbacks[event_name] then callbacks[event_name][callback_key] = nil; end
    end,
};
```

Provide `ashita.fs` from `fake_filesystem`, `ashita.tasks.once` that records the scheduled delay without invoking deferred work, and `ashita.misc.play_sound` as a recorded no-op. `ashita.memory.find` returns nonzero only when its direct caller is `XIUI/libs/ffxi/macros.lua` during entry import, because that library rejects missing pointers at module scope. Record every scan, disable the exception as soon as `XIUI/XIUI.lua` returns, and return zero for every other scan. Numeric memory reads return zero, memory writes fail with `unexpected startup memory write`, and `ashita.bits.unpack_be` returns zero.

Provide `AshitaCore` methods with explicit managers:

- `GetInstallPath()` returns `filesystem.install_path`
- `GetPacketManager()` returns `fake_packets`
- `GetChatManager():QueueCommand(...)` records the command and returns true
- `GetMemoryManager():GetParty()` returns a neutral party with `GetMemberZone(0) == 0` and inactive members
- `GetMemoryManager():GetPlayer()` returns a neutral player with `GetLoginStatus() == 0`
- `GetMemoryManager():GetEntity()`, `GetInventory()`, `GetTarget()`, and recast managers return neutral explicit objects or nil as expected by safe wrappers
- `GetResourceManager()` returns an explicit resource manager whose item, spell, ability, string, status-icon, and key-item lookups return nil
- `GetPointerManager():Get(...)` returns zero
- `GetFontManager()`, `GetGuiManager()`, and `GetAddonManager()` return explicit neutral managers used only during imports

Return `callbacks` and a restore function for `_G.ashita`, `_G.AshitaCore`, and host constants.

- [x] **Step 8: Compose isolation and addon loading**

Create `host.lua` with constants for `XIUI/XIUI.lua`, XIUI module prefixes, fake preload names, and globals modified by XIUI. `with_environment` must:

1. Snapshot `package.path`, `package.preload`, every `package.loaded` entry, and modified globals.
2. Install common, clock, filesystem, ImGui, packet, Ashita, chat, settings, and FFI boundaries.
3. Set `_G.addon = { path = 'XIUI\\', name = 'XIUI' }` and `_G.struct = { unpack = function() return 0; end }`.
4. Expose `load_addon()` using `assert(loadfile('XIUI/XIUI.lua'))()`.
5. Expose exact event lookup and invocation.
6. Restore initializer wrappers, globals, original library functions, preloads, loaded modules, and `package.path` in reverse install order inside protected cleanup.

The FFI preload must proxy the real FFI table explicitly and replace only `load`:

```lua
local native_ffi = package.loaded.ffi or require('ffi');
local ffi = {};
for key, value in pairs(native_ffi) do ffi[key] = value; end
ffi.load = function(name, ...)
    if tostring(name):lower() == 'winmm' then
        logs.winmm_loads[#logs.winmm_loads + 1] = name;
        if not options.winmm_available then error('winmm unavailable', 2); end
    end
    return native_ffi.load(name, ...);
end;
package.loaded.ffi = nil;
package.preload.ffi = function() return ffi; end;
```

Cleanup restores both the original `package.loaded.ffi` value and the original `package.preload.ffi` loader before the next case.

Load native FFI once when `support.host` is imported, before any per-case package snapshot. Reopening FFI after cleanup reinitializes MoonJIT's global C-type state and can leave earlier cdata with invalid type IDs.

Use an in-memory `settings` preload whose `load(defaults)` returns `{ currentProfile = 'Default' }` merged over the supplied defaults and whose `save()` appends one record to `logs.settings_saves`. The `chat` preload uses the appendable values from Step 3.

- [x] **Step 9: Iterate missing host operations without weakening strictness**

Run the case after each explicit host addition:

```bash
"$MOONJIT_BIN" tests/startup/run.lua
```

For each failure, record the exact missing external method, locate its production call with `rg`, add that one method with the neutral return documented at its call site, and rerun. Do not add `__index` fallbacks to managers, ImGui, globals, or resource objects.

Expected GREEN: `PASS real addon graph registers the load callback` and `1 startup tests passed`.

- [x] **Step 10: Verify environment isolation**

Run the suite twice in the same MoonJIT process by adding a temporary second invocation of the case function. Expected: both runs register a fresh `load_cb` and neither reports duplicate registration or a previously loaded XIUI module. Remove the temporary duplicate invocation after observing the pass.

- [x] **Step 11: Commit the entry-graph harness**

```bash
git add tests/startup
git commit -m "test: load the XIUI graph without FFXI"
```

---

### Task 2: Execute and Observe Every Registered Initializer

**Files:**

- Modify: `tests/startup/run.lua`
- Modify: `tests/startup/support/host.lua`
- Modify: `tests/startup/support/fake_ashita.lua`
- Modify: `tests/startup/support/fake_imgui.lua`
- Modify: `tests/startup/support/fake_d3d8.lua`

**Interfaces:**

- Consumes: `host.with_environment`, `environment.load_addon`, `environment.invoke_event`
- Produces: `environment.observe_initializers()` returning the sorted expected initializer names
- Produces: `environment.logs.initializer_calls` containing the sorted actual initializer names after callback execution

- [x] **Step 1: Add the callback execution case**

Append this case to `tests/startup/run.lua`:

```lua
{
    name = 'registered load callback completes without a live game host',
    run = function()
        host.with_environment({ winmm_available = false }, function(environment)
            environment.load_addon();
            local expected = environment.observe_initializers();
            environment.invoke_event('load', 'load_cb');
            expect_sequence(environment.logs.initializer_calls, expected, 'registered initializer calls');
        end);
    end,
},
```

Add `expect_sequence` using exact length and per-index equality. Both expected and actual lists are sorted before comparison.

- [x] **Step 2: Run and record callback RED**

```bash
"$MOONJIT_BIN" tests/startup/run.lua
```

Expected: the registration case passes and the callback case fails at the first missing initialization boundary. Record the exact method and stack trace.

- [x] **Step 3: Implement initializer observation**

In `host.lua`, after the addon is loaded:

```lua
function environment.observe_initializers()
    local registry = assert(package.loaded['core.moduleregistry']);
    local expected = {};
    for name, entry in pairs(registry.GetAll()) do
        if type(entry.module.Initialize) == 'function' then
            local original = entry.module.Initialize;
            expected[#expected + 1] = name;
            initializer_restores[#initializer_restores + 1] = function()
                entry.module.Initialize = original;
            end;
            entry.module.Initialize = function(...)
                logs.initializer_calls[#logs.initializer_calls + 1] = name;
                return original(...);
            end;
        end
    end
    table.sort(expected);
    return expected;
end
```

Sort `logs.initializer_calls` after callback invocation and before returning from `invoke_event('load', ...)`. Restore wrappers before clearing `package.loaded`.

- [x] **Step 4: Extend only explicit initialization boundaries**

Use callback failures to add the required neutral operations. The expected initialization surface includes:

- neutral texture misses from `TextureManager.getFileTexture`
- party and player getters returning inactive or logged-out state
- `ashita.tasks.once` recording but not executing delayed hotbar retries
- native signature scans returning zero after the caller-scoped macro import exception is disabled
- font atlas lookup and font prewarm returning nil without mutation
- satchel settings and tooltip asset discovery returning empty lists
- resource lookups returning nil

Each added operation goes in its owning fake file. Do not stub XIUI module functions.

- [x] **Step 5: Run to GREEN**

```bash
"$MOONJIT_BIN" tests/startup/run.lua
```

Expected: both startup cases pass, and the initializer call set exactly matches the registered initializer set.

- [x] **Step 6: Deliberately remove initialization and observe RED**

Use `apply_patch` to temporarily replace the production line in `XIUI/XIUI.lua`:

```lua
uiModules.InitializeAll(gAdjustedSettings);
```

with no call. Run the startup suite. Expected: `registered initializer calls length` fails because the actual list is empty. Restore the exact production line with `apply_patch` and rerun to GREEN.

- [x] **Step 7: Commit callback execution support**

```bash
git add tests/startup
git commit -m "test: run XIUI startup initializers"
```

---

### Task 3: Prove Optional WinMM and Startup Side-Effect Safety

**Files:**

- Modify: `tests/startup/run.lua`
- Modify: `tests/startup/support/host.lua`
- Modify: `tests/startup/support/fake_filesystem.lua`
- Modify: `tests/startup/support/fake_packets.lua`

**Interfaces:**

- Consumes: environment logs from Tasks 1 and 2
- Produces: exact empty-list assertions for `winmm_loads`, `packets`, `filesystem_mutations`, and `settings_saves`

- [x] **Step 1: Add the unavailable-WinMM startup case**

```lua
{
    name = 'unavailable WinMM is not acquired during startup',
    run = function()
        host.with_environment({ winmm_available = false }, function(environment)
            environment.load_addon();
            environment.observe_initializers();
            environment.invoke_event('load', 'load_cb');
            expect_equal(#environment.logs.winmm_loads, 0, 'WinMM startup acquisitions');
        end);
    end,
},
```

Run once against current production and record GREEN as characterization evidence. This behavior was implemented in the already merged Ready Check fix, so its required RED is the deliberate mutation in Step 2.

- [x] **Step 2: Restore eager WinMM acquisition temporarily and observe RED**

Use `apply_patch` to add a temporary module-scope `ffi.load('winmm')` in `XIUI/modules/readycheck/sound.lua`. Run:

```bash
"$MOONJIT_BIN" tests/startup/run.lua
```

Expected: `real addon graph registers the load callback` fails with `winmm unavailable`, and the WinMM acquisition log contains one entry. Remove the temporary eager load and rerun to GREEN.

- [x] **Step 3: Add the no-side-effect startup case**

```lua
{
    name = 'startup emits no packets or persistent writes',
    run = function()
        host.with_environment({ winmm_available = false }, function(environment)
            environment.load_addon();
            environment.observe_initializers();
            environment.invoke_event('load', 'load_cb');
            expect_sequence(environment.logs.packets, {}, 'startup packets');
            expect_sequence(environment.logs.filesystem_mutations, {}, 'startup filesystem mutations');
            expect_sequence(environment.logs.settings_saves, {}, 'startup settings saves');
        end);
    end,
},
```

The virtual profile version is `1.8.4`, contains `Default` in both names and order, and exposes `Default.lua`. Therefore migration, profile creation, backup, and route repair are not valid startup writes for this fixture.

- [x] **Step 4: Run and classify any unexpected mutation**

```bash
"$MOONJIT_BIN" tests/startup/run.lua
```

Expected GREEN: exact empty logs. If production emits a write with the valid fixture, stop and report the exact operation and call stack because the design forbids silently accepting or fixing a new production defect.

- [x] **Step 5: Deliberately inject a packet and observe RED**

Use `apply_patch` to add this temporary line at the start of the registered load callback:

```lua
AshitaCore:GetPacketManager():AddOutgoingPacket(0x041, 'startup mutation');
```

Run the suite. Expected: `startup packets length: expected 0, got 1`. Remove the temporary line and rerun to GREEN.

- [x] **Step 6: Audit the startup behavior cases**

Map each retained case to its distinct mutation:

- entry import failure before callback registration
- removed `InitializeAll`
- eager WinMM acquisition
- startup packet or persistent mutation

Delete any case whose mutation is already caught by another case with equally strong assertions. Rerun each retained deliberate mutation after slimming the suite, restore production, and finish GREEN.

- [x] **Step 7: Commit the startup safety contracts**

```bash
git add tests/startup
git commit -m "test: enforce XIUI startup safety"
```

---

### Task 4: Add Scoped CI and Verify the Release Boundary

**Files:**

- Create: `.github/workflows/startup-smoke.yml`
- Modify: `docs/superpowers/plans/2026-08-22-startup-smoke.md` only to mark executed checkboxes

**Interfaces:**

- Consumes: `tests/startup/run.lua`
- Produces: GitHub check `Startup smoke`

- [x] **Step 1: Prove CI discovery is missing**

```bash
if rg -l --fixed-strings 'tests/startup/run.lua' .github/workflows; then
    printf 'Unexpected startup workflow already exists.\n' >&2
    exit 1
fi
printf 'Expected RED: no workflow runs tests/startup/run.lua.\n'
exit 1
```

Expected: exit 1 with the explicit expected-red message.

- [x] **Step 2: Add the startup workflow**

Create `.github/workflows/startup-smoke.yml`:

```yaml
name: Startup smoke

on:
  pull_request:
    paths:
      - 'XIUI/**/*.lua'
      - 'tests/startup/**'
      - '.github/workflows/startup-smoke.yml'

permissions:
  contents: read

jobs:
  test:
    name: Startup smoke
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    env:
      MOONJIT_COMMIT: a2a39ea7184f3c8cab9474c6e41f6541265fb362

    steps:
      - name: Checkout code
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          persist-credentials: false

      - name: Build Ashita-compatible MoonJIT
        run: |
          git init --quiet "${RUNNER_TEMP}/moonjit"
          git -C "${RUNNER_TEMP}/moonjit" remote add origin https://github.com/moonjit/moonjit.git
          git -C "${RUNNER_TEMP}/moonjit" fetch --quiet --depth=1 origin "${MOONJIT_COMMIT}"
          git -C "${RUNNER_TEMP}/moonjit" checkout --quiet --detach FETCH_HEAD
          make -C "${RUNNER_TEMP}/moonjit" -j2 XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT

      - name: Test XIUI startup
        run: >-
          "${RUNNER_TEMP}/moonjit/src/luajit" tests/startup/run.lua
```

- [x] **Step 3: Validate workflow discovery and YAML**

```bash
rg -n --fixed-strings 'tests/startup/run.lua' .github/workflows/startup-smoke.yml
ruby -e "require 'psych'; Psych.parse_file(ARGV.fetch(0))" .github/workflows/startup-smoke.yml
git diff --check
```

Expected: one workflow match, valid YAML, and no whitespace errors.

- [x] **Step 4: Run all focused test gates**

```bash
"$MOONJIT_BIN" tests/startup/run.lua
"$MOONJIT_BIN" tests/readycheck-audio/run.lua
tests/lua-syntax/check-changed-test.sh "$MOONJIT_BIN"
```

Expected: all startup cases pass, 10 Ready Check audio cases pass, and all changed-Lua selector cases pass.

- [x] **Step 5: Parse every Lua file changed from the integration base**

```bash
changed_count=0
while IFS= read -r -d '' lua_file; do
    XIUI_LUA_FILE="$lua_file" "$MOONJIT_BIN" -e \
        "local path = os.getenv('XIUI_LUA_FILE'); local chunk, err = loadfile(path, 't'); assert(chunk, err)"
    changed_count=$((changed_count + 1))
done < <(git diff --name-only -z --diff-filter=ACMRT beta-1.8.4-tanyrus...HEAD -- '*.lua')
printf 'MoonJIT parsed %d changed Lua files.\n' "$changed_count"
```

Expected: every new startup Lua file parses using the compatible profile.

- [x] **Step 6: Build and inspect both release layouts**

```bash
set -euo pipefail
package_root=$(mktemp -d /tmp/xiui-startup-package.XXXXXX)
mkdir -p "$package_root/regular" "$package_root/horizon"
cp -r XIUI "$package_root/regular/"
cp -r XIUI "$package_root/horizon/"
(cd "$package_root/regular" && zip -qr "$package_root/XIUI-test.zip" XIUI)
(cd "$package_root/horizon" && zip -qr "$package_root/XIUI-test-horizon.zip" XIUI)
for archive in "$package_root/XIUI-test.zip" "$package_root/XIUI-test-horizon.zip"; do
    listing=$(unzip -Z1 "$archive")
    test -n "$listing"
    if printf '%s\n' "$listing" | rg -q '(^|/)tests/'; then exit 1; fi
    if printf '%s\n' "$listing" | rg -qv '^XIUI/'; then exit 1; fi
done
```

Expected: both archives contain only `XIUI/` entries and no test path.

- [x] **Step 7: Run final branch checks**

```bash
git merge-base --is-ancestor beta-1.8.4-tanyrus HEAD
git diff --check beta-1.8.4-tanyrus...HEAD
git status --short
git diff --stat beta-1.8.4-tanyrus...HEAD
```

Expected: correct ancestry, no whitespace errors, and only the planned documentation, startup tests, and workflow changes.

- [x] **Step 8: Commit CI and plan execution state**

```bash
git add .github/workflows/startup-smoke.yml docs/superpowers/plans/2026-08-22-startup-smoke.md
git commit -m "ci: run XIUI startup smoke tests"
```

- [x] **Step 9: Hold the branch without a PR**

Report the branch, commits, exact test counts, deliberate mutation failures, packaging evidence, and any host behavior not covered. Do not push or open a pull request until the user explicitly requests it.

---

### Task 5: Close Review Findings at the Host Boundary

**Files:**

- Modify: `tests/startup/run.lua`
- Modify: `tests/startup/support/host.lua`
- Modify: `tests/startup/support/fake_ashita.lua`
- Modify: `tests/startup/support/fake_filesystem.lua`
- Modify: `tests/startup/support/fake_imgui.lua`
- Modify: `docs/superpowers/specs/2026-08-22-startup-smoke-design.md`
- Modify: `docs/superpowers/plans/2026-08-22-startup-smoke.md`

- [x] **Step 1: Add harness-boundary regressions and observe RED**

Add cases for unknown and traversal filesystem reads, unrecognized native signatures, semantic ImGui `None` flags, and failure-path process restoration. Before changing the fakes, observe the filesystem, signature, and ImGui cases fail for their intended reasons.

- [x] **Step 2: Isolate the virtual filesystem**

Allow virtual profile loads and relative `.lua` source paths below `XIUI/`. Reject dot-segment traversal and every other `loadfile`, `dofile`, and read-only `io.open` request instead of delegating to the test runner's filesystem.

- [x] **Step 3: Narrow the macro import signature exception**

Return a nonzero signature only to `XIUI/libs/ffxi/macros.lua` while the entry graph is importing. Record each scan and disable the exception immediately after entry loading so initializers and every other caller see neutral zero results.

- [x] **Step 4: Reduce and correct the ImGui surface**

Keep only constants evaluated during import and initialization. Use the ImGui enum values for those constants, preserve zero for `None`, use the corner bitmasks, name the shared font size, and remove the unused IO font-atlas surface.

- [x] **Step 5: Mutation-test protected cleanup**

Remove global, `package.preload`, `package.loaded`, and library-function restoration one at a time. Confirm that each deliberate mutation makes the retained failure-path case fail, restore the cleanup, and finish with all eight cases passing.

Keep the native FFI instance outside per-case cleanup. Confirm the original lifecycle aborts under an assertion-enabled MoonJIT build with `bad CTID`, then confirm repeated assertion-enabled and release-profile runs remain stable after the fix.

- [x] **Step 6: Re-run the complete verification set**

Run the startup and Ready Check suites, changed-file selector tests, all relevant Lua parse checks, workflow YAML validation, release archive inspection, whitespace checks, and the final diff review. Leave the review remediation uncommitted and do not push or open a pull request without a separate instruction.
