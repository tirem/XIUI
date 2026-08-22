# XIUI Startup Smoke Harness Design

## Goal

Prove that the real `XIUI/XIUI.lua` entry point can load its normal dependency graph, register its startup callback, and complete that callback without FFXI or a live Ashita host. The harness must also prove that unavailable optional WinMM audio cannot abort startup.

This completes the remaining Phase 0 test boundary before destructive Treasure actions are changed in Phase 1.

## Scope

The branch is `tanyrus/startup-smoke`, based on `beta-1.8.4-tanyrus` at `9153145`.

The change adds a reusable test harness under `tests/startup/` and a path-scoped workflow. Production source is not expected to change. If the real startup graph exposes another production defect, implementation stops so that defect can be reviewed before it is changed.

The harness does not emulate FFXI gameplay, render a frame, validate native ABI behavior, or replace later Windows, Wine, and Proton validation.

## Approach

The harness loads the real addon entry point and all XIUI-owned modules. It replaces only external host boundaries through globals and `package.preload`:

- Ashita event registration and managers
- ImGui functions, constants, and pointer-like values
- D3D8 device and texture operations
- settings persistence
- filesystem operations
- time
- packet injection
- WinMM acquisition
- Ashita `common` and `chat` helpers

Each fake exposes an explicit contract and records observable calls. Unknown host methods fail with a useful name instead of silently returning a generic value. This makes the harness grow only when the real startup path demonstrates a required host operation.

A shallow module-stub approach was rejected because it would not detect module import failures. Launching FFXI was rejected because this gate must run deterministically in CI.

## Files

Create:

- `tests/startup/run.lua`
- `tests/startup/support/host.lua`
- `tests/startup/support/fake_ashita.lua`
- `tests/startup/support/fake_common.lua`
- `tests/startup/support/fake_imgui.lua`
- `tests/startup/support/fake_d3d8.lua`
- `tests/startup/support/fake_filesystem.lua`
- `tests/startup/support/fake_clock.lua`
- `tests/startup/support/fake_packets.lua`
- `.github/workflows/startup-smoke.yml`

Production files under `XIUI/` change only if the test reveals a separately reviewed startup defect.

## Harness Contract

`support.host` owns isolation and exposes:

```lua
local host = require('support.host')

host.with_environment(options, function(environment)
    environment.load_addon()
    environment.invoke_event('load')
end)
```

The environment records:

- registered event names and callback keys
- invoked events
- WinMM load attempts
- packet injections
- filesystem writes, removes, and renames
- settings saves
- registered module initializer calls
- native signature scans and whether the narrow macro-import exception matched
- host-manager calls needed to diagnose a startup failure

`with_environment` snapshots and restores modified globals, `package.path`, `package.preload`, and `package.loaded`. Every XIUI module loaded by a case is removed afterward so test order cannot provide hidden state.

The fake filesystem presents an existing valid Default profile in memory. `loadfile` accepts only the virtual profile files and relative `.lua` source paths below `XIUI/` without dot segments; `dofile` follows the same rule, and `io.open` rejects every read. Writes, removes, and renames are recorded rather than touching the repository or user files. Unknown and traversal paths never fall through to the host filesystem.

The FFI wrapper delegates declarations, allocation, casts, and size queries to MoonJIT's real FFI implementation. Native FFI is loaded once before per-case package snapshots so cleanup restores the same C-type state instead of reinitializing it while cdata remains alive. Only `ffi.load('winmm')` is intercepted. An unavailable WinMM option raises the same kind of acquisition error as the native loader and records the attempt.

The fake ImGui and D3D8 surfaces use explicit functions and values required by import and initialization. ImGui `None` constants are zero, corner flags use their bitmask values, and only constants evaluated by startup are installed. The fakes do not use a catch-all metatable that could hide a misspelled or newly required host API.

Most native signature scans return zero. `libs/ffxi/macros.lua` is the sole exception during entry loading because that imported library rejects missing function pointers at module scope. The exception is caller-scoped, is disabled immediately after `XIUI/XIUI.lua` returns, and never enables signature matches for initializers or other modules.

After entry loading registers the real modules, the harness reads `core.moduleregistry.GetAll()`. It wraps each advertised `Initialize` function with a recorder that calls the original function and restores every wrapper during cleanup. The expected initializer set is derived from the live registry, not duplicated in test data.

## Execution Flow

```text
reset Lua state
  -> install deterministic host boundaries
  -> load real XIUI/XIUI.lua
  -> inspect captured event registry
  -> invoke captured load callback
  -> assert startup side effects
  -> restore globals and package state
```

Each assertion runs inside a fresh environment. Cleanup runs even when loading or callback invocation fails.

## Tests

`tests/startup/run.lua` reports exact case names and accumulates failures using the same small runner style as `tests/readycheck-audio/run.lua`.

### `real addon graph registers the load callback`

Load `XIUI/XIUI.lua` with the strict fake host. Assert that loading returns normally and that the event registry contains the `load` callback under `load_cb`.

Production mutation: make any eager import fail. Expected result: the entry point fails before callback registration.

### `registered load callback completes without a live game host`

Load the addon and invoke the captured `load` callback. Provide neutral party, entity, inventory, resource, D3D, and settings state. Assert the callback returns normally and the host records its invocation.

Compare the sorted set of observed initializer calls with the sorted set of registry entries that advertised `Initialize` before callback invocation. This proves the orchestration reached every registered initializer without hardcoding the registry in the test.

Production mutation: remove or break the `InitializeAll` call. Expected result: the initializer-set assertion fails.

### `unavailable WinMM is not acquired during startup`

Configure WinMM acquisition to fail, then load the entry point and invoke `load`. Assert both operations complete and the WinMM attempt count is zero.

Production mutation: restore eager WinMM acquisition in Ready Check sound. Expected result: entry loading fails and the attempt count becomes one.

### `startup emits no packets or persistent writes`

Load the entry point and invoke `load` against an already valid in-memory profile. Assert exact empty packet and mutation logs.

Production mutation: inject a packet or persistent write into startup. Expected result: exact log equality fails.

### `unknown filesystem reads stay inside the virtual host`

Attempt `io.open`, `loadfile`, and `dofile` against a real repository test file that is outside `XIUI/`. Assert that none can read it.

Harness mutation: delegate any unknown read to the original host function. Expected result: the corresponding read succeeds and the assertion fails.

### `neutral host rejects unrecognized native signatures`

Call `ashita.memory.find` from the test runner before addon loading. Assert that the neutral host returns zero.

Harness mutation: return a nonzero address for every signature. Expected result: the unrecognized scan assertion fails.

### `neutral ImGui constants preserve None semantics`

Assert that child and corner `None` flags are zero inside the installed host.

Harness mutation: assign arbitrary sequential values to ImGui constants. Expected result: the `None` assertions fail.

### `failing cases restore process state`

Force a callback failure after replacing a global, `package.loaded`, `package.preload`, and `io.open`. Assert that the original failure is propagated and every value is restored.

Harness mutation: remove any cleanup boundary. Expected result: its identity assertion fails, while removing `package.loaded` cleanup also contaminates later startup cases.

## Failure Handling

Missing host operations and production tracebacks are preserved. Runner case names identify whether the failure occurred during entry loading, callback execution, or a harness-boundary check. The runner restores global and package state after every failure and continues to report remaining cases.

The harness must not catch or convert production errors into passes. Only test cleanup is protected.

## CI

`.github/workflows/startup-smoke.yml` runs for pull requests that change:

- `XIUI/**/*.lua`
- `tests/startup/**`
- `.github/workflows/startup-smoke.yml`

Every XIUI Lua module is eagerly reachable from `modules.init`, so any XIUI Lua change can affect startup. Asset, documentation, and unrelated workflow changes do not run the job.

The job:

- has `contents: read` permission
- runs on `ubuntu-24.04`
- has a five-minute timeout
- checks out without persisted credentials
- builds MoonJIT commit `a2a39ea7184f3c8cab9474c6e41f6541265fb362`
- enables `LUAJIT_ENABLE_LUA52COMPAT`
- uses `RUNNER_TEMP` only inside runner steps
- runs `tests/startup/run.lua` directly

The existing changed-Lua syntax workflow remains the cheapest syntax gate and continues to compare the PR head with GitHub's actual base SHA.

## Test-First Sequence

1. Add the smallest runner and strict host boundary needed to load the real entry point.
2. Run the first case and record its expected missing-host failure.
3. Add one explicit fake operation at a time until entry loading reaches callback registration.
4. Add callback execution and record each missing-host failure before extending the fake contract.
5. Add WinMM and side-effect assertions.
6. Restore eager WinMM acquisition temporarily and observe the WinMM regression fail.
7. Restore lazy acquisition and observe the pass.
8. Introduce one startup packet or write in the fake boundary, observe the side-effect regression fail, then restore it.
9. Audit all behavior and harness-boundary cases and remove any case that does not catch a distinct mutation.

## Verification

Before handoff:

- run the startup suite under pinned compatible MoonJIT
- run the Ready Check audio suite
- run the changed-Lua selector tests
- parse every changed Lua file
- validate workflow YAML syntax
- run `git diff --check`
- build both release ZIP layouts and prove every entry is under `XIUI/`
- confirm `tests/startup/` is absent from both ZIPs
- confirm the branch is based on `beta-1.8.4-tanyrus`

No FFXI, Windows, Wine, or Proton runtime claim is made from this harness.

## Acceptance Criteria

- The real addon entry and real XIUI module graph load under the fake host.
- The registered `load` callback completes with neutral host state.
- Missing WinMM cannot abort entry loading or callback execution.
- Startup sends no packets and performs no persistent mutations against an already valid profile.
- Test state is isolated between cases.
- CI is path-scoped and completes within five minutes.
- Tests remain outside the release payload.
- The deliberate eager-WinMM and side-effect mutations are observed failing before handoff.
