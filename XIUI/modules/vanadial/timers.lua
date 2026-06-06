--[[
* Vana'Dial timer schedule data and per-real-second/minute cache.
*
* No rendering logic.  All public data (M.airships, M.boats, M.rse, M.lunar)
* are pre-built arrays of plain Lua tables that the popup render loop can
* iterate with zero computation and zero per-frame allocation.
*
* Optimisation contract
*   • Call M.Update(osNow, vtMinuteOfDay, vtDay, moonDay) from the timers popup draw
*     path only (skipped when the panel is closed).
*   • Airships + boats rebuild at most once per real second.
*   • RSE + lunar rebuild at most once per real minute.
]]--

require('common');
local bit = require('bit');

local M = {};

-- ── Constants (mirror ui.lua) ────────────────────────────────────────────────
local VANA_EPOCH   = 1009810800;  -- Unix ts of Vana'diel year-0 epoch
local VD_DAY_SEC   = 3456;        -- real seconds per VT day  (57.6 min)
local VD_MIN_F     = 2.4;         -- real seconds per VT minute
local VD_MOON_DAYS = 84;

-- Ferry routes: 8 VT-hour departure cycle (480 VT). Boarding + transit lengths vary by route.
-- Standard (Selbina<>Mhaura, Mhaura<>Whitegate): 80 VT board, 400 VT sail (Earth 3m12s / 16m).
-- Nashmau<>Whitegate: 180 VT board (3 VT h), 300 VT sail (Earth 7m12s / 12m).
local FERRY_CYCLE_VT        = 480;
local FERRY_BOARD_VT_STD    = 80;
local FERRY_TRANSIT_VT_STD  = 400;
local FERRY_BOARD_VT_NASH   = 180;
local FERRY_TRANSIT_VT_NASH = 300;

-- Yellow "soon" threshold: 5 real minutes
local SOON_SECS = 300;

-- Nation / city label colours (float4, RGB from user spec — brightened for dark bg)
local C_CITY = {
    -- Airships
    Bastok = {0.33,  0.53,  0.93,  1.0},  -- bright blue
    Sandy  = {0.90,  0.25,  0.30,  1.0},  -- bright red
    Windy  = {0.22,  0.80,  0.42,  1.0},  -- bright green
    Jeuno  = {1.0,   1.0,   1.0,   1.0},  -- white
    Kazham = {1.0,   0.82,  0.10,  1.0},  -- vivid yellow
    -- Boats (Selbina / Mhaura)
    Selbina        = {0.98, 0.95, 0.55, 1.0},  -- light yellow
    Mhaura         = {1.00, 0.72, 0.76, 1.0},  -- light pink
    Whitegate      = {0.94, 0.92, 0.86, 1.0},  -- off-white
    Nashmau        = {0.35, 0.88, 0.78, 1.0},  -- teal (Al Zahbi / Nashmau)
    -- Bibiki Manaclipper
    Bibiki          = {1.00, 0.52, 0.52, 1.0},  -- light red
    Purgonorgo      = {0.52, 0.78, 1.00, 1.0},  -- light blue
    ['Purgo. Isle'] = {0.52, 0.78, 1.00, 1.0},  -- light blue (legacy alias)
    ['Mal. Reef']   = {0.90, 0.55, 0.75, 1.0},  -- coral pink (Maliyakaleya Reef)
    ['Dhalmel Rock']= {0.85, 0.65, 0.40, 1.0},  -- sandy orange (Dhalmel Rock Tour)
    -- Carpenters' Landing
    North          = {0.62, 0.76, 0.55, 1.0},  -- sage green  (North Landing)
    Central        = {0.52, 0.88, 0.52, 1.0},  -- light green (Central Landing)
    EMFEA          = {0.40, 0.80, 0.60, 1.0},  -- light green (Central EMFEA)
    South          = {0.82, 0.67, 0.47, 1.0},  -- light brown (South Landing)
    Newtpool       = {0.75, 0.58, 0.38, 1.0},  -- light brown (South Newtpool)
    ['Newtpool 2'] = {0.75, 0.58, 0.38, 1.0},
    OOS            = {0.90, 0.30, 0.30, 1.0},  -- red
    ['OOS 2']      = {0.90, 0.30, 0.30, 1.0},
};
local C_CITY_DEFAULT = {0.957, 0.855, 0.592, 1.0};  -- XIUI gold fallback

local function CityColor(name)
    if not name then return C_CITY_DEFAULT end;
    return C_CITY[name] or C_CITY_DEFAULT;
end



-- ── Status colours (ARGB hex) ─────────────────────────────────────────────────
local C_BOARDING = 0xFF44EE88;   -- green
local C_SOON     = 0xFFFFCC44;   -- yellow
local C_WAITING  = 0xFFCCCCCC;   -- light grey

-- Pre-allocated float4 colour tables for route rows (reused, never mutated).
-- Eliminates a ToF4() table allocation on every makeRow/MakeCLRouteRow call per second.
local CF4_BOARDING = {0.267, 0.933, 0.533, 1.0};  -- 0xFF44EE88 boarding green
local CF4_AWAITING = {0.500, 0.980, 0.720, 1.0};  -- 0xFF80FA88 lighter green (awaiting arrival)
local CF4_SOON     = {1.0,   0.800, 0.267, 1.0};  -- 0xFFFFCC44 departure soon
local CF4_WAITING  = {0.800, 0.800, 0.800, 1.0};  -- 0xFFCCCCCC waiting grey
local CF4_CL_TRANS = {0.510, 0.392, 0.055, 1.0};  -- 0xFF82640E CL/Manaclipper in-transit
local CF4_CL_SVC   = {0.400, 0.733, 0.400, 1.0};  -- 0xFF66BB66 serviced soon
local CF4_CL_OOS   = {0.800, 0.200, 0.200, 1.0};  -- 0xFFCC3333 out of service

-- ── Schedule tables (VT minutes from midnight, 0-1439) ─────────────────────
-- Store DEPARTURE TIMES only. The state machine derives everything else from
-- two universal constants confirmed by Pyogenes live data:
--   BOARD_VT  = 60 VT min  → boarding window = 2m 24s real  (dep - 60 to dep)
--   ROUND_VT  = 300 VT min → same-port round trip = 12m 00s real (always, all routes)
-- Arrival times in the wiki are rounded by the in-game 2-2-3-2-3 tick pattern
-- and can be off by up to 12 VT min; departure times are consistently accurate.

-- Bastok <> Jeuno
-- Calibrated from live Pyogenes data: all 8 routes spaced exactly 180 VT min apart.
-- (Wiki displayed-clock times were 2-4 VT min off due to the 2-2-3-2-3 tick rounding.)
local DEP_BASTOK  = {70,  430,  790, 1150};  -- 01:10  07:10  13:10  19:10
local DEP_JEUNOBD = {250, 610,  970, 1330};  -- 04:10  10:10  16:10  22:10

-- Sandoria <> Jeuno
local DEP_SANDY   = {250, 610,  970, 1330};  -- 04:10  10:10  16:10  22:10
local DEP_JEUNOSD = {430, 790, 1150,   70};  -- 07:10  13:10  19:10  01:10

-- Windurst <> Jeuno
local DEP_WINDY   = {345, 705, 1065, 1425};  -- 05:45  11:45  17:45  23:45
local DEP_JEUNOWD = {520, 880, 1240,  160};  -- 08:40  14:40  20:40  02:40

-- Kazham <> Jeuno
local DEP_KAZHAM  = {160, 520,  880, 1240};  -- 02:40  08:40  14:40  20:40
local DEP_JEUNOKD = {335, 695, 1055, 1415};  -- 05:35  11:35  17:35  23:35

-- ── Ferry schedules (departure VT min only; boarding/transit from FERRY_* constants) ──
local DEP_SELBINA_SM     = {  0, 480,  960};  -- 00:00  08:00  16:00
local DEP_MHAURA_SM      = {  0, 480,  960};
-- Mhaura <> Whitegate: dep 04/12/20:00 → arr 10:40/18:40/02:40 (std 80+400)
local DEP_MHAURA_WG      = {240, 720, 1200};
-- Whitegate <> Nashmau: dep 00/08/16:00 → arr 05:00/13:00/21:00 (nash 180+300)
local DEP_WG_NASHMAU     = {  0, 480,  960};

-- ── Bibiki Bay Manaclipper ───────────────────────────────────────────────────
-- Four named routes share the same dock at Bibiki Bay (Sunset Docks).
-- Reuses the same timed-route state machine as CL: IN-TRANSIT → BOARDING →
-- Serviced Soon → Out of Service.  All times are Vana'diel minutes (H*60+M).
--
-- Source: FFXI wiki Manaclipper/Schedule page (image confirmed by user).
--   Bibiki→Purgo  : B 4:50/16:50  D 5:30/17:30  A 8:30/20:30
--   Purgo→Bibiki  : B 8:40/20:30  D 9:15/21:15  A 12:10/0:10 (run-B wraps midnight)
--   Mal. Reef Tour: B 12:10       D 12:50        A 16:50
--   Dhalmel Rock  : B 0:10        D 0:50         A 4:50

local BIBIKI_ROUTES = {
    {   -- Bibiki Bay → Purgonorgo Isle  (2 runs / VT day)
        fromName='Bibiki',     fromColor={1.00, 0.52, 0.52, 1.0},
        toName  ='Purgonorgo', toColor  ={0.52, 0.78, 1.00, 1.0},
        routeVia=nil,
        schedule={
            {boarding=290,  dep=330,  arr=510 },  -- 4:50 / 5:30  / 8:30
            {boarding=1010, dep=1050, arr=1230},  -- 16:50 / 17:30 / 20:30
        },
    },
    {   -- Purgonorgo Isle → Bibiki Bay  (2 runs / VT day; run-B arr wraps midnight)
        fromName='Purgonorgo', fromColor={0.52, 0.78, 1.00, 1.0},
        toName  ='Bibiki',     toColor  ={1.00, 0.52, 0.52, 1.0},
        routeVia=nil,
        schedule={
            {boarding=520,  dep=555,  arr=730},   -- 8:40  / 9:15  / 12:10
            {boarding=1230, dep=1275, arr=10 },   -- 20:30 / 21:15 / 0:10 (wraps)
        },
    },
    {   -- Bibiki Bay → Maliyakaleya Reef (1 run / VT day)
        fromName='Bibiki',      fromColor={1.00, 0.52, 0.52, 1.0},
        toName  ='Mal. Reef',   toColor  ={0.90, 0.55, 0.75, 1.0},
        city3   ='Bibiki',      city3Color={1.00, 0.52, 0.52, 1.0},
        schedule={
            {boarding=730, dep=770, arr=1010},    -- 12:10 / 12:50 / 16:50
        },
    },
    {   -- Bibiki Bay → Dhalmel Rock (1 run / VT day)
        fromName='Bibiki',       fromColor={1.00, 0.52, 0.52, 1.0},
        toName  ='Dhalmel Rock', toColor  ={0.85, 0.65, 0.40, 1.0},
        city3   ='Bibiki',       city3Color={1.00, 0.52, 0.52, 1.0},
        schedule={
            {boarding=10, dep=50, arr=290},       -- 0:10 / 0:50 / 4:50
        },
    },
};

-- ── The Carpenters' Landing Barge (Phanauet Channel) ────────────────────────
-- Four routes run in a strict looping circuit.  Status is ALWAYS one of:
--   IN-TRANSIT    : vtMin in [dep, arr)      — barge en route to destination
--   BOARDING      : vtMin in [boarding, dep) — you can board right now
--   Serviced Soon : vtMin in [boarding-CL_SOON_VT, boarding) — within 10 Earth min of boarding
--   OOS           : all other times          — barge is elsewhere in the circuit
-- Countdown: to arrival (transit), departure (boarding), boarding start (soon/OOS).

local CL_SOON_VT = 250;  -- VT minutes before boarding = 10 Earth minutes (250 × 2.4 s = 600 s)

local CL_ROUTES = {
    {   -- South Landing → Central Landing  (via Emfea Waterway, once per VT day)
        fromName='South',   fromColor={0.82,0.67,0.47,1.0},
        toName  ='Central', toColor  ={0.52,0.88,0.52,1.0},
        routeVia='via Emfea',
        schedule={{boarding=15,  dep=50,   arr=275}},
    },
    {   -- Central Landing → South Landing  (via Newtpool, twice per VT day)
        fromName='Central', fromColor={0.52,0.88,0.52,1.0},
        toName  ='South',   toColor  ={0.82,0.67,0.47,1.0},
        routeVia='via Newtpool',
        schedule={
            {boarding=275,  dep=310,  arr=535},
            {boarding=1155, dep=1190, arr=1415},
        },
    },
    {   -- South Landing → North Landing  (once per VT day)
        fromName='South', fromColor={0.82,0.67,0.47,1.0},
        toName  ='North', toColor  ={0.62,0.76,0.55,1.0},
        routeVia=nil,
        schedule={{boarding=575, dep=610, arr=960}},
    },
    {   -- North Landing → Central Landing  (once per VT day)
        fromName='North',   fromColor={0.62,0.76,0.55,1.0},
        toName  ='Central', toColor  ={0.52,0.88,0.52,1.0},
        routeVia=nil,
        schedule={{boarding=1005, dep=1045, arr=1155}},
    },
};

-- True when vtMin is inside the half-open VT interval [a, b) with midnight-wrap support.
local function InVtInterval(vtMin, a, b)
    if a == b then return false end
    if a < b   then return vtMin >= a and vtMin < b end
    return vtMin >= a or vtMin < b;   -- interval crosses midnight
end

-- Real seconds from osNow until targetVtMin on the nearest future VT day.
local function SecsToVtMin(targetVtMin, vtMin, vtDay, osNow)
    local diff = targetVtMin - vtMin;
    local wrap = (diff < 0);
    if wrap then diff = diff + 1440 end
    local ts = VANA_EPOCH + (vtDay + (wrap and 1 or 0)) * VD_DAY_SEC + targetVtMin * VD_MIN_F;
    return math.max(0, math.floor(ts - osNow));
end

-- ── RSE rotation ─────────────────────────────────────────────────────────────
-- 8 slots × 8 VT days = 64-day full cycle.
-- Adjust RSE_ANCHOR_OFFSET if slot names don't match the in-game NPC.
local RSE_ANCHOR_OFFSET = 0;

local RSE_SLOTS = {
    [0] = 'M Hume',   [1] = 'F Hume',
    [2] = 'M Elvaan', [3] = 'F Elvaan',
    [4] = 'M Taru',   [5] = 'F Taru',
    [6] = 'Mithra',   [7] = 'Galka',
};

-- Location cycles through 3 dungeons each Vana'diel week (every 8 VT days).
-- Tied to the absolute week counter, not the race index — race and location advance
-- independently through the 64-week grand cycle.
-- Formula: locIdx = (absWeek + RSE_LOC_WEEK_OFFSET) % 3
-- Adjust RSE_LOC_WEEK_OFFSET if the shown location doesn't match in-game.
-- Default (1) calibrated against Horizogenes/Pyogenes RSE calendar:
-- M Taru -> Shakrami, F Taru -> Ordelle, Mithra -> Gusgen, etc.
local RSE_LOC_WEEK_OFFSET = 1;
local RSE_LOCATIONS = {
    [0] = 'Shakrami Maze',
    [1] = 'Ordelle Caves',
    [2] = 'Gusgen Mines',
};

-- ── Moon phase data ───────────────────────────────────────────────────────────
local PHASE_NAMES = {
    [0]  = 'New Moon',         [1]  = 'Waxing Crescent', [2]  = 'Waxing Crescent',
    [3]  = 'First Quarter',    [4]  = 'Waxing Gibbous',  [5]  = 'Waxing Gibbous',
    [6]  = 'Full Moon',        [7]  = 'Waning Gibbous',  [8]  = 'Waning Gibbous',
    [9]  = 'Last Quarter',     [10] = 'Waning Crescent', [11] = 'Waning Crescent',
};

-- MoonDay at which each phase INDEX begins.
-- Each phase is exactly 7 VT days.  New Moon wraps around moonDay 0:
-- it starts at moonDay 80 (10% waning) and ends before moonDay 3 (7% waxing).
local PHASE_START_DAYS = {
    [0]=80,  -- New Moon:           moonDays 80-83 + 0-2 (wraps, 7 days total)
    [1]=3,   -- Waxing Crescent #1: moonDays  3- 9
    [2]=10,  -- Waxing Crescent #2: moonDays 10-16
    [3]=17,  -- First Quarter:      moonDays 17-23
    [4]=24,  -- Waxing Gibbous #1:  moonDays 24-30
    [5]=31,  -- Waxing Gibbous #2:  moonDays 31-37
    [6]=38,  -- Full Moon:          moonDays 38-44
    [7]=45,  -- Waning Gibbous #1:  moonDays 45-51
    [8]=52,  -- Waning Gibbous #2:  moonDays 52-58
    [9]=59,  -- Last Quarter:       moonDays 59-65
    [10]=66, -- Waning Crescent #1: moonDays 66-72
    [11]=73, -- Waning Crescent #2: moonDays 73-79
};

-- ── Local helpers ─────────────────────────────────────────────────────────────

local function PhaseIndex(moonDay)
    -- New Moon wraps: moonDays 80-83 and 0-2 all belong to phase 0.
    if moonDay >= 80 or moonDay <= 2 then return 0 end
    -- All other phases are clean 7-day segments from moonDay 3 onward.
    return math.floor((moonDay - 3) / 7) + 1;
end

local function FmtTime(minOfDay)
    return string.format('%02d:%02d', math.floor(minOfDay / 60), minOfDay % 60);
end

-- Format a real-Earth countdown (seconds) as a human-readable string.
local function FmtRealCountdown(secs)
    if secs <= 0 then return '0m 00s' end
    local d = math.floor(secs / 86400);
    local h = math.floor(secs % 86400 / 3600);
    local m = math.floor(secs % 3600 / 60);
    local s = math.floor(secs % 60);
    if d > 0 then
        return h > 0 and string.format('%dd %dh', d, h) or string.format('%dd', d);
    elseif h > 0 then
        return string.format('%dh %02dm', h, m);
    elseif m > 0 then
        return string.format('%dm %02ds', m, s);
    else
        return string.format('%ds', s);
    end
end

-- Format a Unix timestamp as a short Earth date string.
local function FmtDate(ts)
    return os.date('%a %d %b %H:%M', math.floor(ts));
end

-- Convert ARGB hex -> imgui float4 table
local function ToF4(argb)
    return {
        bit.band(bit.rshift(argb, 16), 0xFF) / 255.0,
        bit.band(bit.rshift(argb,  8), 0xFF) / 255.0,
        bit.band(argb,                0xFF) / 255.0,
        bit.band(bit.rshift(argb, 24), 0xFF) / 255.0,
    };
end

-- Boarding [dep-boardVt, dep). dep=0 → [1440-boardVt, 1440) (e.g. 21:00-24:00 for 180 VT board).
local function InFerryBoarding(vtMin, dep, boardVt)
    local start = (dep - boardVt + 1440) % 1440;
    if dep == 0 then
        return vtMin >= start;
    end
    return vtMin >= start and vtMin < dep;
end

-- In-transit [dep, dep+transitVt) only (never the full 8h cycle).
local function InFerryTransit(vtMin, dep, transitVt)
    local finish = (dep + transitVt) % 1440;
    if finish > dep then
        return vtMin >= dep and vtMin < finish;
    end
    return vtMin >= dep or vtMin < finish;
end

-- BOARDING [dep-boardVt, dep); IN-TRANSIT [dep, dep+transitVt). Countdown to dep / arrive.
-- All Fill* helpers mutate pre-allocated row tables (no per-tick table churn).
local function FillFerryRow(dst, city1, city2, vtMinuteOfDay, vtDay, osNow, schedule, arrow, boardVt, transitVt)
    boardVt   = boardVt   or FERRY_BOARD_VT_STD;
    transitVt = transitVt or FERRY_TRANSIT_VT_STD;
    dst.isHeader = nil;

    for _, dep in ipairs(schedule) do
        if InFerryBoarding(vtMinuteOfDay, dep, boardVt) then
            local secs = SecsToVtMin(dep, vtMinuteOfDay, vtDay, osNow);
            local cdColor = (secs < SOON_SECS) and CF4_SOON or CF4_BOARDING;
            dst.city1 = city1; dst.city1Color = CityColor(city1);
            dst.city2 = city2 or ''; dst.city2Color = CityColor(city2);
            dst.arrow = arrow or '<>';
            dst.countdownStr = FmtRealCountdown(secs); dst.cdColor = cdColor;
            dst.isBoarding = true; dst.isTransit = false; dst.isEmpty = false;
            return;
        end
    end

    for _, dep in ipairs(schedule) do
        if InFerryTransit(vtMinuteOfDay, dep, transitVt) then
            local finish = (dep + transitVt) % 1440;
            local secs = SecsToVtMin(finish, vtMinuteOfDay, vtDay, osNow);
            local cdColor = (secs < SOON_SECS) and CF4_SOON or CF4_WAITING;
            dst.city1 = city1; dst.city1Color = CityColor(city1);
            dst.city2 = city2 or ''; dst.city2Color = CityColor(city2);
            dst.arrow = arrow or '<>';
            dst.countdownStr = FmtRealCountdown(secs); dst.cdColor = cdColor;
            dst.isBoarding = false; dst.isTransit = true; dst.isEmpty = false;
            return;
        end
    end

    local bestDiff = math.huge;
    local bestBoard = nil;
    for _, dep in ipairs(schedule) do
        local boardStart = (dep - boardVt + 1440) % 1440;
        local diff = boardStart - vtMinuteOfDay;
        if diff <= 0 then diff = diff + 1440 end
        if diff < bestDiff then
            bestDiff = diff;
            bestBoard = boardStart;
        end
    end
    if not bestBoard then
        dst.city1 = city1; dst.city1Color = CityColor(city1);
        dst.city2 = city2 or ''; dst.city2Color = CityColor(city2);
        dst.arrow = arrow or '<>';
        dst.countdownStr = '--'; dst.cdColor = CF4_WAITING;
        dst.isBoarding = false; dst.isTransit = false; dst.isEmpty = true;
        return;
    end
    local secs = SecsToVtMin(bestBoard, vtMinuteOfDay, vtDay, osNow);
    local cdColor = (secs < SOON_SECS) and CF4_SOON or CF4_WAITING;
    dst.city1 = city1; dst.city1Color = CityColor(city1);
    dst.city2 = city2 or ''; dst.city2Color = CityColor(city2);
    dst.arrow = arrow or '<>';
    dst.countdownStr = FmtRealCountdown(secs); dst.cdColor = cdColor;
    dst.isBoarding = false; dst.isTransit = false; dst.isEmpty = false;
end

local function FillHeader(dst, text)
    dst.isHeader = true;
    dst.label = text;
    dst.isEmpty = nil;
end

local function FillCLRow(dst, route, transit, boarding, soon, oos, secs, cdColor)
    dst.isHeader = nil;
    dst.city1 = route.fromName; dst.city1Color = route.fromColor;
    dst.city2 = route.toName;   dst.city2Color = route.toColor; dst.arrow = '>';
    dst.city3 = route.city3;    dst.city3Color = route.city3Color;
    dst.routeVia = route.routeVia;
    dst.countdownStr = FmtRealCountdown(secs); dst.cdColor = cdColor;
    dst.isBoarding = boarding; dst.isTransit = transit;
    dst.isServicedSoon = soon; dst.isOOS = oos; dst.isEmpty = false;
end

local function FillCLRouteRow(dst, route, vtMin, vtDay, osNow)
    local sched = route.schedule;

    for _, run in ipairs(sched) do
        local soonStart = (run.boarding - CL_SOON_VT + 1440) % 1440;
        if InVtInterval(vtMin, run.dep, run.arr) then
            FillCLRow(dst, route, true, false, false, false,
                SecsToVtMin(run.arr, vtMin, vtDay, osNow), CF4_CL_TRANS);
            return;
        elseif InVtInterval(vtMin, run.boarding, run.dep) then
            FillCLRow(dst, route, false, true, false, false,
                SecsToVtMin(run.dep, vtMin, vtDay, osNow), CF4_BOARDING);
            return;
        elseif InVtInterval(vtMin, soonStart, run.boarding) then
            FillCLRow(dst, route, false, false, true, false,
                SecsToVtMin(run.boarding, vtMin, vtDay, osNow), CF4_CL_SVC);
            return;
        end
    end

    local bestDiff = math.huge;
    local bestBoard = sched[1].boarding;
    for _, run in ipairs(sched) do
        local diff = run.boarding - vtMin;
        if diff <= 0 then diff = diff + 1440 end
        if diff < bestDiff then bestDiff = diff; bestBoard = run.boarding end
    end
    FillCLRow(dst, route, false, false, false, true,
        SecsToVtMin(bestBoard, vtMin, vtDay, osNow), CF4_CL_OOS);
end

local function FillAirshipLeg(dst, lbl, realSecs, opts)
    local c1, c2 = lbl:match('^(%S+) > (%S+)$');
    local secs   = math.max(0, realSecs);
    local cdColor = (secs < SOON_SECS) and CF4_SOON or CF4_WAITING;
    if opts.boarding then cdColor = CF4_BOARDING end
    dst.label = lbl;
    dst.city1 = c1 or lbl; dst.city1Color = CityColor(c1);
    dst.city2 = c2 or '';  dst.city2Color = CityColor(c2);
    dst.countdownStr = FmtRealCountdown(secs); dst.cdColor = cdColor;
    dst.isBoarding = opts.boarding or false;
    dst.isTransit = opts.transit or false;
    dst.isAwaiting = opts.awaiting or false;
    dst.isEmpty = false;
end

local function FillEmptyAirship(dst, lbl)
    dst.label = lbl;
    dst.city1 = lbl; dst.city1Color = CityColor(nil);
    dst.city2 = '';  dst.city2Color = CityColor(nil);
    dst.countdownStr = '--'; dst.cdColor = CF4_WAITING;
    dst.isBoarding = false; dst.isTransit = false;
    dst.isAwaiting = false; dst.isEmpty = true;
    dst.sub = nil;
end

local function InAirshipWindow(vtMin, startVt, endVt)
    if startVt == endVt then return false end
    if startVt < endVt then return vtMin >= startVt and vtMin < endVt end
    return vtMin >= startVt or vtMin < endVt;
end

local function AirshipCyclePhase(vt, depF, depR, depFNext, boardR, boardF)
    if InAirshipWindow(vt, depF, boardR) then return 'fwd_await_hub' end
    if InAirshipWindow(vt, boardR, depR) then return 'rev_board_hub' end
    if InAirshipWindow(vt, depR, boardF) then return 'fwd_await_city' end
    if InAirshipWindow(vt, boardF, depFNext) then return 'fwd_board_city' end
    return nil;
end

-- Display pairing (schedule math unchanged). labelFwd = City>Jeuno, labelRev = Jeuno>City.
--   Top: next service at the dock being approached (inbound name at destination).
--   Sub: leg that departed the other city — IN-TRANSIT until next Jeuno arrival.
local function FillRowBi(dst, subDst, labelFwd, labelRev, vtMinuteOfDay, vtDay, osNow, depFwd, depRev)
    local n     = #depFwd;
    local BOARD = 60;
    local vt    = vtMinuteOfDay;

    for i = 1, n do
        local depF       = depFwd[i];
        local depR       = depRev[i];
        local depFNext   = depFwd[(i % n) + 1];
        local boardR     = depR - BOARD;
        local boardF     = depFNext - BOARD;
        local returnHub  = depRev[(i % n) + 1] - BOARD;
        local phase = AirshipCyclePhase(vt, depF, depR, depFNext, boardR, boardF);
        if phase then
            local secsReturn = SecsToVtMin(returnHub, vt, vtDay, osNow);
            dst.isEmpty = false;
            dst.sub = subDst;
            if phase == 'fwd_await_hub' then
                FillAirshipLeg(dst, labelRev, SecsToVtMin(boardR, vt, vtDay, osNow), { awaiting=true });
                FillAirshipLeg(subDst, labelFwd, secsReturn, { transit=true });
            elseif phase == 'rev_board_hub' then
                FillAirshipLeg(dst, labelRev, SecsToVtMin(depR, vt, vtDay, osNow), { boarding=true });
                FillAirshipLeg(subDst, labelFwd, secsReturn, { transit=true });
            elseif phase == 'fwd_await_city' then
                FillAirshipLeg(dst, labelFwd, SecsToVtMin(boardF, vt, vtDay, osNow), { awaiting=true });
                FillAirshipLeg(subDst, labelRev, secsReturn, { transit=true });
            else
                FillAirshipLeg(dst, labelFwd, SecsToVtMin(depFNext, vt, vtDay, osNow), { boarding=true });
                FillAirshipLeg(subDst, labelRev, secsReturn, { transit=true });
            end
            return;
        end
    end

    FillEmptyAirship(dst, labelFwd);
end


local _lastSec = -1;   -- airships + boats refresh on real-second change
local _lastMin = -1;   -- RSE + lunar refresh on real-minute change

-- ── Pre-allocated output tables ───────────────────────────────────────────────
M.airships = {};
M.boats    = {};
M.rse      = {};
M.lunar    = {};

local BOAT_ROW_MAX = 24;

for i = 1, 4 do
    M.airships[i] = { sub = {} };
end
for i = 1, BOAT_ROW_MAX do
    M.boats[i] = {};
end
for i = 1, 5 do
    if M.rse[i] == nil then M.rse[i] = {} end
end
for i = 1, 12 do
    if M.lunar[i] == nil then M.lunar[i] = {} end
end

-- Pre-computed colour float4 tables exposed to render code (reference CF4_ tables, no extra allocation)
M.colorBoarding = CF4_BOARDING;
M.colorAwaiting = CF4_AWAITING;
M.colorSoon     = CF4_SOON;
M.colorWaiting  = CF4_WAITING;
M.colorServicedSoon  = {0.55, 0.95, 0.55, 1.0};   -- light green "Serviced Soon" label
M.colorGold     = {0.957, 0.855, 0.592, 1.0};   -- standard XIUI gold (header text)
M.colorGoldDark = {0.82,  0.64,  0.22,  1.0};   -- deeper/richer gold for active labels
M.colorGoldMuted= {0.72,  0.65,  0.46,  1.0};   -- gold-tinted grey for future labels
M.colorWhite    = {1.0,   1.0,   1.0,   1.0};
M.colorGrey     = {0.78,  0.78,  0.78,  1.0};
M.colorDimGrey  = {0.50,  0.50,  0.50,  1.0};

-- Expose the shared countdown formatter for use in ui.lua (e.g. TOD timer).
M.FmtCountdown = FmtRealCountdown;
M.FmtVtTime    = FmtTime;

-- ── M.Update ─────────────────────────────────────────────────────────────────
-- osNow         : os.time()  (integer Unix seconds)
-- vtMinuteOfDay : integer 0-1439
-- vtDay         : integer (absolute VT day count since epoch)
-- moonDay       : integer 0-83
function M.NeedsUpdate(osNow)
    local osSec = math.floor(osNow);
    local osMin = math.floor(osNow / 60);
    return osSec ~= _lastSec or osMin ~= _lastMin;
end

function M.Update(osNow, vtMinuteOfDay, vtDay, moonDay)
    local osSec = math.floor(osNow);
    local osMin = math.floor(osNow / 60);
    if osSec == _lastSec and osMin == _lastMin then
        return;
    end

    -- ── Airships + boats: rebuild every real second ───────────────────────────
    if osSec ~= _lastSec then
        _lastSec = osSec;

        local a = M.airships;
        FillRowBi(a[1], a[1].sub, 'Bastok > Jeuno', 'Jeuno > Bastok', vtMinuteOfDay, vtDay, osNow, DEP_BASTOK,  DEP_JEUNOBD);
        FillRowBi(a[2], a[2].sub, 'Sandy > Jeuno',  'Jeuno > Sandy',  vtMinuteOfDay, vtDay, osNow, DEP_SANDY,   DEP_JEUNOSD);
        FillRowBi(a[3], a[3].sub, 'Windy > Jeuno',  'Jeuno > Windy',  vtMinuteOfDay, vtDay, osNow, DEP_WINDY,   DEP_JEUNOWD);
        FillRowBi(a[4], a[4].sub, 'Kazham > Jeuno', 'Jeuno > Kazham', vtMinuteOfDay, vtDay, osNow, DEP_KAZHAM,  DEP_JEUNOKD);

        local b  = M.boats;
        local bi = 0;

        bi = bi + 1; FillHeader(b[bi], 'Boats  ');
        bi = bi + 1; FillFerryRow(b[bi], 'Selbina',   'Mhaura',    vtMinuteOfDay, vtDay, osNow, DEP_SELBINA_SM, '<>');
        bi = bi + 1; FillFerryRow(b[bi], 'Mhaura',    'Whitegate', vtMinuteOfDay, vtDay, osNow, DEP_MHAURA_WG,  '<>');
        bi = bi + 1; FillFerryRow(b[bi], 'Whitegate', 'Nashmau',   vtMinuteOfDay, vtDay, osNow, DEP_WG_NASHMAU, '<>',
            FERRY_BOARD_VT_NASH, FERRY_TRANSIT_VT_NASH);

        bi = bi + 1; FillHeader(b[bi], 'Bibiki Manaclipper  ');
        for _, route in ipairs(BIBIKI_ROUTES) do
            bi = bi + 1; FillCLRouteRow(b[bi], route, vtMinuteOfDay, vtDay, osNow);
        end

        bi = bi + 1; FillHeader(b[bi], "Carpenters' Landing Barge  ");
        for _, route in ipairs(CL_ROUTES) do
            bi = bi + 1; FillCLRouteRow(b[bi], route, vtMinuteOfDay, vtDay, osNow);
        end
        for i = bi + 1, BOAT_ROW_MAX do b[i] = nil; end
    end

    -- ── RSE + Lunar: rebuild every real minute ────────────────────────────────
    if osMin ~= _lastMin then
        _lastMin = osMin;

        -- ── RSE: current slot + next 4 ───────────────────────────────────────
        local secsPerSlot = 8 * VD_DAY_SEC;           -- 27648 s = 7.68 h per rotation
        local adj         = vtDay - RSE_ANCHOR_OFFSET;
        local dayInSlot   = adj % 8;
        local absWeek     = math.floor(adj / 8);
        local slotIdx     = absWeek % 8;

        -- Seconds already elapsed in the current RSE slot
        local secInSlot   = dayInSlot * VD_DAY_SEC + vtMinuteOfDay * VD_MIN_F;
        -- Seconds remaining until next rotation
        local secsToNext  = math.floor(secsPerSlot - secInSlot);

        local rse = M.rse;
        for i = 0, 4 do
            local si = (slotIdx + i) % 8;
            local e = rse[i + 1];
            e.slotName = RSE_SLOTS[si] or '???';
            local locIdx = (absWeek + i + RSE_LOC_WEEK_OFFSET) % 3;
            e.location = RSE_LOCATIONS[locIdx] or '???';
            if i == 0 then
                e.isCurrent    = true;
                e.countdownStr = FmtRealCountdown(secsToNext);
                e.dateStr      = '';
            else
                local secsUntil = secsToNext + (i - 1) * secsPerSlot;
                e.isCurrent    = false;
                e.countdownStr = FmtRealCountdown(secsUntil);
                e.dateStr      = FmtDate(osNow + secsUntil);
            end
        end

        -- ── Lunar: current phase + next 6 phase boundaries ───────────────────
        local currentPhaseIdx  = PhaseIndex(moonDay);
        local nextPhaseIdx     = (currentPhaseIdx + 1) % 12;
        local nextPhaseStartMd = PHASE_START_DAYS[nextPhaseIdx];

        -- Days until the current phase ends (= days until next phase starts)
        local daysUntilPhaseEnd = (nextPhaseStartMd - moonDay + VD_MOON_DAYS) % VD_MOON_DAYS;
        if daysUntilPhaseEnd == 0 then daysUntilPhaseEnd = VD_MOON_DAYS end

        -- Real seconds until current phase ends
        local secsUntilEnd = math.floor(daysUntilPhaseEnd * VD_DAY_SEC - vtMinuteOfDay * VD_MIN_F);

        local lun = M.lunar;
        local cur       = lun[1];
        cur.phaseName   = PHASE_NAMES[currentPhaseIdx] or '';
        cur.phaseIdx    = currentPhaseIdx;
        cur.isCurrent   = true;
        cur.countdownStr = FmtRealCountdown(secsUntilEnd);
        cur.dateStr     = FmtDate(osNow + secsUntilEnd);  -- when this phase ends

        -- Upcoming phases (cumulative offset from now) — show full 12-phase cycle
        local cumSecs = secsUntilEnd;
        for i = 1, 11 do
            local e    = lun[i + 1];
            local pidx = (currentPhaseIdx + i) % 12;
            e.phaseName    = PHASE_NAMES[pidx] or '';
            e.phaseIdx     = pidx;
            e.isCurrent    = false;
            e.countdownStr = FmtRealCountdown(cumSecs);
            e.dateStr      = FmtDate(osNow + cumSecs);   -- when this phase starts

            -- Duration of this phase in real seconds
            local np   = (pidx + 1) % 12;
            local sMd  = PHASE_START_DAYS[pidx];
            local eMd  = PHASE_START_DAYS[np];
            local dur  = (eMd - sMd + VD_MOON_DAYS) % VD_MOON_DAYS;
            if dur == 0 then dur = VD_MOON_DAYS end
            cumSecs = cumSecs + dur * VD_DAY_SEC;
        end
    end
end

return M;
