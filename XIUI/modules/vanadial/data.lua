--[[
* Vana'Dial data — pure Lua constants and time computation for XIUI.
*
* No ImGui, no drawing, no ashita.memory.
* All consumers (display, popups) require this file.
]]--

require('common');
local bit = require('bit');
local ffi = require('ffi');

-- High-precision wall-clock milliseconds via Windows API.
-- os.clock() is CPU time in LuaJIT (doesn't advance while the game sleeps),
-- so we use GetTickCount64 for sub-second interpolation instead.
pcall(function() ffi.cdef[[ unsigned long long __stdcall GetTickCount64(void); ]]; end);
local function _doGetTickCount64()
    return tonumber(ffi.C.GetTickCount64());
end
local function GetTickMs()
    local ok, v = pcall(_doGetTickCount64);
    return (ok and v) or nil;
end

local M = {};

-- ── Vana'diel time constants ───────────────────────────────────────────────────
-- Vana'diel time runs at 25x real-world speed.
-- 1 VD day  = 3456 real seconds  (57.6 minutes)
-- 1 VD hour = 144  real seconds
-- 1 VD min  = 2.4  real seconds
-- Moon cycle = 84 VD days; day 0 = new moon, day 42 = full moon.
M.VANA_EPOCH     = 1009810800; -- Canonical FFXI Vana'diel epoch (Unix ts). The game's own
                               -- clock uses this exact value, so Vana'Dial tracks it in
                               -- lockstep (both read the same system clock) and never drifts.
                               -- Do NOT hand-tune this to fractional offsets: doing so only
                               -- lines up while your PC clock is momentarily off, then desyncs
                               -- again once Windows time service corrects the clock.
M.VD_DAY_SEC     = 3456;
M.VD_HOUR_SEC    = 144;
M.VD_MIN_F       = 2.4;
M.VD_MOON_DAYS   = 84;
-- VT day 0 does not coincide with moon-cycle day 0. Calibrated against live data:
-- at a known timestamp the raw vtDays%84 is off by +4, so subtract 4 (add 80) to align.
M.VD_MOON_OFFSET = 80;

-- ── Time math ─────────────────────────────────────────────────────────────────

-- Vana'diel time advances in lockstep with INTEGER Earth seconds. The game
-- increments the displayed VT minute only on whole-second boundaries — the
-- 2-2-3-2-3 Earth-second tick pattern that averages exactly 2.4 s per VT
-- minute (25 VT days per Earth day). os.time() is already an integer, so
-- subtracting the epoch here reproduces that stepping exactly and rolls the
-- minute at the same instant as the in-game clock.
--
-- Do NOT re-introduce sub-second interpolation here: dividing a fractional
-- Earth-second by 2.4 crosses the VT-minute boundary early (at 2.4/4.8/7.2/
-- 9.6 s) instead of on the integer second the game uses, making the clock read
-- up to a full VT minute AHEAD. That oscillating error is unfixable by epoch
-- tuning, which is what caused the recurring desync.
function M.GetRawTime()
    return os.time() - M.VANA_EPOCH;
end

-- Milliseconds since boot (Windows GetTickCount64). For display-only smoothing;
-- do not use for VT clock math (see GetRawTime comment).
function M.GetTickMs()
    return GetTickMs();
end

function M.CalcMoonPercent(moonDay)
    if moonDay <= 42 then
        return math.floor(moonDay / 42 * 100 + 0.5);
    else
        return math.floor((M.VD_MOON_DAYS - moonDay) / 42 * 100 + 0.5);
    end
end

-- Map moonDay (0-83) to logical phase index (0-11).
-- New Moon wraps: moonDays 80-83 and 0-2 → 0.
-- All other phases are 7-day segments from moonDay 3 onward.
function M.GetMoonPhaseRaw(moonDay)
    if moonDay >= 80 or moonDay <= 2 then
        return 0;
    else
        return math.floor((moonDay - 3) / 7) + 1;
    end
end

-- ── Element tables ─────────────────────────────────────────────────────────────
-- Weekday index → element name (matches assets/VanaDial/elements/*.png)
-- Indices 0-7: the eight FFXI elements.
-- Indices 8-11: non-elemental weather icons (weather popup only).
M.ELEMENT_NAMES = {
    [0]='Fire',  [1]='Earth',   [2]='Water', [3]='Wind',
    [4]='Ice',   [5]='Thunder', [6]='Light', [7]='Darkness',
    [8]='Clear', [9]='Sunshine', [10]='Cloudy', [11]='Foggy',
};

-- Weekday index → colorCustomization key
M.ELEM_KEYS = {
    [0]='elementFire', [1]='elementEarth',     [2]='elementWater', [3]='elementWind',
    [4]='elementIce',  [5]='elementLightning', [6]='elementLight', [7]='elementDark',
};

-- Weekday index (0-7) → Vana'diel day name (element order).
M.WEEKDAY_NAMES = {
    [0]='Firesday', [1]='Earthsday', [2]='Watersday', [3]='Windsday',
    [4]='Iceday',   [5]='Lightningday', [6]='Lightsday', [7]='Darksday',
};

function M.GetTodName(vtHour)
    if vtHour >= 20 or vtHour < 4 then
        return 'Dead of Night';
    end
    if vtHour >= 6 and vtHour < 18 then
        return 'Day';
    end
    return 'Night';
end

-- Which element each weekday DEFEATS (weakness badge)
-- Chain: Water > Fire > Ice > Wind > Earth > Thunder > Water; Light <-> Dark
M.ELEMENT_DEFEATS = {
    [0]=4, -- Fire    defeats Ice
    [1]=5, -- Earth   defeats Lightning
    [2]=0, -- Water   defeats Fire
    [3]=1, -- Wind    defeats Earth
    [4]=3, -- Ice     defeats Wind
    [5]=2, -- Lightning defeats Water
    [6]=7, -- Light   defeats Dark
    [7]=6, -- Dark    defeats Light
};

-- Light group (black outline + white pill). Dark group gets white + dark pill.
M.LIGHT_GROUP = { [0]=true, [3]=true, [5]=true, [6]=true };

-- ── Weather tables ─────────────────────────────────────────────────────────────
-- Weather IDs 4-19 are elemental; odd = double strength.
-- Map to weekday element index (0-7).
M.WEATHER_TO_ELEMENT = {
    [0]=8,  [1]=9,   -- Clear / Sunshine          (non-elemental)
    [2]=10, [3]=11,  -- Cloudy / Fog              (non-elemental)
    [4]=0,  [5]=0,   -- Hot Spell / Heat Wave     (Fire)
    [6]=2,  [7]=2,   -- Rain / Squall             (Water)
    [8]=1,  [9]=1,   -- Dust Storm / Sandstorm    (Earth)
    [10]=3, [11]=3,  -- Wind / Gales              (Wind)
    [12]=4, [13]=4,  -- Snow / Blizzard           (Ice)
    [14]=5, [15]=5,  -- Thunder / Thunderstorm    (Lightning)
    [16]=6, [17]=6,  -- Auroras / Stellar Glare   (Light)
    [18]=7, [19]=7,  -- Gloom / Darkness          (Dark)
};

M.WEATHER_NAMES = {
    [0]='Clear',      [1]='Sunshine',
    [2]='Cloudy',     [3]='Fog',
    [4]='Hot Spell',  [5]='Heat Wave',
    [6]='Rain',       [7]='Squall',
    [8]='Dust Storm', [9]='Sandstorm',
    [10]='Wind',      [11]='Gales',
    [12]='Snow',      [13]='Blizzard',
    [14]='Thunder',   [15]='Thunderstorm',
    [16]='Auroras',   [17]='Stellar Glare',
    [18]='Gloom',     [19]='Darkness',
};

-- ── Moon phase data ────────────────────────────────────────────────────────────
-- Maps phase index (0-11) to icon file number (currently 1:1).
M.PHASE_ICON_MAP = {
    [0]=0, [1]=1,  [2]=2,  [3]=3,  [4]=4,  [5]=5,
    [6]=6, [7]=7,  [8]=8,  [9]=9,  [10]=10,[11]=11,
};

-- Phase 0=New Moon, 6=Full Moon; 1-5 waxing, 7-11 waning
M.PHASE_NAMES = {
    [0]='New Moon',        [1]='Waxing Crescent', [2]='Waxing Crescent',
    [3]='First Quarter',   [4]='Waxing Gibbous',  [5]='Waxing Gibbous',
    [6]='Full Moon',       [7]='Waning Gibbous',  [8]='Waning Gibbous',
    [9]='Last Quarter',    [10]='Waning Crescent', [11]='Waning Crescent',
};

-- ── Fenrir / Selene Blood Pact data (indexed by phase 0-11) ───────────────────
-- Lunar Cry: {acc_penalty, eva_penalty}
M.LUNAR_CRY = {
    [0]={-1,-31}, [1]={-6,-26},  [2]={-11,-21}, [3]={-16,-16},
    [4]={-21,-11},[5]={-26,-6},  [6]={-31,-1},  [7]={-26,-6},
    [8]={-21,-11},[9]={-16,-16}, [10]={-11,-21},[11]={-6,-26},
};

-- Ecliptic Howl: {acc_bonus, eva_bonus}
M.ECLIPTIC_HOWL = {
    [0]={1,25},  [1]={5,21},  [2]={9,17},  [3]={13,13},
    [4]={17,9},  [5]={21,5},  [6]={25,1},  [7]={21,5},
    [8]={17,9},  [9]={13,13}, [10]={9,17}, [11]={5,21},
};

-- Ecliptic Growl: {STR/DEX/VIT, AGI/INT/MND/CHR}
M.ECLIPTIC_GROWL = {
    [0]={1,7},  [1]={2,6},  [2]={3,5},  [3]={4,4},
    [4]={5,3},  [5]={6,2},  [6]={7,1},  [7]={6,2},
    [8]={5,3},  [9]={4,4},  [10]={3,5}, [11]={2,6},
};

-- Selene's Bow: {Ranged Accuracy bonus, Ranged Attack bonus}
-- Full Moon = best RAcc; New Moon = best RAtk
M.SELENE_BOW = {
    [0]={5,25},  [1]={10,20}, [2]={10,20}, [3]={15,15},
    [4]={20,10}, [5]={20,10}, [6]={25,5},  [7]={20,10},
    [8]={20,10}, [9]={15,15}, [10]={10,20},[11]={10,20},
};

return M;
