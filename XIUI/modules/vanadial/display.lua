--[[
* Vana'Dial main window renderer for XIUI.
*
* Layout (when all options enabled):
*
*   ┌─ Vana'Dial ─────────────────────────────────────────────┐
*   │  VT: 18:32                       LT: 01:53 AM           │
*   │ ┌──────────┐ ▶ ┌────────────────┐ ▶ ┌──────────┐       │
*   │ │ [Fire]   │   │   [Earth]      │   │  [Wind]  │       │
*   │ │  65% ↑   │   │    72% ↑       │   │  73% ↑   │       │
*   │ │[↓][weak] │   │  [↓][weak]     │   │[↓][weak] │       │
*   │ └──────────┘   └────────────────┘   └──────────┘       │
*   └─────────────────────────────────────────────────────────┘
]]--

require('common');
local bit    = require('bit');
local imgui  = require('imgui');
local imtext = require('libs.imtext');

local TextureManager = require('libs.texturemanager');
local windowbg       = require('libs.windowbackground');
local timers         = require('modules.vanadial.timers');
local data           = require('modules.vanadial.data');
local popups         = require('modules.vanadial.popups');

local M = {};

-- ── Constants ─────────────────────────────────────────────────────────────────

local WEATHER_POPUP_GAP = 4;
local PAST_FUTURE_ALPHA = 0.18;
local BADGE_SCALE       = 0.40;
local VT_TEXT_COLOR     = 0xFFC3AE79; -- XIUI Gold Dark — fixed for VT clock text
local ARROW_SCALE       = 0.55;
local COL_ARROW         = '>';

-- ── Textures ──────────────────────────────────────────────────────────────────

local textures          = {};
local moonPhaseTextures = {};
local todTextures       = { day=nil, night=nil, deadOfNight=nil };
local arrowRightTex     = nil;
local moonUpTex         = nil;
local moonDownTex       = nil;
local clockIconTex      = nil;
local gearIconTex       = nil;

local function LoadTextures()
    for i = 0, 11 do
        local name = data.ELEMENT_NAMES[i];
        if name and not textures[i] then
            textures[i] = TextureManager.getFileTexture('VanaDial/elements/' .. name);
        end
    end
    for i = 0, 11 do
        if not moonPhaseTextures[i] then
            moonPhaseTextures[i] = TextureManager.getFileTexture('VanaDial/moon/phase_' .. i);
        end
    end
    if not arrowRightTex     then arrowRightTex     = TextureManager.getFileTexture('VanaDial/arrow_right');          end
    if not moonUpTex         then moonUpTex         = TextureManager.getFileTexture('VanaDial/moon_up');              end
    if not moonDownTex       then moonDownTex       = TextureManager.getFileTexture('VanaDial/moon_down');            end
    if not clockIconTex      then clockIconTex      = TextureManager.getFileTexture('VanaDial/clock_icon');           end
    if not gearIconTex       then gearIconTex       = TextureManager.getFileTexture('icons/gear');                    end
    if not todTextures.day   then todTextures.day   = TextureManager.getFileTexture('VanaDial/tod/tod_day');          end
    if not todTextures.night then todTextures.night = TextureManager.getFileTexture('VanaDial/tod/tod_night');        end
    if not todTextures.deadOfNight then
        todTextures.deadOfNight = TextureManager.getFileTexture('VanaDial/tod/tod_deadofnight');
    end
end

local function GetTexPtr(tex)
    if tex == nil then return nil; end
    return TextureManager.getTexturePtr(tex);
end

-- ── Color helpers ─────────────────────────────────────────────────────────────

local function ArgbR(c) return bit.band(bit.rshift(c, 16), 0xFF) / 255.0; end
local function ArgbG(c) return bit.band(bit.rshift(c,  8), 0xFF) / 255.0; end
local function ArgbB(c) return bit.band(c,                0xFF) / 255.0; end
local function ArgbA(c) return bit.band(bit.rshift(c, 24), 0xFF) / 255.0; end

-- Allocation-free ARGB→packed-U32 (ABGR). Avoids the {r,g,b,a} table that
-- imgui.GetColorU32(ARGBToImGui(...)) allocates on every call — this runs
-- dozens of times per frame in the draw path.
local function ToU32(argb)
    return ARGBToABGR(argb);
end

local function WithAlpha(argb, alpha)
    local a = math.floor(alpha * 255);
    return bit.bor(bit.lshift(a, 24), bit.band(argb, 0x00FFFFFF));
end

local function LerpArgb(c1, c2, t)
    local a1 = bit.band(bit.rshift(c1, 24), 0xFF);
    local r1 = bit.band(bit.rshift(c1, 16), 0xFF);
    local g1 = bit.band(bit.rshift(c1,  8), 0xFF);
    local b1 = bit.band(c1, 0xFF);
    local a2 = bit.band(bit.rshift(c2, 24), 0xFF);
    local r2 = bit.band(bit.rshift(c2, 16), 0xFF);
    local g2 = bit.band(bit.rshift(c2,  8), 0xFF);
    local b2 = bit.band(c2, 0xFF);
    local a = math.floor(a1 + (a2 - a1) * t + 0.5);
    local r = math.floor(r1 + (r2 - r1) * t + 0.5);
    local g = math.floor(g1 + (g2 - g1) * t + 0.5);
    local b = math.floor(b1 + (b2 - b1) * t + 0.5);
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
end

local function GetOutlineColor(weekday)
    return 0xFF000000;
end

-- ── Per-frame allocation sinks ────────────────────────────────────────────────

local _textPos        = {0, 0};
local _moonPctMeasW   = 0;
local _moonPctFontSz  = -1;

-- Reusable scratch tables for drawlist calls. ImGui consumes the point tables
-- synchronously within each call, so sharing two scratch points (plus constant
-- UVs) across all draws is safe and eliminates per-call {x,y} allocations.
local UV0 = {0, 0};
local UV1 = {1, 1};
local _pa = {0, 0};
local _pb = {0, 0};

local function DLRectFilled(dl, x1, y1, x2, y2, col, rounding)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddRectFilled(_pa, _pb, col, rounding);
end

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

local function DLLine(dl, x1, y1, x2, y2, col, thickness)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddLine(_pa, _pb, col, thickness);
end

local function DLCircleFilled(dl, x, y, radius, col, segments)
    _pa[1] = x; _pa[2] = y;
    dl:AddCircleFilled(_pa, radius, col, segments);
end

-- ── Frame caches ──────────────────────────────────────────────────────────────

local vtCache    = { hour=-1, min=-1, str='', measW=0 };
local ltCache    = { osMin=-1, osHour=-1, str='', measW=0 };
local lastOsTime  = -1;
local lastFontSize = -1;

-- ── Main window state ─────────────────────────────────────────────────────────

local mainWinPos  = {x=0, y=0};
local mainWinSize = {w=0, h=0};

-- Deferred tooltips: set during Begin/End, drawn after End() on foreground list
local pendingFenrirTooltip = nil;
local pendingDayWeekday    = nil;

-- Preview flags: set by config/vanadial.lua while sliders are dragged
if _G.XIUI_weatherElementalPreview == nil then _G.XIUI_weatherElementalPreview = false; end
if _G.XIUI_weatherBasePreview      == nil then _G.XIUI_weatherBasePreview      = false; end
if _G.XIUI_weatherTestExpiry       == nil then _G.XIUI_weatherTestExpiry       = 0;     end

-- ── Draw helpers ──────────────────────────────────────────────────────────────

local function DrawTextWithOutline(drawList, text, x, y, textArgb, outlineArgb, fontSize)
    local font    = imtext.GetFont();
    local ow      = 1;
    local textU32 = ToU32(textArgb);
    local outU32  = ToU32(outlineArgb);
    local fs = fontSize and (fontSize + 2) or nil;
    _textPos[1] = x + ow; _textPos[2] = y + ow;
    if fs and font then
        drawList:AddText(font, fs, _textPos, outU32, text);
    else
        drawList:AddText(_textPos, outU32, text);
    end
    _textPos[1] = x; _textPos[2] = y;
    if fs and font then
        drawList:AddText(font, fs, _textPos, textU32, text);
    else
        drawList:AddText(_textPos, textU32, text);
    end
end

-- colU32 is already a packed drawlist color (callers pass ToU32(...)).
local function DrawPill(drawList, x, y, w, h, colU32, rounding)
    local r = rounding or 4;
    DLRectFilled(drawList, x, y, x + w, y + h, colU32, r);
end

-- Draw a single day column: icon + moon% + weakness badge
local function DrawDayColumn(drawList, cx, cy, colWeekday, moonPercent, moonDay, alpha, iconSize, fontSize, colorConfig, showMoon, showBadge, disableIcons)
    local badgeSize = math.floor(iconSize * BADGE_SCALE);

    local elemArgb = colorConfig[data.ELEM_KEYS[colWeekday]] or 0xFFFFFFFF;

    local moonArrowSlot = showMoon and (math.floor(fontSize * 0.7) + 2) or 0;
    local phaseIconSlot = showMoon and (math.floor(fontSize + 2) + 2) or 0;
    local moonMaxW      = showMoon and (phaseIconSlot + _moonPctMeasW + moonArrowSlot) or 0;
    local colContentW   = math.max(iconSize, moonMaxW + 4);

    local iconY  = cy;
    local moonY  = iconY + iconSize + 2;

    local colH = showMoon
        and (iconSize + 2 + fontSize + 4)
        or  (iconSize + 4);

    -- Column card: dark background + element-colored border
    local cardPad = 4;
    local cardX   = cx - cardPad;
    local cardY   = cy - cardPad;
    local cardW   = colContentW + cardPad * 2;
    local cardH   = colH + cardPad * 2;
    DLRectFilled(drawList, cardX, cardY, cardX + cardW, cardY + cardH,
        ToU32(WithAlpha(0xFF050510, 0.70 * alpha)), 6);
    DLRect(drawList, cardX, cardY, cardX + cardW, cardY + cardH,
        ToU32(WithAlpha(elemArgb, alpha)), 6, nil, alpha >= 0.95 and 1.5 or 1.0);

    local iconX = cx + math.floor((colContentW - iconSize) / 2);

    if disableIcons then
        DLRectFilled(drawList, iconX, iconY, iconX + iconSize, iconY + iconSize,
            ToU32(WithAlpha(elemArgb, alpha * 0.85)), 3);
    else
        DLRectFilled(drawList, iconX, iconY, iconX + iconSize, iconY + iconSize,
            ToU32(WithAlpha(0xFF000000, alpha)), 3);
    end

    if not disableIcons then
        local iconTex = GetTexPtr(textures[colWeekday]);
        if iconTex then
            local tint = ToU32(WithAlpha(0xFFFFFFFF, alpha));
            DLImage(drawList, iconTex, iconX, iconY, iconX + iconSize, iconY + iconSize, tint);
        end
    end

    local iconBorderArgb = data.LIGHT_GROUP[colWeekday] and 0xFFF4DA97 or 0xFF6A0DAD;
    DLRect(drawList, iconX - 1, iconY - 1, iconX + iconSize + 1, iconY + iconSize + 1,
        ToU32(WithAlpha(iconBorderArgb, alpha * 0.85)), 4, nil, 1.0);

    if showMoon then
        local moonStr     = string.format('%d%%', moonPercent);
        local outlineArgb = WithAlpha(GetOutlineColor(colWeekday), alpha);
        local textArgb    = WithAlpha(elemArgb, alpha);
        local moonW, _    = imtext.Measure(moonStr, fontSize);

        local phaseIconSize = math.floor(fontSize + 2);
        local phaseTex = GetTexPtr(moonPhaseTextures[data.GetMoonPhaseRaw(moonDay)]);

        local moonArrowSize = math.floor(fontSize * 0.7);
        local moonArrowTex  = nil;
        if moonDay > 0 and moonDay < 42 then
            moonArrowTex = GetTexPtr(moonUpTex);
        elseif moonDay > 42 then
            moonArrowTex = GetTexPtr(moonDownTex);
        end
        local arrowGap  = moonArrowTex and 2 or 0;
        local phaseGap  = phaseTex and (phaseIconSize + 2) or 0;

        -- Center the entire group (phase icon + text + optional arrow) as a unit.
        -- Using only moonW would misplace the group whenever the arrow is absent (0% / 100%).
        local totalMoonRowW = phaseGap + moonW + (moonArrowTex and (moonArrowSize + arrowGap) or 0);
        local groupLeft     = cx + math.floor((colContentW - totalMoonRowW) / 2);
        local moonTextX     = groupLeft + phaseGap;

        local moonRowH  = fontSize + 4;
        local moonBaseY = moonY + math.floor((moonRowH - fontSize) / 2);

        -- Moon pill border for New Moon (blood red) and Full Moon (moonlit blue)
        local isNewMoonPhase  = (moonDay >= 80 or moonDay <= 2);
        local isFullMoonPhase = (moonDay >= 38 and moonDay <= 44);
        if isNewMoonPhase or isFullMoonPhase then
            local pillPad   = 4;
            local pillX = groupLeft - pillPad;
            local pillY = moonBaseY - 3;
            local pillW = totalMoonRowW + pillPad * 2;
            local pillH = fontSize + 6;
            if isNewMoonPhase then
                DrawPill(drawList, pillX, pillY, pillW, pillH,
                    ToU32(WithAlpha(0xFF6B0000, 0.30 * alpha)), 4);
                DLRect(drawList, pillX, pillY, pillX + pillW, pillY + pillH,
                    ToU32(WithAlpha(0xFFCC2222, 0.85 * alpha)), 4, nil, 1.0);
            else
                DrawPill(drawList, pillX, pillY, pillW, pillH,
                    ToU32(WithAlpha(0xFF001833, 0.35 * alpha)), 4);
                DLRect(drawList, pillX, pillY, pillX + pillW, pillY + pillH,
                    ToU32(WithAlpha(0xFF4499FF, 0.85 * alpha)), 4, nil, 1.0);
            end
        end

        if phaseTex then
            local phIconX = moonTextX - phaseGap;
            local phIconY = moonY + math.floor((moonRowH - phaseIconSize) / 2);
            DLImage(drawList, phaseTex, phIconX, phIconY,
                phIconX + phaseIconSize, phIconY + phaseIconSize, ToU32(WithAlpha(0xFFFFFFFF, alpha)));
        end

        -- Pulse the % text between normal element color and glow color on new/full moon.
        if isNewMoonPhase or isFullMoonPhase then
            local pulse = (math.sin(os.clock() * 4.0) + 1.0) * 0.5;
            local glowColor = isNewMoonPhase and 0xFFFF4444 or 0xFF88CCFF;
            textArgb = LerpArgb(textArgb, WithAlpha(glowColor, alpha), pulse);
        end

        DrawTextWithOutline(drawList, moonStr, moonTextX, moonBaseY, textArgb, outlineArgb, fontSize);

        if moonArrowTex then
            local arrowX = moonTextX + moonW + arrowGap;
            local arrowY = moonY + math.floor((moonRowH - moonArrowSize) / 2);
            DLImage(drawList, moonArrowTex, arrowX, arrowY,
                arrowX + moonArrowSize, arrowY + moonArrowSize, ToU32(WithAlpha(0xFFFFFFFF, alpha)));
        end
    end

    -- Weakness corner badge
    local weakWeekday = data.ELEMENT_DEFEATS[colWeekday];
    if showBadge ~= false and weakWeekday ~= nil then
        local cornerX = iconX + iconSize - badgeSize;
        local cornerY = iconY + iconSize - badgeSize;
        DLRectFilled(drawList, cornerX - 1, cornerY - 1, cornerX + badgeSize + 1, cornerY + badgeSize + 1,
            ToU32(WithAlpha(0xFF3B0000, alpha)), 2);
        if disableIcons then
            local weakArgb = colorConfig[data.ELEM_KEYS[weakWeekday]] or 0xFFFFFFFF;
            DLRectFilled(drawList, cornerX, cornerY, cornerX + badgeSize, cornerY + badgeSize,
                ToU32(WithAlpha(weakArgb, alpha * 0.85)), 2);
        else
            local badgeTex = GetTexPtr(textures[weakWeekday]);
            if badgeTex then
                DLImage(drawList, badgeTex, cornerX, cornerY, cornerX + badgeSize, cornerY + badgeSize,
                    ToU32(WithAlpha(0xFFFFFFFF, alpha)));
            end
        end
        DLRect(drawList, cornerX - 1, cornerY - 1, cornerX + badgeSize + 1, cornerY + badgeSize + 1,
            ToU32(WithAlpha(0xFF8B1010, alpha)), 2, nil, 1.0);
    end

    if gConfig and gConfig.vanaDialEnableTooltips ~= false
        and imgui.IsMouseHoveringRect({cardX, cardY}, {cardX + cardW, cardY + cardH}) then
        pendingDayWeekday = colWeekday;
    end

    return cardX, cardY, cardW, cardH;
end

-- ── Fenrir tooltip ────────────────────────────────────────────────────────────

local function FlushDayTooltip()
    if pendingDayWeekday == nil then return end
    local wd = pendingDayWeekday;
    pendingDayWeekday = nil;
    local name = data.WEEKDAY_NAMES[wd];
    if name then imgui.SetTooltip(name) end
end

local function DrawFenrirTooltip(drawList, cardX, cardY, cardW, cardH, moonDay, moonPercent)
    if not (gConfig and gConfig.vanaDialEnableTooltips ~= false
        and (gConfig.vanaDialTooltipFenrir or gConfig.vanaDialTooltipSeleneBow)) then return; end
    if not imgui.IsMouseHoveringRect({cardX, cardY}, {cardX + cardW, cardY + cardH}) then return; end
    DLRect(drawList, cardX, cardY, cardX + cardW, cardY + cardH,
        ToU32(0xCCFFFFFF), 6, nil, 2.0);
    pendingFenrirTooltip = {moonDay, moonPercent};
end

local function FlushFenrirTooltip()
    if not pendingFenrirTooltip then return; end
    local moonDay, moonPercent = pendingFenrirTooltip[1], pendingFenrirTooltip[2];
    pendingFenrirTooltip = nil;

    local showFenrir = not gConfig or gConfig.vanaDialTooltipFenrir  ~= false;
    local showSelene = not gConfig or gConfig.vanaDialTooltipSeleneBow ~= false;
    if not showFenrir and not showSelene then return; end

    local phaseIdx  = data.GetMoonPhaseRaw(moonDay);
    local phaseName = data.PHASE_NAMES[phaseIdx] or '?';

    local dl = imgui.GetForegroundDrawList();
    if not dl then return; end

    local fontSize    = 12;
    local pad         = 8;
    local lineSpacing = fontSize + 5;
    local colGap      = 10;
    local sectionGap  = math.floor(pad * 0.5);

    imtext.SetConfig('Tahoma', false, 1);

    local rows = {};
    local function addRow(lbl, val) rows[#rows+1] = {'row', lbl, val}; end
    local function addSep()         rows[#rows+1] = {'sep', '', ''}; end
    local function addHeader(txt)   rows[#rows+1] = {'header', txt, ''}; end

    if showFenrir then
        local lc = data.LUNAR_CRY[phaseIdx];
        local eh = data.ECLIPTIC_HOWL[phaseIdx];
        local eg = data.ECLIPTIC_GROWL[phaseIdx];
        if lc and eh and eg then
            addHeader('Fenrir Pacts');
            addRow('Lunar Cry',      string.format('Acc %+d   Eva %+d', lc[1], lc[2]));
            addRow('Ecliptic Howl',  string.format('Acc %+d   Eva %+d', eh[1], eh[2]));
            addRow('Ecliptic Growl', string.format('STR/DEX/VIT %+d   AGI/INT/MND/CHR %+d', eg[1], eg[2]));
        end
    end

    if showSelene then
        local sb = data.SELENE_BOW[phaseIdx];
        if sb then
            if showFenrir then addSep(); end
            addHeader("Selene's Bow");
            addRow('Rng Acc / Atk', string.format('%+d RAcc   %+d RAtk', sb[1], sb[2]));
        end
    end

    if #rows == 0 then return; end

    local labelColW = 0;
    local valueColW = 0;
    for _, r in ipairs(rows) do
        if r[1] == 'row' then
            local lw = imtext.Measure(r[2], fontSize);
            local vw = imtext.Measure(r[3], fontSize);
            if lw > labelColW then labelColW = lw; end
            if vw > valueColW then valueColW = vw; end
        end
    end
    labelColW = labelColW + colGap;

    local headerStr = phaseName .. '  (' .. moonPercent .. '%)';
    local headerW   = imtext.Measure(headerStr, fontSize);

    local maxSecW = 0;
    for _, r in ipairs(rows) do
        if r[1] == 'header' then
            local hw = imtext.Measure(r[2], fontSize);
            if hw > maxSecW then maxSecW = hw; end
        end
    end

    local separatorH = math.floor(pad * 0.75);
    local contentW   = math.max(headerW, maxSecW, labelColW + valueColW);
    local boxW       = contentW + pad * 2;

    local boxH = pad + lineSpacing + separatorH;
    for i, r in ipairs(rows) do
        if r[1] == 'row' then
            boxH = boxH + lineSpacing;
        elseif r[1] == 'header' then
            boxH = boxH + lineSpacing;
        elseif r[1] == 'sep' then
            boxH = boxH + sectionGap * 2 + 1;
        end
    end
    boxH = boxH + pad;

    local direction = (gConfig and gConfig.vanaDialTooltipDirection) or 'above';
    local ox = mainWinPos.x + math.floor((mainWinSize.w - boxW) / 2);
    local oy;
    if direction == 'below' then
        oy = mainWinPos.y + mainWinSize.h + 4;
    else
        oy = mainWinPos.y - boxH - 4;
    end

    local bgCol     = imgui.GetColorU32({0.06, 0.06, 0.07, 0.92});
    local borderCol = imgui.GetColorU32({0.45, 0.45, 0.45, 1.0});
    DLRectFilled(dl, ox, oy, ox + boxW, oy + boxH, bgCol, 4);
    DLRect(dl, ox, oy, ox + boxW, oy + boxH, borderCol, 4, nil, 1.0);

    local curY = oy + pad;
    imtext.Draw(dl, headerStr, ox + pad, curY, 0xFFF4DA97, fontSize);
    curY = curY + lineSpacing;

    local sepLineY = curY + math.floor(separatorH / 2);
    DLLine(dl, ox + pad, sepLineY, ox + boxW - pad, sepLineY,
        imgui.GetColorU32({0.35, 0.35, 0.35, 1.0}), 1.0);
    curY = curY + separatorH;

    local sepLineCol = imgui.GetColorU32({0.28, 0.28, 0.28, 1.0});
    for _, r in ipairs(rows) do
        local kind, a, b = r[1], r[2], r[3];
        if kind == 'header' then
            imtext.Draw(dl, a, ox + pad, curY, 0xFFCBAA50, fontSize);
            curY = curY + lineSpacing;
        elseif kind == 'row' then
            imtext.Draw(dl, a, ox + pad,             curY, 0xFFAAAAAA, fontSize);
            imtext.Draw(dl, b, ox + pad + labelColW, curY, 0xFFFFFFFF, fontSize);
            curY = curY + lineSpacing;
        elseif kind == 'sep' then
            curY = curY + sectionGap;
            DLLine(dl, ox + pad, curY, ox + boxW - pad, curY, sepLineCol, 1.0);
            curY = curY + sectionGap + 1;
        end
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

local WINDOW_KEY = 'VanaDial';

function M.Initialize()
    if gConfig then
        if not gConfig.windowPositions then gConfig.windowPositions = T{}; end
        if gConfig.windowPositions['VanaTime'] and not gConfig.windowPositions[WINDOW_KEY] then
            gConfig.windowPositions[WINDOW_KEY] = gConfig.windowPositions['VanaTime'];
        end
    end
    LoadTextures();
    -- Share texture tables and position state with popups via a context table.
    -- Tables are references — LoadTextures and DrawWindow update them in-place.
    popups.Initialize({
        mainWinPos        = mainWinPos,
        mainWinSize       = mainWinSize,
        textures          = textures,
        moonPhaseTextures = moonPhaseTextures,
        todTextures       = todTextures,
        GetTexPtr         = GetTexPtr,
    });
end

function M.Reset()
    vtCache    = { hour=-1, min=-1, str='', measW=0 };
    ltCache    = { osMin=-1, osHour=-1, str='', measW=0 };
    lastOsTime  = -1;
    lastFontSize = -1;
end

function M.Cleanup()
    -- Clear shared texture tables in place so popups' context keeps referencing
    -- the same tables (a fresh {} would orphan popups._ctx and the old textures).
    for k in pairs(textures)          do textures[k]          = nil; end
    for k in pairs(moonPhaseTextures) do moonPhaseTextures[k] = nil; end
    todTextures.day         = nil;
    todTextures.night       = nil;
    todTextures.deadOfNight = nil;
    arrowRightTex     = nil;
    moonUpTex         = nil;
    moonDownTex       = nil;
    clockIconTex      = nil;
    gearIconTex       = nil;
    popups.SetTimersOpen(false);
end

-- ── DrawWindow ────────────────────────────────────────────────────────────────

function M.DrawWindow(weatherId)
    local cfg = gConfig;
    if not cfg then return; end

    pendingFenrirTooltip = nil;
    pendingDayWeekday    = nil;

    local colorCfg = (cfg.colorCustomization or {}).vanaDial or {};
    local scale    = math.max(0.5, math.min(2.0, cfg.vanaDialScale    or 1.0));
    local fontSize = math.floor(math.max(8,  math.min(24, cfg.vanaDialFontSize or 12)) * scale);
    local iconSize = math.floor(math.max(16, math.min(64, cfg.vanaDialIconSize  or 28)) * scale);
    local rounding = 12.0;

    -- ── Game data (pure Lua — no FFI) ────────────────────────────────────────
    local rawTime       = data.GetRawTime();
    local weekday       = math.floor(rawTime / data.VD_DAY_SEC) % 8;
    local vtDay         = math.floor(rawTime / data.VD_DAY_SEC);
    local vtHour        = math.floor(rawTime % data.VD_DAY_SEC / data.VD_HOUR_SEC);
    local vtMin         = math.floor(rawTime % data.VD_HOUR_SEC / data.VD_MIN_F);
    local vtMinuteOfDay = vtHour * 60 + vtMin;
    local moonDay       = (math.floor(rawTime / data.VD_DAY_SEC) + data.VD_MOON_OFFSET) % data.VD_MOON_DAYS;
    local moonPct       = data.CalcMoonPercent(moonDay);

    local showTimers = cfg.vanaDialShowTimers ~= false;
    if showTimers and popups.IsTimersOpen() then
        timers.Update(os.time(), vtMinuteOfDay, vtDay, moonDay);
    end

    local pastWeekday   = (weekday  - 1 + 8)                   % 8;
    local futureWeekday = (weekday  + 1)                        % 8;
    local pastMoonDay   = (moonDay  - 1 + data.VD_MOON_DAYS)   % data.VD_MOON_DAYS;
    local futureMoonDay = (moonDay  + 1)                        % data.VD_MOON_DAYS;
    local pastMoonPct   = data.CalcMoonPercent(pastMoonDay);
    local futureMoonPct = data.CalcMoonPercent(futureMoonDay);

    -- ── Time string caches ───────────────────────────────────────────────────
    if vtHour ~= vtCache.hour or vtMin ~= vtCache.min then
        vtCache.hour  = vtHour;
        vtCache.min   = vtMin;
        vtCache.str   = string.format('VT: %02d:%02d', vtHour, vtMin);
        vtCache.measW = 0;
    end
    local vtStr = vtCache.str;

    local ltStr = '';
    if cfg.vanaDialShowLocalTime ~= false then
        local now = os.time();
        if now ~= lastOsTime then
            lastOsTime = now;
            local lt   = os.date('*t', now);
            local h    = lt.hour;
            local m    = lt.min;
            local ampm = h >= 12 and 'PM' or 'AM';
            local h12  = h % 12;
            if h12 == 0 then h12 = 12; end
            if h ~= ltCache.osHour or m ~= ltCache.osMin then
                ltCache.osHour = h;
                ltCache.osMin  = m;
                ltCache.str    = string.format('LT: %02d:%02d %s', h12, m, ampm);
                ltCache.measW  = 0;
            end
        end
        ltStr = ltCache.str;
    end

    -- ── Column layout geometry ───────────────────────────────────────────────
    local colPad = 8;

    if fontSize ~= lastFontSize then
        lastFontSize   = fontSize;
        vtCache.measW  = 0;
        ltCache.measW  = 0;
        _moonPctFontSz = -1;
    end
    if vtCache.measW == 0 then
        vtCache.measW = imtext.Measure(vtCache.str, fontSize);
    end
    if ltStr ~= '' and ltCache.measW == 0 then
        ltCache.measW = imtext.Measure(ltCache.str, fontSize);
    end
    if _moonPctFontSz ~= fontSize then
        _moonPctFontSz = fontSize;
        _moonPctMeasW  = imtext.Measure('100%', fontSize);
    end

    -- ── Window open ──────────────────────────────────────────────────────────
    local windowFlags = GetBaseWindowFlags(cfg.lockPositions);

    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, rounding);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {colPad, colPad});

    ApplyWindowPosition(WINDOW_KEY);

    local ok, err = pcall(function()
    if imgui.Begin("Vana'Dial", true, windowFlags) then
        SaveWindowPosition(WINDOW_KEY);

        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        mainWinPos.x  = wx;
        mainWinPos.y  = wy;
        mainWinSize.w = ww;
        mainWinSize.h = wh;

        local elemArgb    = colorCfg[data.ELEM_KEYS[weekday]] or 0xFFFFFFFF;
        local outlineArgb = GetOutlineColor(weekday);
        local vtTextColor = cfg.vanaDialVTElementColor and elemArgb or VT_TEXT_COLOR;

        local CARD_PAD      = 4;
        local SEP_GAP       = 4;
        local sepArrowW     = math.floor(iconSize * 0.5);

        local showGear        = cfg.vanaDialShowSettingsBtn ~= false;
        local showPastFuture  = cfg.vanaDialShowPastFuture ~= false;
        local showMoon        = cfg.vanaDialShowMoonPercent ~= false;
        local showBadge       = cfg.vanaDialShowWeaknessBadge ~= false;
        local plainDayIcons   = cfg.vanaDialPlainDayIcons == true;
        local pastFutureAlpha = cfg.vanaDialPastFutureOpacity or PAST_FUTURE_ALPHA;

        local moonArrowSlot = showMoon and (math.floor(fontSize * 0.7) + 2) or 0;
        local phaseIconSlot = showMoon and (math.floor(fontSize + 2) + 2) or 0;
        local moonMaxW      = showMoon and (phaseIconSlot + _moonPctMeasW + moonArrowSlot) or 0;
        local colContentW   = math.max(iconSize, moonMaxW + 4);
        local cardW         = colContentW + CARD_PAD * 2;
        local cardAreaW     = showPastFuture
            and (cardW * 3 + SEP_GAP * 4 + sepArrowW * 2)
            or  cardW;

        local clockH   = fontSize + 4;
        local colH     = showMoon and (iconSize + 2 + fontSize + 4) or (iconSize + 4);
        local contentW = cardAreaW;
        local vtMeasW  = vtCache.measW;
        local ltMeasW  = ltStr ~= '' and ltCache.measW or 0;

        local totalH = clockH + colH + colPad;
        local ltBelowColumns = (not showPastFuture) and (ltStr ~= '');
        if not showPastFuture then
            local inlineTodW = (not cfg.vanaDialTodPopup) and (clockH + 3) or 0;
            local numIcons   = (showTimers and 1 or 0) + (showGear and 1 or 0);
            local iconZoneW  = numIcons > 0 and (numIcons * clockH + (numIcons - 1) * 2 + 4) or 0;
            local vtRowNeed  = vtMeasW + inlineTodW + 8 + iconZoneW;
            local ltRowNeed  = ltStr ~= '' and (ltMeasW + 8) or 0;
            contentW = math.max(contentW, vtRowNeed, ltRowNeed);
        end
        if ltBelowColumns then
            totalH = totalH + clockH + 2;
        end

        local cx0, cy0 = imgui.GetCursorScreenPos();
        local drawList = imgui.GetWindowDrawList();

        -- ── Window background ────────────────────────────────────────────────
        local bgPad  = colPad;
        local bgX    = cx0 - bgPad;
        local bgY    = cy0 - bgPad;
        local bgW    = contentW + bgPad * 2;
        local bgH    = totalH  + bgPad * 2;
        local bgOpacity = cfg.vanaDialBackgroundOpacity or 0.85;
        local bgRgb  = colorCfg.bgColor or 0xFF000000;

        local bgTheme     = 'Plain';
        local borderTheme = 'Window1';

        if bgTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx0, cy0, contentW, totalH, {
                theme=bgTheme, bgScale=cfg.vanaDialBgScale or 1.0,
                bgOpacity=bgOpacity, borderScale=0, borderOpacity=0,
                bgColor=bgRgb, borderColor=0x00000000, padding=colPad });
        elseif bgTheme ~= '-None-' then
            local opaqueU32 = ToU32(WithAlpha(bgRgb, bgOpacity));
            local transpU32 = ToU32(WithAlpha(bgRgb, 0.0));
            local midX      = bgX + bgW / 2;
            DLRectMultiColor(drawList, bgX,bgY, midX,bgY+bgH, transpU32,opaqueU32,opaqueU32,transpU32);
            DLRectMultiColor(drawList, midX,bgY, bgX+bgW,bgY+bgH, opaqueU32,transpU32,transpU32,opaqueU32);
        end

        if borderTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx0, cy0, contentW, totalH, {
                theme=borderTheme, bgScale=0, bgOpacity=0,
                borderScale=cfg.vanaDialBorderScale or 1.0,
                borderOpacity=cfg.vanaDialBorderOpacity or 1.0,
                bgColor=0x00000000, borderColor=colorCfg.borderColor or 0xFFFFFFFF,
                padding=colPad });
        elseif borderTheme == 'Plain' then
            local borderArgb = WithAlpha(colorCfg.borderColor or 0xFFFFFFFF, cfg.vanaDialBorderOpacity or 1.0);
            DLRect(drawList, bgX,bgY, bgX+bgW,bgY+bgH, ToU32(borderArgb), rounding, nil, 1.0);
        end

        imgui.Dummy({contentW, totalH});

        -- ── Clock row ────────────────────────────────────────────────────────
        local clockY = cy0;

        do
            local gY   = clockY - 2;
            local gH   = clockH + 4;
            local gX1  = cx0 - 4;
            local gX2  = cx0 + contentW + 4;
            local midX = (gX1 + gX2) / 2;
            local glow   = ToU32(WithAlpha(elemArgb, 0.28));
            local transp = ToU32(WithAlpha(elemArgb, 0.0));
            DLRectMultiColor(drawList, gX1,gY, midX,gY+gH, transp,glow,glow,transp);
            DLRectMultiColor(drawList, midX,gY, gX2,gY+gH, glow,transp,transp,glow);
        end

        local iconSzClock = clockH;

        -- TOD icon (inline in clock row — only when popup is disabled)
        local todTexRaw =
            (vtHour >= 20 or vtHour < 4)     and todTextures.deadOfNight
            or (vtHour >= 6 and vtHour < 18) and todTextures.day
            or todTextures.night;
        local todIconTex = GetTexPtr(todTexRaw);

        local function DrawTodIcon(vtX)
            if not todIconTex then return end;
            if cfg.vanaDialTodPopup then return end;
            local tx = vtX + vtMeasW + 3;
            local ty = clockY + math.floor((clockH - clockH) / 2);
            DLImage(drawList, todIconTex, tx,ty, tx+clockH,ty+clockH, ToU32(0xEEFFFFFF));
            if cfg.vanaDialEnableTooltips ~= false and cfg.vanaDialTipTod ~= false
                and imgui.IsMouseHoveringRect({tx, ty}, {tx + clockH, ty + clockH}) then
                imgui.SetTooltip('Time of Day: ' .. (data.GetTodName(vtHour) or ''));
            end
        end

        local function DrawClockTooltips(vtX, ltX, ltClockY)
            if cfg.vanaDialEnableTooltips == false then return end;
            local ltY = ltClockY or clockY;
            if imgui.IsMouseHoveringRect({vtX,clockY},{vtX+vtMeasW,clockY+clockH}) then
                if cfg.vanaDialTipVT ~= false then imgui.SetTooltip("Vana'diel Time"); end
            elseif ltX and ltMeasW > 0
                and imgui.IsMouseHoveringRect({ltX,ltY},{ltX+ltMeasW,ltY+clockH}) then
                if cfg.vanaDialTipLT ~= false then imgui.SetTooltip('Local Time'); end
            end
        end

        local function DrawGearIcon(gx, gy, isz)
            local gearTex = GetTexPtr(gearIconTex);
            local gc2x, gc2y = gx + isz * 0.5, gy + isz * 0.5;
            DLCircleFilled(drawList, gc2x,gc2y, isz*0.65, ToU32(bit.bor(bit.lshift(0x55,24),0x000000)), 24);
            if gearTex then
                DLImage(drawList, gearTex, gx,gy, gx+isz,gy+isz, ToU32(0xCCC3AE79));
            end
            if imgui.IsMouseHoveringRect({gx,gy},{gx+isz,gy+isz}) then
                DLCircleFilled(drawList, gc2x,gc2y, isz*0.65, ToU32(0x30FFFFFF), 24);
                if cfg.vanaDialEnableTooltips ~= false then imgui.SetTooltip("Vana'Dial Settings"); end
                if imgui.IsMouseClicked(0) and XIUI_ToggleVanaDialConfig then XIUI_ToggleVanaDialConfig(); end
            end
        end

        if showTimers then
            local iconTex = GetTexPtr(clockIconTex);

            -- Determine layout based on what's shown
            local function PlaceClockIcon(icX, icY, isz)
                local icxFinal = icX;
                if showGear then
                    icxFinal = icX - math.floor((isz + 2) / 2);
                end
                local cx2, cy2 = icxFinal + isz * 0.5, icY + isz * 0.5;
                local glowAlpha = popups.IsTimersOpen() and 0xAA or 0x66;
                DLCircleFilled(drawList, cx2,cy2, isz*0.65, ToU32(bit.bor(bit.lshift(glowAlpha,24),0x000000)), 24);
                if iconTex then
                    DLImage(drawList, iconTex, icxFinal,icY, icxFinal+isz,icY+isz, ToU32(0xCCFFFFFF));
                end
                if imgui.IsMouseHoveringRect({icxFinal,icY},{icxFinal+isz,icY+isz}) then
                    DLCircleFilled(drawList, cx2,cy2, isz*0.65, ToU32(0x30FFFFFF), 24);
                    if imgui.IsMouseClicked(0) then
                        popups.SetTimersOpen(not popups.IsTimersOpen());
                    end
                end
                if showGear then
                    DrawGearIcon(icxFinal + isz + 2, icY, isz);
                end
            end

            if ltBelowColumns then
                local twoThird = math.floor(contentW * 2 / 3);
                local vtX  = cx0 + math.floor((twoThird - vtMeasW) / 2);
                local icX  = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local icY  = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawTextWithOutline(drawList, vtStr, vtX, clockY, vtTextColor, outlineArgb, fontSize);
                DrawTodIcon(vtX);
                PlaceClockIcon(icX, icY, iconSzClock);
                DrawClockTooltips(vtX, nil);
            elseif ltStr ~= '' then
                local third = math.floor(contentW / 3);
                local vtX  = cx0 + math.floor((third - vtMeasW) / 2);
                local icX  = cx0 + third + math.floor((third - iconSzClock) / 2);
                local icY  = clockY + math.floor((clockH - iconSzClock) / 2);
                local ltX  = cx0 + third * 2 + math.floor((third - ltMeasW) / 2);
                DrawTextWithOutline(drawList, vtStr, vtX, clockY, vtTextColor, outlineArgb, fontSize);
                DrawTodIcon(vtX);
                DrawTextWithOutline(drawList, ltStr, ltX, clockY, colorCfg.textColor or 0xFFFFFFFF, outlineArgb, fontSize);
                PlaceClockIcon(icX, icY, iconSzClock);
                DrawClockTooltips(vtX, ltX);
            else
                local twoThird = math.floor(contentW * 2 / 3);
                local vtX  = cx0 + math.floor((twoThird - vtMeasW) / 2);
                local icX  = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local icY  = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawTextWithOutline(drawList, vtStr, vtX, clockY, vtTextColor, outlineArgb, fontSize);
                DrawTodIcon(vtX);
                PlaceClockIcon(icX, icY, iconSzClock);
                DrawClockTooltips(vtX, nil);
            end
        elseif ltBelowColumns then
            local twoThird = showGear and math.floor(contentW * 2 / 3) or contentW;
            local vtX = cx0 + math.floor((twoThird - vtMeasW) / 2);
            DrawTextWithOutline(drawList, vtStr, vtX, clockY, vtTextColor, outlineArgb, fontSize);
            DrawTodIcon(vtX);
            DrawClockTooltips(vtX, nil);
            if showGear then
                local gx = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local gy = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawGearIcon(gx, gy, iconSzClock);
            end
        elseif ltStr ~= '' then
            local halfW = contentW / 2;
            local vtX   = cx0 + math.floor((halfW - vtMeasW) / 2);
            local ltX   = cx0 + halfW + math.floor((halfW - ltMeasW) / 2);
            DrawTextWithOutline(drawList, vtStr, vtX, clockY, vtTextColor, outlineArgb, fontSize);
            DrawTodIcon(vtX);
            DrawTextWithOutline(drawList, ltStr, ltX, clockY, colorCfg.textColor or 0xFFFFFFFF, outlineArgb, fontSize);
            DrawClockTooltips(vtX, ltX);
            if showGear then
                DrawGearIcon(cx0 + contentW - iconSzClock, clockY + math.floor((clockH - iconSzClock) / 2), iconSzClock);
            end
        else
            local twoThird = showGear and math.floor(contentW * 2 / 3) or contentW;
            local vtX = cx0 + math.floor((twoThird - vtMeasW) / 2);
            DrawTextWithOutline(drawList, vtStr, vtX, clockY, vtTextColor, outlineArgb, fontSize);
            DrawTodIcon(vtX);
            DrawClockTooltips(vtX, nil);
            if showGear then
                local gx = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local gy = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawGearIcon(gx, gy, iconSzClock);
            end
        end

        -- ── Day columns ──────────────────────────────────────────────────────
        local colY   = cy0 + clockH + colPad;
        local cardX0 = cx0;

        if showPastFuture then
            local pastX = cardX0 + CARD_PAD;
            local pcx, pcy, pcw, pch = DrawDayColumn(drawList, pastX, colY, pastWeekday,
                pastMoonPct, pastMoonDay, pastFutureAlpha,
                iconSize, fontSize, colorCfg, showMoon, showBadge, plainDayIcons);
            DrawFenrirTooltip(drawList, pcx, pcy, pcw, pch, pastMoonDay, pastMoonPct);

            local arr1X   = pastX + colContentW + CARD_PAD + SEP_GAP;
            local arrImgW = sepArrowW;
            local arrImgH = math.floor(colH * 0.75);
            local arr1Y   = colY + math.floor((colH - arrImgH) / 2);
            local arrTex  = GetTexPtr(arrowRightTex);
            local arrTint = ToU32(0xC0FFFFFF);
            if arrTex then
                DLImage(drawList, arrTex, arr1X,arr1Y, arr1X+arrImgW,arr1Y+arrImgH, arrTint);
            else
                DrawTextWithOutline(drawList, COL_ARROW, arr1X, colY + math.floor((colH-fontSize)/2),
                    0xFFFFFFFF, 0xFF000000, fontSize);
            end

            local curX = arr1X + sepArrowW + SEP_GAP + CARD_PAD;
            local ccx, ccy, ccw, cch = DrawDayColumn(drawList, curX, colY, weekday,
                moonPct, moonDay, 1.0,
                iconSize, fontSize, colorCfg, showMoon, showBadge, plainDayIcons);
            DrawFenrirTooltip(drawList, ccx, ccy, ccw, cch, moonDay, moonPct);

            local arr2X = curX + colContentW + CARD_PAD + SEP_GAP;
            if arrTex then
                DLImage(drawList, arrTex, arr2X,arr1Y, arr2X+arrImgW,arr1Y+arrImgH, arrTint);
            else
                DrawTextWithOutline(drawList, COL_ARROW, arr2X, colY + math.floor((colH-fontSize)/2),
                    0xFFFFFFFF, 0xFF000000, fontSize);
            end

            local futX = arr2X + sepArrowW + SEP_GAP + CARD_PAD;
            local fcx, fcy, fcw, fch = DrawDayColumn(drawList, futX, colY, futureWeekday,
                futureMoonPct, futureMoonDay, pastFutureAlpha,
                iconSize, fontSize, colorCfg, showMoon, showBadge, plainDayIcons);
            DrawFenrirTooltip(drawList, fcx, fcy, fcw, fch, futureMoonDay, futureMoonPct);
        else
            local cardOffX = math.floor((contentW - cardW) / 2);
            local ccx, ccy, ccw, cch = DrawDayColumn(drawList, cardX0 + cardOffX + CARD_PAD, colY, weekday,
                moonPct, moonDay, 1.0,
                iconSize, fontSize, colorCfg, showMoon, showBadge, plainDayIcons);
            DrawFenrirTooltip(drawList, ccx, ccy, ccw, cch, moonDay, moonPct);
        end

        -- LT below day columns when past/future is hidden
        if ltBelowColumns and ltStr ~= '' then
            local ltY = colY + colH + 2;
            local ltX = cx0 + math.floor((contentW - ltMeasW) / 2);
            DrawTextWithOutline(drawList, ltStr, ltX, ltY, colorCfg.textColor or 0xFFFFFFFF, outlineArgb, fontSize);
            if cfg.vanaDialEnableTooltips ~= false and cfg.vanaDialTipLT ~= false then
                if imgui.IsMouseHoveringRect({ltX,ltY},{ltX+ltMeasW,ltY+clockH}) then
                    imgui.SetTooltip('Local Time');
                end
            end
        end
    end -- imgui.Begin
    end); -- pcall
    imgui.End();
    imgui.PopStyleVar(2);
    if not ok then
        error(err, 2);
    end

    FlushDayTooltip();
    FlushFenrirTooltip();

    -- ── Popup stacking offsets ────────────────────────────────────────────────
    local todEnabled    = cfg.vanaDialTodPopup == true;

    local weatherTestId    = nil;
    local weatherTestAlpha = 1.0;
    if cfg.vanaDialShowWeather ~= false and cfg.vanaDialWeatherHideNonElemental then
        if os.clock() < (_G.XIUI_weatherTestExpiry or 0) then
            weatherTestId    = 4;  -- Hot Spell / Fire (first elemental in HorizonXI ordering)
            weatherTestAlpha = 0.35 + 0.65 * math.abs(math.sin(os.clock() * 3));
        end
    else
        _G.XIUI_weatherTestExpiry = 0;
    end

    local weatherEnabled = (cfg.vanaDialShowWeather ~= false
        and weatherId >= 0
        and not (cfg.vanaDialWeatherHideNonElemental and weatherId < 4))
        or (weatherTestId ~= nil);
    local todSide    = cfg.vanaDialTodSide     or 'left';
    local weatherSide = cfg.vanaDialWeatherSide or 'right';
    local sameSide   = todEnabled and weatherEnabled and (todSide == weatherSide);

    local weatherOffX, weatherOffY = 0, 0;
    local todAlignForce, weatherAlignForce = nil, nil;
    if sameSide then
        local _, cachedTodH = popups.GetCachedTodSize();
        if todSide == 'left' or todSide == 'right' then
            weatherOffY = cachedTodH + WEATHER_POPUP_GAP;
        else
            local todAlign     = cfg.vanaDialTodAlign     or 'left';
            local weatherAlign = cfg.vanaDialWeatherAlign or 'left';
            if todAlign == weatherAlign then
                local cachedTodW, _ = popups.GetCachedTodSize();
                todAlignForce = todAlign;
                if todAlign == 'right' then
                    weatherAlignForce = 'right';
                    weatherOffX = -(cachedTodW + WEATHER_POPUP_GAP);
                else
                    weatherAlignForce = 'left';
                    weatherOffX = cachedTodW + WEATHER_POPUP_GAP;
                end
            end
        end
    end

    -- Per-popup icon sizes
    local todIconSize;
    if cfg.vanaDialTodCustomScale then
        todIconSize = math.floor(math.max(16, math.min(64, cfg.vanaDialTodIconSize or 28)) * scale);
    else
        todIconSize = iconSize;
    end

    local weatherBaseSize;
    if cfg.vanaDialWeatherCustomScale then
        weatherBaseSize = math.floor(math.max(16, math.min(64, cfg.vanaDialWeatherIconSize or 28)) * scale);
    else
        weatherBaseSize = iconSize;
    end
    local weatherIconSize = weatherBaseSize;
    if cfg.vanaDialWeatherAdjustElemental then
        local isElemental   = weatherEnabled and weatherId >= 4;
        local previewActive = _G.XIUI_weatherElementalPreview == true;
        local previewBase   = _G.XIUI_weatherBasePreview == true;
        if not previewBase and (isElemental or previewActive) then
            if cfg.vanaDialWeatherCustomScale then
                weatherIconSize = math.floor(math.max(16, math.min(64, cfg.vanaDialWeatherElementalIconSize or 42)) * scale);
            else
                weatherIconSize = math.min(math.floor(weatherBaseSize * 1.5), math.floor(64 * scale));
            end
        end
    end

    if todEnabled then
        popups.DrawTodPopup(vtHour, vtMinuteOfDay, todIconSize, colorCfg, rounding, todAlignForce);
    end
    if weatherEnabled then
        popups.DrawWeatherPopup(weatherTestId or weatherId, fontSize, weatherIconSize,
            colorCfg, rounding, weatherOffX, weatherOffY, weatherAlignForce, weatherTestAlpha);
    end

    if showTimers and popups.IsTimersOpen() then
        local timersFontSize = math.floor(math.max(8, math.min(24, cfg.vanaDialTimersFontSize or 12)) * scale);
        popups.DrawTimersPopup(timersFontSize, colorCfg, rounding);
    end
end

return M;
