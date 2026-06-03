--[[
* Vana'Dial popup windows for XIUI.
*
* Renders the three floating popups that orbit the main Vana'Dial widget:
*   - Timers     (airships, boats, RSE, lunar phases)
*   - Time of Day  (day/night/dead-of-night icon + optional countdown)
*   - Weather     (elemental icon, single or double)
*
* Initialized once by display.lua via M.Initialize(ctx) with shared texture
* and position state.  No circular require — display requires popups, not vice-versa.
]]--

require('common');
local bit    = require('bit');
local imgui  = require('imgui');
local imtext = require('libs.imtext');

local TextureManager = require('libs.texturemanager');
local windowbg       = require('libs.windowbackground');
local timers         = require('modules.vanadial.timers');
local data           = require('modules.vanadial.data');

local M = {};

-- ── Shared context (injected by display.lua at Initialize) ────────────────────
-- ctx fields:
--   mainWinPos        {x,y}  — updated each frame by display.DrawWindow
--   mainWinSize       {w,h}  — updated each frame by display.DrawWindow
--   textures          [0..11] element/weather icons
--   moonPhaseTextures [0..11] moon phase icons
--   todTextures       {day, night, deadOfNight}
--   GetTexPtr         function(tex) → ptr
local _ctx = nil;

function M.Initialize(ctx)
    _ctx = ctx;
end

-- ── Constants ─────────────────────────────────────────────────────────────────

local WEATHER_POPUP_GAP = 4;  -- px gap between main window and popup

-- ── Window flags ──────────────────────────────────────────────────────────────

local WIN_FLAGS_WEATHER = bit.bor(
    ImGuiWindowFlags_NoDecoration,
    ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoBackground,
    ImGuiWindowFlags_NoBringToFrontOnFocus,
    ImGuiWindowFlags_NoDocking,
    ImGuiWindowFlags_NoMove,
    ImGuiWindowFlags_NoSavedSettings
);

-- Timers popup uses ImGui-drawn background (no NoBackground) so PushStyleColor controls it.
local WIN_FLAGS_TIMERS = bit.bor(
    ImGuiWindowFlags_NoDecoration,
    ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoDocking,
    ImGuiWindowFlags_NoMove,
    ImGuiWindowFlags_NoSavedSettings
);

-- ── Color helpers (shared with display.lua — tiny inline duplication) ─────────

local function ArgbR(c) return bit.band(bit.rshift(c, 16), 0xFF) / 255.0; end
local function ArgbG(c) return bit.band(bit.rshift(c,  8), 0xFF) / 255.0; end
local function ArgbB(c) return bit.band(c,                0xFF) / 255.0; end
local function ArgbA(c) return bit.band(bit.rshift(c, 24), 0xFF) / 255.0; end

-- Allocation-free ARGB→packed-U32 (ABGR). Avoids the {r,g,b,a} table that
-- imgui.GetColorU32(ARGBToImGui(...)) allocates on every call.
local function ToU32(argb)
    return ARGBToABGR(argb);
end

local function WithAlpha(argb, alpha)
    local a = math.floor(alpha * 255);
    return bit.bor(bit.lshift(a, 24), bit.band(argb, 0x00FFFFFF));
end

local function GetTexPtr(tex)
    return _ctx and _ctx.GetTexPtr(tex) or nil;
end

-- Reusable scratch tables for drawlist calls (consumed synchronously by ImGui),
-- plus constant UVs — eliminates per-call {x,y} / {u,v} allocations.
local UV0 = {0, 0};
local UV1 = {1, 1};
local _pa = {0, 0};
local _pb = {0, 0};

local function DLRect(dl, x1, y1, x2, y2, col, rounding, flags, thickness)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddRect(_pa, _pb, col, rounding, flags, thickness);
end

local function DLImage(dl, tex, x1, y1, x2, y2, col)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddImage(tex, _pa, _pb, UV0, UV1, col);
end

local function DLRectMultiColor(dl, x1, y1, x2, y2, c1, c2, c3, c4)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddRectFilledMultiColor(_pa, _pb, c1, c2, c3, c4);
end

-- ── Timers popup state ────────────────────────────────────────────────────────

local timersOpen         = false;
local timersLastActivity = 0;
local timersOpenedAt     = 0;

-- Smoothed height for "above" positioning — eliminates the 1-frame position
-- blink caused by ImGui's pivot using a stale window height. We track the
-- measured height each frame and lerp toward it; position is derived from
-- the smoothed value rather than relying on the pivot.
local smoothTimersH   = 300;
local measuredTimersH = 300;
local TIMER_H_LERP    = 0.70;

-- Command-driven section open: set by M.OpenTimersSection, cleared each frame.
local pendingOpenSection = nil;   -- label string of section to force-open
local pendingOpenBoats   = false; -- force all boat sub-groups open
local lastOpenedSection  = nil;   -- key of the last section opened via command

-- ── Popup position cache (weather / TOD) ──────────────────────────────────────

local cachedWeatherH = 0;
local cachedWeatherW = 0;
local cachedTodH     = 0;
local cachedTodW     = 0;

-- Wall-clock smoothed TOD countdown. Integer os.time() can advance by 2+ between
-- draws; easing by "1 per frame" still looks like a skip at 60fps. Instead decay
-- the shown value at 1 real second per real second (GetTickMs), never more than
-- 1s ahead of the true target.
local todDisplaySecs = nil;
local todLastDecayMs = nil;

local function UpdateTodDisplaySecs(targetSecs)
    local ms = data.GetTickMs and data.GetTickMs() or nil;
    if ms == nil then
        if todDisplaySecs == nil then
            todDisplaySecs = targetSecs;
        elseif targetSecs > todDisplaySecs + 5 then
            todDisplaySecs = targetSecs;
        elseif targetSecs < todDisplaySecs then
            todDisplaySecs = math.max(targetSecs, todDisplaySecs - 1);
        else
            todDisplaySecs = targetSecs;
        end
        return math.max(0, todDisplaySecs);
    end

    if todDisplaySecs == nil or todLastDecayMs == nil then
        todDisplaySecs = targetSecs;
        todLastDecayMs = ms;
        return math.max(0, todDisplaySecs);
    end

    if targetSecs > todDisplaySecs + 5 then
        todDisplaySecs = targetSecs;
        todLastDecayMs = ms;
        return math.max(0, todDisplaySecs);
    end

    local dt = (ms - todLastDecayMs) / 1000.0;
    if dt < 0 then
        todLastDecayMs = ms;
        dt = 0;
    elseif dt > 1.0 then
        dt = 1.0;
    end
    todLastDecayMs = ms;
    local prevDisplay = todDisplaySecs;
    todDisplaySecs = todDisplaySecs - dt;
    -- If this draw was stalled, do not drop more than 1s of display per frame.
    if prevDisplay - todDisplaySecs > 1.0 then
        todDisplaySecs = prevDisplay - 1.0;
    end

    if todDisplaySecs > targetSecs + 1 then
        todDisplaySecs = targetSecs + 1;
    end
    if todDisplaySecs < targetSecs then
        todDisplaySecs = targetSecs;
    end
    return math.max(0, todDisplaySecs);
end

-- ── Public: timers toggle ─────────────────────────────────────────────────────

function M.IsTimersOpen()
    return timersOpen;
end

-- Resets all timers-popup UI state (used on close so command toggle stays predictable).
local function CloseTimers()
    timersOpen           = false;
    lastOpenedSection    = nil;
    collapsePhase        = 0;
    pendingOpenSection   = nil;
    pendingOpenBoats     = false;
end

function M.SetTimersOpen(open)
    if open then
        timersOpen = true;
        timersLastActivity = os.clock();
        timersOpenedAt     = os.clock();
        -- Avoid a position jump when reopening above the clock: reuse the last
        -- measured height instead of a stale smoothed value from a prior session.
        smoothTimersH = measuredTimersH;
    else
        CloseTimers();
    end
end

-- Section keys → header labels used in DrawTimerSection.
local SECTION_LABELS = {
    vdships = 'Airships##vdTimers',
    vdboats = 'Boats##vdTimers',
    vdrse   = 'RSE##vdTimers',
    vdlunar = 'Lunar Phases##vdTimers',
};

-- Opens the timers popup and jumps to the given section.
-- Calling a second time with the same key closes the popup entirely.
function M.OpenTimersSection(key)
    local label = SECTION_LABELS[key];
    if not label then return; end
    if timersOpen and lastOpenedSection == key then
        -- Same command again — close the popup.
        CloseTimers();
    else
        M.SetTimersOpen(true);
        pendingOpenSection = label;
        lastOpenedSection  = key;
        if key == 'vdboats' then pendingOpenBoats = true; end
    end
end

-- ── Static style/color tables ─────────────────────────────────────────────────
-- PushStyleColor/PushStyleVar read these synchronously, so reusing constant
-- tables avoids re-allocating identical literals on every frame.
local COL_GOLD_TEXT  = {0.957, 0.855, 0.592, 1.0};
local COL_SEPARATOR  = {0.28, 0.28, 0.28, 0.55};
local COL_OOS        = {0.85, 0.22, 0.22, 1.0};

local COL_WINDOW_BG     = {0.06, 0.06, 0.07, 0.93};
local COL_WINDOW_BORDER = {0.38, 0.38, 0.38, 0.90};
local COL_HEADER        = {0.14, 0.12, 0.08, 1.0};
local COL_HEADER_HOVER  = {0.22, 0.19, 0.11, 1.0};
local COL_HEADER_ACTIVE = {0.28, 0.24, 0.12, 1.0};

local COL_BTN        = {0.18, 0.16, 0.12, 0.80};
local COL_BTN_HOVER  = {0.28, 0.24, 0.14, 0.90};
local COL_BTN_ACTIVE = {0.35, 0.30, 0.16, 1.0};
local COL_BTN_TEXT   = {0.76, 0.68, 0.47, 0.85};

local VAR_WINDOW_PADDING = {12, 8};
local VAR_FRAME_PADDING  = {6, 4};
local VAR_POPUP_PADDING  = {6, 6};

-- ── Timers popup helpers ──────────────────────────────────────────────────────

-- 2-phase collapse: phase 2 = collapse sub-groups only (parents stay open so
-- sub-groups render), phase 1 = collapse top-level headers.
local collapsePhase = 0;

-- Wraps a CollapsingHeader with XIUI gold label text.
local function DrawTimerSection(label, drawFn)
    if collapsePhase == 1 then
        imgui.SetNextItemOpen(false, ImGuiCond_Always);
    elseif pendingOpenSection ~= nil then
        -- Command-driven open: expand only the target, collapse everything else.
        imgui.SetNextItemOpen(pendingOpenSection == label, ImGuiCond_Always);
    end
    imgui.PushStyleColor(ImGuiCol_Text, COL_GOLD_TEXT);
    local isOpen = imgui.CollapsingHeader(label);
    imgui.PopStyleColor(1);
    if isOpen then drawFn() end
end

-- Thin separator between rows inside a timer section.
local function DrawSectionDivider()
    imgui.PushStyleColor(ImGuiCol_Separator, COL_SEPARATOR);
    imgui.Separator();
    imgui.PopStyleColor(1);
end

-- Collapse-all button — closure-free; positioned closest to the main widget.
local function DrawCollapseButton()
    imgui.PushStyleColor(ImGuiCol_Button,        COL_BTN);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, COL_BTN_HOVER);
    imgui.PushStyleColor(ImGuiCol_ButtonActive,  COL_BTN_ACTIVE);
    imgui.PushStyleColor(ImGuiCol_Text,          COL_BTN_TEXT);
    if imgui.SmallButton('_##vtTimersCollapse') then
        collapsePhase = 2;
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Collapse');
    end
    imgui.PopStyleColor(4);
end

-- One transport route row: Label | Status | Countdown
local function DrawRouteRow(row)
    if row.city1 then
        imgui.TextColored(row.city1Color, row.city1);
        if row.city2 and row.city2 ~= '' then
            imgui.SameLine(0, 4);
            imgui.TextColored(timers.colorGoldDark, row.arrow or '>');
            imgui.SameLine(0, 4);
            imgui.TextColored(row.city2Color, row.city2);
        end
        if row.city3 then
            imgui.SameLine(0, 4);
            imgui.TextColored(timers.colorGoldDark, '>');
            imgui.SameLine(0, 4);
            imgui.TextColored(row.city3Color, row.city3);
        end
        if row.routeVia then
            imgui.SameLine(0, 6);
            imgui.TextColored(timers.colorDimGrey, row.routeVia);
        end
    else
        imgui.TextColored(timers.colorGoldDark, row.label or '');
    end
    imgui.SameLine(0, 10);
    if row.isOOS then
        imgui.TextColored(COL_OOS, 'Out of Service');
        imgui.SameLine(0, 10);
    elseif row.isServicedSoon then
        imgui.TextColored(timers.colorServicedSoon, 'Serviced Soon');
        imgui.SameLine(0, 10);
    elseif row.isBoarding then
        imgui.TextColored(timers.colorBoarding, 'BOARDING');
        imgui.SameLine(0, 10);
    elseif row.isTransit then
        imgui.TextColored(timers.colorGoldDark, 'IN-TRANSIT');
        imgui.SameLine(0, 10);
    end
    local cdColor = (row.isEmpty or not row.cdColor) and timers.colorDimGrey or row.cdColor;
    imgui.TextColored(cdColor, row.countdownStr or '--');
end

local function DrawAirshipsContent()
    local a = timers.airships;
    for i, entry in ipairs(a) do
        DrawRouteRow(entry);
        if i < #a then DrawSectionDivider() end
    end
end

-- Memoized 'label##boatGroup' header IDs — avoids re-concatenating strings
-- (a fresh string allocation) for every boat header on every frame.
local _boatGroupIds = {};

local function DrawBoatsContent()
    local b = timers.boats;
    local groupOpen = false;
    imgui.Indent(10);
    for i, entry in ipairs(b) do
        if entry.isHeader then
            if collapsePhase >= 1 then
                imgui.SetNextItemOpen(false, ImGuiCond_Always);
            elseif pendingOpenBoats then
                imgui.SetNextItemOpen(true, ImGuiCond_Always);
            end
            local headerId = _boatGroupIds[entry.label];
            if not headerId then
                headerId = entry.label .. '##boatGroup';
                _boatGroupIds[entry.label] = headerId;
            end
            imgui.PushStyleColor(ImGuiCol_Text, timers.colorGoldDark);
            local open = imgui.CollapsingHeader(headerId);
            imgui.PopStyleColor(1);
            groupOpen = open;
        elseif groupOpen then
            DrawRouteRow(entry);
            if i < #b and not b[i + 1].isHeader then
                DrawSectionDivider();
            end
        end
    end
    imgui.Unindent(10);
end

local RSE_LOCATION_COLOR = {
    ['Shakrami Maze'] = {0.22, 0.80, 0.42, 1.0},  -- Windurst green
    ['Ordelle Caves'] = {0.90, 0.25, 0.30, 1.0},  -- Sandoria red
    ['Gusgen Mines']  = {0.33, 0.53, 0.93, 1.0},  -- Bastok blue
};

local function DrawRSELocation(loc)
    local col = RSE_LOCATION_COLOR[loc] or timers.colorDimGrey;
    imgui.TextColored(timers.colorDimGrey, '@');
    imgui.SameLine(0, 4);
    imgui.TextColored(col, loc or '');
end

local function DrawRSEContent()
    local rse = timers.rse;
    for i, e in ipairs(rse) do
        if e.isCurrent then
            imgui.TextColored(timers.colorGoldDark,  e.slotName);
            imgui.SameLine(0, 5);
            DrawRSELocation(e.location);
            imgui.SameLine(0, 10);
            imgui.TextColored(timers.colorSoon, e.countdownStr .. ' left');
        else
            imgui.TextColored(timers.colorGoldMuted, e.slotName);
            imgui.SameLine(0, 5);
            DrawRSELocation(e.location);
            imgui.SameLine(0, 10);
            imgui.TextColored(timers.colorDimGrey, e.dateStr);
            imgui.SameLine(0, 10);
            imgui.TextColored(timers.colorWaiting, e.countdownStr);
        end
        if i < #rse then DrawSectionDivider() end
    end
end

local function DrawLunarContent()
    local lun  = timers.lunar;
    local dl   = imgui.GetWindowDrawList();
    local isz  = math.floor(imgui.GetTextLineHeight());

    local function DrawPhaseIcon(phaseIdx)
        local iconIdx = data.PHASE_ICON_MAP[phaseIdx] or phaseIdx;
        local tex = GetTexPtr(_ctx and _ctx.moonPhaseTextures[iconIdx]);
        local cx, cy = imgui.GetCursorScreenPos();
        if tex then
            DLImage(dl, tex, cx, cy, cx + isz, cy + isz, 0xFFFFFFFF);
        end
        imgui.Dummy({isz, isz});
    end

    for i, e in ipairs(lun) do
        local isNew  = (e.phaseIdx == 0);
        local isFull = (e.phaseIdx == 6);
        local rowX, rowY = imgui.GetCursorScreenPos();

        if e.isCurrent then
            DrawPhaseIcon(e.phaseIdx);
            imgui.SameLine(0, 4);
            imgui.TextColored(timers.colorGoldDark,  e.phaseName);
            imgui.SameLine(0, 10);
            imgui.TextColored(timers.colorDimGrey, 'ends');
            imgui.SameLine(0, 4);
            imgui.TextColored(timers.colorGrey,    e.dateStr);
            imgui.SameLine(0, 10);
            imgui.TextColored(timers.colorSoon,    e.countdownStr);
        else
            DrawPhaseIcon(e.phaseIdx);
            imgui.SameLine(0, 4);
            imgui.TextColored(timers.colorGoldMuted, e.phaseName);
            imgui.SameLine(0, 10);
            imgui.TextColored(timers.colorDimGrey, e.dateStr);
            imgui.SameLine(0, 10);
            imgui.TextColored(timers.colorWaiting, e.countdownStr);
        end

        -- Blood-red border for New Moon; moonlit-blue border for Full Moon
        if isNew or isFull then
            local mx, my = imgui.GetItemRectMax();
            local borderArgb = isNew and 0xFFCC2222 or 0xFF4499FF;
            DLRect(dl, rowX - 3, rowY - 1, mx + 3, my + 1,
                ToU32(WithAlpha(borderArgb, 0.80)), 3, nil, 1.0);
        end

        if i < #lun then DrawSectionDivider() end
    end
end

-- ── Public: DrawTimersPopup ────────────────────────────────────────────────────

function M.DrawTimersPopup(fontSize, colorCfg, rounding)
    local cfg = gConfig;
    if not cfg or not _ctx or not timersOpen then return; end

    local mainWinPos  = _ctx.mainWinPos;
    local mainWinSize = _ctx.mainWinSize;

    local side = cfg.vanaDialTimerSide or 'above';
    local popX = mainWinPos.x;

    imgui.PushStyleColor(ImGuiCol_WindowBg,      COL_WINDOW_BG);
    imgui.PushStyleColor(ImGuiCol_Border,        COL_WINDOW_BORDER);
    imgui.PushStyleColor(ImGuiCol_Header,        COL_HEADER);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, COL_HEADER_HOVER);
    imgui.PushStyleColor(ImGuiCol_HeaderActive,  COL_HEADER_ACTIVE);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, rounding);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, VAR_WINDOW_PADDING);
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding,  VAR_FRAME_PADDING);

    -- Smooth height lerp for "above" mode positioning (no pivot needed).
    smoothTimersH = smoothTimersH + (measuredTimersH - smoothTimersH) * TIMER_H_LERP;

    if side == 'above' then
        local popY = mainWinPos.y - 4 - math.floor(smoothTimersH + 0.5);
        imgui.SetNextWindowPos({popX, popY}, ImGuiCond_Always);
    else
        imgui.SetNextWindowPos({popX, mainWinPos.y + mainWinSize.h + 4}, ImGuiCond_Always);
    end
    imgui.SetNextWindowSizeConstraints({220, 0}, {600, 9999});

    -- Capture global font size BEFORE Begin to avoid feedback loop.
    local globalFontSize = imgui.GetFontSize();
    if not globalFontSize or globalFontSize <= 1 then globalFontSize = 13; end

    local timersHovered = false;
    if imgui.Begin("Vana'Dial Timers", true, WIN_FLAGS_TIMERS) then
        local fontScale = math.max(0.5, math.min(3.0, fontSize / globalFontSize));
        imgui.SetWindowFontScale(fontScale);

        if side == 'below' then
            DrawCollapseButton();
            imgui.Separator();
        end

        DrawTimerSection('Airships##vdTimers',     DrawAirshipsContent);
        DrawTimerSection('Boats##vdTimers',        DrawBoatsContent);
        DrawTimerSection('RSE##vdTimers',          DrawRSEContent);
        DrawTimerSection('Lunar Phases##vdTimers', DrawLunarContent);

        -- Tick down the collapse phase: 2→1 (sub-groups done, top-level next frame), 1→0 (done).
        if collapsePhase > 0 then
            collapsePhase = collapsePhase - 1;
        end

        -- Clear command-open flags after one frame so they don't re-fire.
        pendingOpenSection = nil;
        pendingOpenBoats   = false;

        if side == 'above' then
            imgui.Separator();
            DrawCollapseButton();
        end

        -- Measure actual window height for the smooth position lerp.
        local _, wh = imgui.GetWindowSize();
        if wh and wh > 1 then measuredTimersH = wh; end

        -- Flag 32 = AllowWhenBlockedByActiveItem
        timersHovered = imgui.IsWindowHovered(32);
        if timersHovered then
            timersLastActivity = os.clock();
        end
        imgui.SetWindowFontScale(1.0);
    end
    imgui.End();

    -- Auto-close: click outside
    if cfg.vanaDialTimersAutoCloseClick then
        if (imgui.IsMouseClicked(0) or imgui.IsMouseClicked(1))
            and not timersHovered
            and (os.clock() - timersOpenedAt) > 0.15 then
            CloseTimers();
        end
    end

    -- Auto-close: idle timeout
    if cfg.vanaDialTimersAutoCloseIdle then
        local idleSec = cfg.vanaDialTimersAutoCloseIdleSec or 5;
        if os.clock() - timersLastActivity > idleSec then
            CloseTimers();
        end
    end

    imgui.PopStyleVar(3);
    imgui.PopStyleColor(5);
end

-- ── Public: DrawTodPopup ───────────────────────────────────────────────────────

function M.DrawTodPopup(vtHour, vtMinuteOfDay, iconSize, colorCfg, rounding, alignOverride)
    local cfg = gConfig;
    if not cfg or not _ctx then return; end

    local mainWinPos  = _ctx.mainWinPos;
    local mainWinSize = _ctx.mainWinSize;
    local tod         = _ctx.todTextures;

    local todTexRaw =
        (vtHour >= 20 or vtHour < 4)     and tod.deadOfNight
        or (vtHour >= 6 and vtHour < 18) and tod.day
        or tod.night;
    local todTex = GetTexPtr(todTexRaw);
    if not todTex then return; end

    local side  = cfg.vanaDialTodSide or 'left';
    local align = alignOverride or cfg.vanaDialTodAlign or 'left';
    local wx, wy = mainWinPos.x, mainWinPos.y;
    local ww, wh = mainWinSize.w, mainWinSize.h;

    -- Timer countdown to next TOD transition
    local showTimer = cfg.vanaDialTodShowTimer == true;
    local timerStr  = nil;
    if not showTimer then
        todDisplaySecs = nil;
        todLastDecayMs = nil;
    end
    if showTimer then
        -- Period boundaries in VT minutes:
        --   Dead of Night : [1200,1440) ∪ [0,240)  → transitions to Night at 04:00 (240)
        --   Night (early) : [240,360)               → transitions to Day   at 06:00 (360)
        --   Day           : [360,1080)              → transitions to Night at 18:00 (1080)
        --   Night (late)  : [1080,1200)             → transitions to Dead  at 20:00 (1200)
        local m = vtMinuteOfDay;
        local target;
        if m >= 1200 or m < 240 then
            target = 240;
        elseif m < 360 then
            target = 360;
        elseif m < 1080 then
            target = 1080;
        else
            target = 1200;
        end
        local vtMinFrac = (data.GetRawTime() % data.VD_DAY_SEC) / data.VD_MIN_F;
        local diffFrac  = target - vtMinFrac;
        if diffFrac <= 0 then diffFrac = diffFrac + 1440 end;
        local secs = math.max(0, diffFrac * data.VD_MIN_F);
        timerStr = timers.FmtCountdown(UpdateTodDisplaySecs(secs));
    end

    if cachedTodW == 0 then cachedTodW = iconSize + 12; end
    if cachedTodH == 0 then cachedTodH = iconSize + 12; end

    local popX, popY;
    if side == 'right' then
        popX = wx + ww + WEATHER_POPUP_GAP;
        popY = wy;
    elseif side == 'left' then
        popX = wx - WEATHER_POPUP_GAP - cachedTodW;
        popY = wy;
    elseif side == 'below' then
        popY = wy + wh + WEATHER_POPUP_GAP;
        popX = (align == 'right') and (wx + ww - cachedTodW) or wx;
    else -- 'above'
        popY = wy - cachedTodH - WEATHER_POPUP_GAP;
        popX = (align == 'right') and (wx + ww - cachedTodW) or wx;
    end

    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, rounding);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, VAR_POPUP_PADDING);
    imgui.SetNextWindowPos({popX, popY}, ImGuiCond_Always);

    if imgui.Begin("Vana'Dial Tod", true, WIN_FLAGS_WEATHER) then
        local pw, ph = imgui.GetWindowSize();
        cachedTodH = ph;
        cachedTodW = pw;

        local cx, cy   = imgui.GetCursorScreenPos();
        local drawList = imgui.GetWindowDrawList();

        local popBgPad  = 6;
        local bgX = cx - popBgPad; local bgY = cy - popBgPad;
        local bgW = pw;            local bgH = ph;
        local contentW  = pw - 12;
        local contentH  = ph - 12;
        local bgOpacity  = cfg.vanaDialBackgroundOpacity or 0.85;
        local bgRgb      = colorCfg.bgColor or 0xFF000000;
        local bgTheme    = 'Plain';
        local borderTheme = 'Window1';

        if bgTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx, cy, contentW, contentH, {
                theme=bgTheme, bgScale=cfg.vanaDialBgScale or 1.0,
                bgOpacity=bgOpacity, borderScale=0, borderOpacity=0,
                bgColor=bgRgb, borderColor=0x00000000, padding=popBgPad });
        elseif bgTheme ~= '-None-' then
            local opaqueU32 = ToU32(WithAlpha(bgRgb, bgOpacity));
            local transpU32 = ToU32(WithAlpha(bgRgb, 0.0));
            local midX = bgX + bgW / 2;
            DLRectMultiColor(drawList, bgX,bgY, midX,bgY+bgH, transpU32,opaqueU32,opaqueU32,transpU32);
            DLRectMultiColor(drawList, midX,bgY, bgX+bgW,bgY+bgH, opaqueU32,transpU32,transpU32,opaqueU32);
        end

        if borderTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx, cy, contentW, contentH, {
                theme=borderTheme, bgScale=0, bgOpacity=0,
                borderScale=cfg.vanaDialBorderScale or 1.0,
                borderOpacity=cfg.vanaDialBorderOpacity or 1.0,
                bgColor=0x00000000, borderColor=colorCfg.borderColor or 0xFFFFFFFF,
                padding=popBgPad });
        elseif borderTheme == 'Plain' then
            local borderArgb = WithAlpha(colorCfg.borderColor or 0xFFFFFFFF, cfg.vanaDialBorderOpacity or 1.0);
            DLRect(drawList, bgX,bgY, bgX+bgW,bgY+bgH, ToU32(borderArgb), rounding, nil, 1.0);
        end

        local iconOffX = math.max(0, math.floor((contentW - iconSize) / 2));
        DLImage(drawList, todTex, cx + iconOffX, cy, cx + iconOffX + iconSize, cy + iconSize,
            ToU32(0xEEFFFFFF));
        imgui.Dummy({iconSize, iconSize});

        if timerStr then
            local fontScale = iconSize / 28.0;
            imgui.SetWindowFontScale(fontScale);
            local tw, _ = imgui.CalcTextSize(timerStr);
            local textOffX = math.max(0, math.floor((contentW - tw) / 2));
            imgui.SetCursorPosX(imgui.GetCursorPosX() + textOffX);
            local timerArgb = colorCfg.todTimerColor or 0xFFFFFFFF;
            local timerF4   = {ArgbR(timerArgb), ArgbG(timerArgb), ArgbB(timerArgb), ArgbA(timerArgb)};
            imgui.TextColored(timerF4, timerStr);
            imgui.SetWindowFontScale(1.0);
        end

        if imgui.IsWindowHovered() then
            if cfg.vanaDialEnableTooltips ~= false and cfg.vanaDialTipTod ~= false then
                local todName =
                    (vtHour >= 20 or vtHour < 4)     and 'Dead of Night'
                    or (vtHour >= 6 and vtHour < 18) and 'Day'
                    or 'Night';
                imgui.SetTooltip(todName);
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

-- ── Public: DrawWeatherPopup ───────────────────────────────────────────────────

function M.DrawWeatherPopup(weatherId, fontSize, iconSize, colorCfg, rounding, offX, offY, alignOverride, iconAlpha)
    local cfg = gConfig;
    if not cfg or not _ctx then return; end

    local elemIdx = data.WEATHER_TO_ELEMENT[weatherId];
    if elemIdx == nil then return; end

    local mainWinPos  = _ctx.mainWinPos;
    local mainWinSize = _ctx.mainWinSize;

    local weatherTex = GetTexPtr(_ctx.textures[elemIdx]);
    if weatherTex == nil then return; end

    local isDouble = (weatherId % 2 ~= 0) and weatherId >= 5;
    local iconGap  = 2;
    local doubleW  = isDouble and (iconSize + iconGap) or 0;

    if cachedWeatherW == 0 then
        cachedWeatherW = iconSize + doubleW + 12;
    end

    local side  = cfg.vanaDialWeatherSide or 'right';
    local align = alignOverride or cfg.vanaDialWeatherAlign or 'left';
    local wx, wy = mainWinPos.x, mainWinPos.y;
    local ww, wh = mainWinSize.w, mainWinSize.h;

    local popX, popY;
    if side == 'right' then
        popX = wx + ww + WEATHER_POPUP_GAP;
        popY = wy;
    elseif side == 'left' then
        popX = wx - WEATHER_POPUP_GAP - cachedWeatherW;
        popY = wy;
    elseif side == 'below' then
        popY = wy + wh + WEATHER_POPUP_GAP;
        popX = (align == 'right') and (wx + ww - cachedWeatherW) or wx;
    else -- 'above'
        popY = wy - cachedWeatherH - WEATHER_POPUP_GAP;
        popX = (align == 'right') and (wx + ww - cachedWeatherW) or wx;
    end
    popX = popX + (offX or 0);
    popY = popY + (offY or 0);

    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, rounding);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, VAR_POPUP_PADDING);
    imgui.SetNextWindowPos({popX, popY}, ImGuiCond_Always);

    if imgui.Begin("Vana'Dial Weather", true, WIN_FLAGS_WEATHER) then
        local pw, ph = imgui.GetWindowSize();
        cachedWeatherH = ph;
        cachedWeatherW = pw;

        local cx, cy   = imgui.GetCursorScreenPos();
        local drawList = imgui.GetWindowDrawList();

        local popContentW = iconSize + doubleW;
        local popBgPad    = 6;
        local bgX = cx - popBgPad;
        local bgY = cy - popBgPad;
        local bgW = popContentW + popBgPad * 2;
        local bgH = iconSize    + popBgPad * 2;
        local bgOpacity   = cfg.vanaDialBackgroundOpacity or 0.85;
        local bgRgb       = colorCfg.bgColor  or 0xFF000000;
        local bgTheme     = 'Plain';
        local borderTheme = 'Window1';

        if bgTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx, cy, popContentW, iconSize, {
                theme=bgTheme, bgScale=cfg.vanaDialBgScale or 1.0,
                bgOpacity=bgOpacity, borderScale=0, borderOpacity=0,
                bgColor=bgRgb, borderColor=0x00000000, padding=popBgPad });
        elseif bgTheme ~= '-None-' then
            local opaqueU32 = ToU32(WithAlpha(bgRgb, bgOpacity));
            local transpU32 = ToU32(WithAlpha(bgRgb, 0.0));
            local midX = bgX + bgW / 2;
            DLRectMultiColor(drawList, bgX,bgY, midX,bgY+bgH, transpU32,opaqueU32,opaqueU32,transpU32);
            DLRectMultiColor(drawList, midX,bgY, bgX+bgW,bgY+bgH, opaqueU32,transpU32,transpU32,opaqueU32);
        end

        if borderTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx, cy, popContentW, iconSize, {
                theme=borderTheme, bgScale=0, bgOpacity=0,
                borderScale=cfg.vanaDialBorderScale   or 1.0,
                borderOpacity=cfg.vanaDialBorderOpacity or 1.0,
                bgColor=0x00000000, borderColor=colorCfg.borderColor or 0xFFFFFFFF,
                padding=popBgPad });
        elseif borderTheme == 'Plain' then
            local borderArgb = WithAlpha(colorCfg.borderColor or 0xFFFFFFFF, cfg.vanaDialBorderOpacity or 1.0);
            DLRect(drawList, bgX,bgY, bgX+bgW,bgY+bgH, ToU32(borderArgb), rounding, nil, 1.0);
        end

        local iconTint = ToU32(WithAlpha(0xFFFFFFFF, iconAlpha or 1.0));
        DLImage(drawList, weatherTex, cx,cy, cx+iconSize,cy+iconSize, iconTint);

        if isDouble then
            local x2 = cx + iconSize + iconGap;
            DLImage(drawList, weatherTex, x2,cy, x2+iconSize,cy+iconSize, iconTint);
        end

        imgui.Dummy({iconSize + doubleW, iconSize});

        if imgui.IsWindowHovered() then
            if cfg.vanaDialEnableTooltips ~= false and cfg.vanaDialTipWeather ~= false then
                imgui.SetTooltip(data.WEATHER_NAMES[weatherId] or 'Unknown');
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

-- ── Public: GetCachedSizes (used by display for popup stacking offsets) ────────

function M.GetCachedTodSize()
    return cachedTodW, cachedTodH;
end

function M.GetCachedWeatherSize()
    return cachedWeatherW, cachedWeatherH;
end

return M;
