--[[
* Vana'Dial module for XIUI.
*
* Displays Vana'diel time, day element, moon phase, and zone weather.
* Data sources:
*   - Time / day / moon : pure Lua math from os.time() (no FFI / ashita.memory)
*   - Weather           : ashita.memory via FFXiMain.dll signature scan (same
*                         approach as meteorologist.lua, proven safe on HorizonXI).
*                         Packet 0x057 is used as a change trigger only — weather
*                         is NOT present in the packet bytes.
*                         On zone-in (0x000A) we defer a re-read by 2 real seconds
*                         so the game client has time to update the memory block.
*
* File layout:
*   init.lua    — lifecycle, weather memory reader, packet hooks (this file)
*   data.lua    — pure Lua constants and time/moon computation (no drawing)
*   display.lua — main window rendering (day columns, clock row, Fenrir tooltip)
*   popups.lua  — floating popup windows (timers, time-of-day, weather)
*   timers.lua  — transport/lunar schedule data and cache
]]--

require('common');
local display = require('modules.vanadial.display');
local popups  = require('modules.vanadial.popups');

local M = {};

-- ── Module state ──────────────────────────────────────────────────────────────
local hidden    = false;
local weatherId = 0;  -- 0 = none / unknown

-- Deferred zone-in weather read (avoids reading stale memory immediately after
-- the zone-in packet, same timing strategy as meteorologist.lua).
local pendingWeatherRead = false;
local pendingWeatherTime = 0;     -- os.time() deadline for the re-read

-- ── Weather memory reader ─────────────────────────────────────────────────────
-- Uses a FFXiMain.dll signature scan, same pattern as gamestate.lua / castcost.
-- Safety model (consistent with those siblings):
--   • Scan result is zero-checked before any read — zero means scan failed; we
--     skip the read entirely (no crash risk from reading address 0).
--   • Reads happen only on a resolved, DLL-relative address; this is NOT a raw
--     arbitrary pointer — the game process owns that memory page.
--   • pcall catches Lua-level errors from the find/read calls (e.g. bad API
--     args on a future Ashita version); it cannot catch C access violations, but
--     those cannot occur when the address is valid and non-zero.
-- THE SCAN IS CACHED: ashita.memory.find() walks the entire DLL (several ms).
-- We resolve the pointer once; subsequent reads are a single read_uint8 — free.
-- The DLL is not remapped on zone-in, so the pointer stays valid all session.
-- On any error the cache is cleared so the next call attempts a fresh scan.
--
-- Ashita 4.0/4.3 compatibility (matches the wrapper in libs/ffxi/macros.lua):
--   4.0: ashita.memory.find('FFXiMain.dll', 0, pattern, offset, scan)
--   4.3: ashita.memory.find(0, 0, pattern, offset, scan)
local WEATHER_SIG = '66A1????????663D????72';
local _weatherPtr = nil;   -- cached pointer to the single weather byte in game RAM

local function memory_find_compat(pattern, offset, scan)
    local result = ashita.memory.find('FFXiMain.dll', 0, pattern, offset, scan);
    if result ~= nil and result ~= 0 then return result end;
    return ashita.memory.find(0, 0, pattern, offset, scan);
end

local function ResolveWeatherPtr()
    -- Expensive: scans FFXiMain.dll. Call only when _weatherPtr is nil.
    local ok, result = pcall(function()
        local base = memory_find_compat(WEATHER_SIG, 0, 0);
        if not base or base == 0 then return nil end;
        local ptr = ashita.memory.read_uint32(base + 0x02);
        if not ptr or ptr == 0 then return nil end;
        return ptr;
    end);
    if ok and type(result) == 'number' and result ~= 0 then return result end;
    return nil;
end

local function GetWeatherSafe()
    local ok, result = pcall(function()
        -- Resolve pointer on first call (or after a cache invalidation).
        if not _weatherPtr then
            _weatherPtr = ResolveWeatherPtr();
        end
        if not _weatherPtr then return nil end;
        -- Cheap: single read from the already-known address.
        local w = ashita.memory.read_uint8(_weatherPtr);
        -- Sanity check: valid weather IDs are 0-19.  Out-of-range means the
        -- pointer drifted — clear cache so we re-scan on the next call.
        if type(w) ~= 'number' or w > 19 then
            _weatherPtr = nil;
            return nil;
        end
        return w;
    end);
    if ok and type(result) == 'number' then return result end;
    -- On any error clear the cache so the next frame attempts a fresh scan.
    _weatherPtr = nil;
    return nil;
end

-- ── Module lifecycle ──────────────────────────────────────────────────────────

function M.Initialize(settings)
    display.Initialize();
    local w = GetWeatherSafe();
    if w ~= nil then weatherId = w; end
end

function M.DrawWindow(settings)
    if hidden then return; end

    -- Deferred weather re-read after zone-in (2 s delay, mirrors meteorologist).
    if pendingWeatherRead and os.time() >= pendingWeatherTime then
        pendingWeatherRead = false;
        local w = GetWeatherSafe();
        if w ~= nil then weatherId = w; end
    end

    display.DrawWindow(weatherId);
end

function M.UpdateVisuals(settings)
    display.Reset();
end

function M.SetHidden(h)
    hidden = h;
end

-- Opens the timers popup to a specific section.
-- A second call with the same key closes the popup.
-- Keys: 'vdships', 'vdboats', 'vdrse', 'vdlunar'
function M.OpenTimersSection(key)
    popups.OpenTimersSection(key);
end

function M.Cleanup()
    weatherId = 0;
    pendingWeatherRead = false;
    _weatherPtr = nil;
    display.Cleanup();
end

-- ── Packet hooks ──────────────────────────────────────────────────────────────
-- Wired from XIUI.lua packet_in handler.

function M.HandlePacketIn(e)
    -- Zone change: clear stale weather and schedule a re-read in 2 real seconds
    -- so memory has time to reflect the new zone's conditions.
    if e.id == 0x000A then
        weatherId         = 0;
        pendingWeatherRead = true;
        pendingWeatherTime = os.time() + 2;
        return;
    end

    -- Weather change trigger (0x057).  The packet is a notification only — the
    -- weather ID is NOT in the packet bytes.  Read from memory after it fires.
    -- Schedule a deferred read in all cases: the memory may not be updated yet
    -- when the packet fires (the game clears old weather before writing new),
    -- so an immediate read can return 0. A 1 s retry guarantees we catch it.
    if e.id == 0x057 then
        local w = GetWeatherSafe();
        if w ~= nil and w > 0 then
            weatherId = w;
        end
        -- Always also schedule a follow-up read in case memory was mid-update.
        pendingWeatherRead = true;
        pendingWeatherTime = os.time() + 1;
    end
end

return M;
