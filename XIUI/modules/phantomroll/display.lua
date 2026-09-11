--[[
* Phantom Roll window: die, potency, duration bar, and Double-Up odds.
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local data = require('modules.phantomroll.data');
local dice = require('modules.phantomroll.dice');
local tracker = require('modules.phantomroll.tracker');

local M = {};

local WINDOW_NAME = 'PhantomRoll';

local TEXT = {
    label       = 0xFFC7CCD4,
    labelHot    = 0xFFFFD159,
    labelCold   = 0xFF9ED9FF,
    potency     = 0xFFF5F7FA,
    potencyHot  = 0xFFFFDB66,
    potencyCold = 0xFFB3E3FF,
    potencyBust = 0xFFFF736B,
    muted       = 0xFF8C949E,
    clock       = 0xFFFAFCFF,
    risk        = 0xFFFF7A73,
    warn        = 0xFFF7C75C,
    safe        = 0xFF8CD99E,
};

local BAR_FILL = {
    normal = { 0.36, 0.72, 0.52, 0.95 },
    warn   = { 0.88, 0.70, 0.24, 0.95 },
    low    = { 0.88, 0.36, 0.32, 0.95 },
    bust   = { 0.75, 0.36, 0.32, 0.95 },
};

local BAR_BACKDROP = { 0.10, 0.11, 0.13, 0.80 };
local BAR_BORDER = { 0, 0, 0, 1 };

local function FormatClock(seconds)
    if seconds == nil then return ''; end
    if seconds < 0 then return '--:--'; end

    local whole = math.floor(seconds);
    return string.format('%d:%02d', math.floor(whole / 60), whole % 60);
end

local function FormatSeconds(seconds)
    if seconds == nil or seconds < 0 then return ''; end
    return tostring(math.floor(seconds));
end

local function BarFill(seconds)
    if seconds == nil or seconds < 0 then return BAR_FILL.normal; end
    if seconds <= 30 then return BAR_FILL.low; end
    if seconds <= 60 then return BAR_FILL.warn; end
    return BAR_FILL.normal;
end

-- Bust % only while Double-Up is up; unlucky is visible on the die itself.
local function OddsText(entry, canDoubleUp)
    if entry.busted then return 'BUSTED', TEXT.risk; end
    if not canDoubleUp or entry.total == nil then return '', TEXT.muted; end

    local bust = data.BustChance(entry.total);
    if bust <= 0 then return 'Safe', TEXT.safe; end

    return string.format('Bust %d%%', math.floor(bust * 100 + 0.5)),
        (bust >= 0.5) and TEXT.risk or TEXT.warn;
end

local function DieStyle(entry, roll)
    if entry.busted then return 'bust'; end
    if data.IsLucky(roll, entry.total) then return 'hot'; end
    if data.IsUnlucky(roll, entry.total) then return 'cold'; end
    return 'normal';
end

local function BuildColumn(entry, horizonMode, canDoubleUp, doubleUpSeconds)
    local roll = data.ByAbility(entry.ability, horizonMode);
    local style = DieStyle(entry, roll);
    local seconds = tracker.SecondsLeft(entry);
    local oddsText, oddsColor = OddsText(entry, canDoubleUp);
    local oddsTimer = (canDoubleUp and oddsText ~= '') and FormatSeconds(doubleUpSeconds) or '';

    local nameColor, potencyColor = TEXT.label, TEXT.potency;
    if style == 'bust' then
        potencyColor = TEXT.potencyBust;
    elseif style == 'hot' then
        nameColor, potencyColor = TEXT.labelHot, TEXT.potencyHot;
    elseif style == 'cold' then
        nameColor, potencyColor = TEXT.labelCold, TEXT.potencyCold;
    end

    local duration = math.max(entry.duration or data.BASE_DURATION, 1);
    local fraction = (seconds ~= nil) and math.min(1, math.max(0, seconds / duration)) or 0;

    return {
        name = (roll and roll.name or (entry.busted and 'Bust' or '?')):upper(),
        potency = data.PotencyText(roll, entry.total, entry.context or data.Context(horizonMode)),
        odds = oddsText,
        oddsTimer = oddsTimer,
        clock = FormatClock(seconds),
        fraction = fraction,
        state = { total = entry.total, style = style },
        nameColor = nameColor,
        potencyColor = potencyColor,
        oddsColor = oddsColor,
        fill = (style == 'bust') and BAR_FILL.bust or BarFill(seconds),
    };
end

-- 4.3+ handles clip pushes on the shared draw list fine; older builds (4.16)
-- run the whole UI away, so they use a clip-free fill (accepts a tiny bleed).
local IS_ASHITA_43 = (ashita.interface_version or 0) >= 4.3;

local function DrawBar(drawList, x, y, width, height, column)
    local rounding = height * 0.45;
    drawList:AddRectFilled({ x, y }, { x + width, y + height },
        dice.Color(BAR_BACKDROP), rounding);

    if column.fraction > 0 then
        local inset = 1;
        local innerRounding = math.max(0, rounding - inset);
        if IS_ASHITA_43 then
            -- Clip so the fill stays inside the track at start/finish.
            local fillRight = x + math.max(inset, width * column.fraction - inset);
            drawList:PushClipRect({ x + inset, y + inset }, { fillRight, y + height - inset }, true);
            drawList:AddRectFilled({ x + inset, y + inset }, { x + width - inset, y + height - inset },
                dice.Color(column.fill), innerRounding);
            drawList:PopClipRect();
        else
            local fillRight = x + math.max(inset * 2, width * column.fraction);
            drawList:AddRectFilled({ x + inset, y + inset }, { fillRight - inset, y + height - inset },
                dice.Color(column.fill), innerRounding, ImDrawCornerFlags_Left);
        end
    end

    -- Same idea as player/target bars: a thin stroke around the fill.
    drawList:AddRect({ x, y }, { x + width, y + height },
        dice.Color(BAR_BORDER), rounding, 15, 1.0);

    dice.CenteredText(drawList, column.clock, x + width / 2, y + height / 2,
        height * 0.86, TEXT.clock);
end

M.DrawWindow = function(settings)
    local dieSize = settings.dieSize;
    local gap = dieSize * 0.50;
    local rowGap = dieSize * 0.09;
    local nameGap = dieSize * 0.30;      -- clears flame tips above the die
    local iceHeadroom = dieSize * 0.32;  -- room for icicles below

    imtext.SetConfigFromSettings(settings.font_settings);

    local slots = tracker.Slots();
    local doubleUpIndex, doubleUpSeconds = tracker.DoubleUp();

    local columns = {};
    local columnWidth = dieSize * 1.35;
    local oddsGap = settings.oddsSize * 0.45;

    for i = 1, 2 do
        if slots[i] ~= nil then
            columns[#columns + 1] = BuildColumn(
                slots[i], settings.horizonMode, i == doubleUpIndex, doubleUpSeconds);
        end
    end

    local count = #columns;
    if count == 0 then return; end

    local contentWidth = columnWidth * count + gap * (count - 1);
    local contentHeight = settings.nameSize + nameGap + dieSize + iceHeadroom
        + rowGap + settings.potencySize + rowGap + settings.barHeight + rowGap + settings.oddsSize;

    imgui.SetNextWindowSize({ -1, -1 }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });

    ApplyWindowPosition(WINDOW_NAME);
    if imgui.Begin(WINDOW_NAME, true, GetBaseWindowFlags(gConfig.lockPositions)) then
        SaveWindowPosition(WINDOW_NAME);

        local originX, originY = imgui.GetCursorScreenPos();
        imgui.Dummy({ contentWidth, contentHeight });

        local drawList = GetUIDrawList();
        local clock = os.clock();

        for i = 1, count do
            local column = columns[i];
            local centerX = originX + (i - 1) * (columnWidth + gap) + columnWidth / 2;
            local y = originY;

            dice.CenteredText(drawList, column.name, centerX, y + settings.nameSize / 2,
                settings.nameSize, column.nameColor);
            y = y + settings.nameSize + nameGap;

            dice.Draw(drawList, centerX - dieSize / 2, y, dieSize, column.state, clock,
                settings.font_settings);
            y = y + dieSize + iceHeadroom + rowGap;

            dice.CenteredText(drawList, column.potency, centerX, y + settings.potencySize / 2,
                settings.potencySize, column.potencyColor);
            y = y + settings.potencySize + rowGap;

            DrawBar(drawList, centerX - columnWidth / 2, y, columnWidth, settings.barHeight, column);
            y = y + settings.barHeight + rowGap;

            if column.odds ~= '' then
                local oddsY = y + settings.oddsSize / 2;
                if column.oddsTimer ~= '' then
                    local oddsW = imtext.Measure(column.odds, settings.oddsSize);
                    local timerW = imtext.Measure(column.oddsTimer, settings.oddsSize);
                    local totalW = oddsW + oddsGap + timerW;
                    local left = centerX - totalW / 2;
                    dice.CenteredText(drawList, column.odds, left + oddsW / 2, oddsY,
                        settings.oddsSize, column.oddsColor);
                    dice.CenteredText(drawList, column.oddsTimer, left + oddsW + oddsGap + timerW / 2,
                        oddsY, settings.oddsSize, TEXT.muted);
                else
                    dice.CenteredText(drawList, column.odds, centerX, oddsY,
                        settings.oddsSize, column.oddsColor);
                end
            end
        end
    end
    imgui.End();

    imgui.PopStyleVar();
end

M.ResetPositions = function()
    local defaultPositions = require('libs.defaultpositions');
    local x, y = defaultPositions.GetPhantomRollPosition();

    if gConfig and gConfig.windowPositions then
        gConfig.windowPositions[WINDOW_NAME] = { x = x, y = y };
        if gConfig.appliedPositions then
            gConfig.appliedPositions[WINDOW_NAME] = nil;
        end
    end
end

return M;
