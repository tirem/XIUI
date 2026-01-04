--[[
* XIUI Pet Bar - Display Module
* Handles rendering of the main pet bar window
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local progressbar = require('libs.progressbar');
local drawing = require('libs.drawing');

local data = require('modules.petbar.data');
local color = require('libs.color');

local display = {};

-- Window state for bottom alignment
local windowState = {
    x = nil,
    y = nil,
    height = nil,
};

-- Position saving state
local hasAppliedSavedPosition = false;
local lastSavedPosX = nil;
local lastSavedPosY = nil;

-- ============================================
-- Per-Pet-Type Settings Helpers
-- ============================================

-- Get the current pet type settings (e.g., gConfig.petBarAvatar)
local function GetPetTypeSettings()
    local petTypeKey = data.GetPetTypeKey();
    local settingsKey = 'petBar' .. petTypeKey:gsub("^%l", string.upper);  -- 'petBarAvatar', etc.
    return gConfig[settingsKey] or {};
end

-- Get the current pet type color config (e.g., gConfig.colorCustomization.petBarAvatar)
local function GetPetTypeColors()
    local petTypeKey = data.GetPetTypeKey();
    local settingsKey = 'petBar' .. petTypeKey:gsub("^%l", string.upper);  -- 'petBarAvatar', etc.
    if gConfig.colorCustomization and gConfig.colorCustomization[settingsKey] then
        return gConfig.colorCustomization[settingsKey];
    end
    -- Fall back to legacy petBar colors
    return gConfig.colorCustomization and gConfig.colorCustomization.petBar or {};
end

-- Helper to get a setting with fallback to per-type, then flat legacy, then default
local function GetPetBarSetting(settingName, defaultValue)
    local typeSettings = GetPetTypeSettings();
    if typeSettings[settingName] ~= nil then
        return typeSettings[settingName];
    end
    -- Fall back to legacy flat settings
    local legacyKey = 'petBar' .. settingName:gsub("^%l", string.upper);
    if gConfig[legacyKey] ~= nil then
        return gConfig[legacyKey];
    end
    return defaultValue;
end

-- ============================================
-- Get Timer Gradients Based on Individual Ability
-- ============================================
-- Each ability has its own unique gradient for better visual distinction
-- Returns: readyGradient, recastGradient (each is {start, stop} hex strings)
local function GetTimerGradients(abilityName, colorConfig)
    local name = abilityName or '';
    local cc = colorConfig or {};

    -- Default gradients
    local defaultReadyGradient = {'#aaaaaae6', '#cccccce6'};
    local defaultRecastGradient = {'#ccccccd9', '#ddddddd9'};

    -- Helper to get gradient as table
    local function getGradient(gradient, default)
        if gradient and gradient.start and gradient.stop then
            return {gradient.start, gradient.stop};
        end
        return default;
    end

    -- SMN abilities
    if name:find('Blood Pact') then
        if name:find('Rage') then
            return getGradient(cc.timerBPRageReadyGradient, {'#ff3333e6', '#ff6666e6'}),
                   getGradient(cc.timerBPRageRecastGradient, {'#ff6666d9', '#ff9999d9'});
        elseif name:find('Ward') then
            return getGradient(cc.timerBPWardReadyGradient, {'#00cccce6', '#66dddde6'}),
                   getGradient(cc.timerBPWardRecastGradient, {'#66ddddd9', '#99eeeed9'});
        end
        return getGradient(cc.timerBPRageReadyGradient, {'#ff3333e6', '#ff6666e6'}),
               getGradient(cc.timerBPRageRecastGradient, {'#ff6666d9', '#ff9999d9'});
    end
    if name == 'Apogee' then
        return getGradient(cc.timerApogeeReadyGradient, {'#ffcc00e6', '#ffdd66e6'}),
               getGradient(cc.timerApogeeRecastGradient, {'#ffdd66d9', '#ffee99d9'});
    end
    if name == 'Mana Cede' then
        return getGradient(cc.timerManaCedeReadyGradient, {'#009999e6', '#66bbbbe6'}),
               getGradient(cc.timerManaCedeRecastGradient, {'#66bbbbd9', '#99ccccd9'});
    end

    -- BST abilities
    if name == 'Ready' then
        return getGradient(cc.timerReadyReadyGradient, {'#ff6600e6', '#ff9933e6'}),
               getGradient(cc.timerReadyRecastGradient, {'#ff9933d9', '#ffbb66d9'});
    end
    if name == 'Reward' then
        return getGradient(cc.timerRewardReadyGradient, {'#00cc66e6', '#66dd99e6'}),
               getGradient(cc.timerRewardRecastGradient, {'#66dd99d9', '#99eebbd9'});
    end
    if name == 'Call Beast' then
        return getGradient(cc.timerCallBeastReadyGradient, {'#3399ffe6', '#66bbffe6'}),
               getGradient(cc.timerCallBeastRecastGradient, {'#66bbffd9', '#99ccffd9'});
    end
    if name == 'Bestial Loyalty' then
        return getGradient(cc.timerBestialLoyaltyReadyGradient, {'#9966ffe6', '#bb99ffe6'}),
               getGradient(cc.timerBestialLoyaltyRecastGradient, {'#bb99ffd9', '#ccaaffd9'});
    end

    -- DRG abilities
    if name == 'Call Wyvern' then
        return getGradient(cc.timerCallWyvernReadyGradient, {'#3366ffe6', '#6699ffe6'}),
               getGradient(cc.timerCallWyvernRecastGradient, {'#6699ffd9', '#99bbffd9'});
    end
    if name == 'Spirit Link' then
        return getGradient(cc.timerSpiritLinkReadyGradient, {'#33cc33e6', '#66dd66e6'}),
               getGradient(cc.timerSpiritLinkRecastGradient, {'#66dd66d9', '#99ee99d9'});
    end
    if name == 'Deep Breathing' then
        return getGradient(cc.timerDeepBreathingReadyGradient, {'#ffff33e6', '#ffff99e6'}),
               getGradient(cc.timerDeepBreathingRecastGradient, {'#ffff99d9', '#ffffc0d9'});
    end
    if name == 'Steady Wing' then
        return getGradient(cc.timerSteadyWingReadyGradient, {'#cc66ffe6', '#dd99ffe6'}),
               getGradient(cc.timerSteadyWingRecastGradient, {'#dd99ffd9', '#eeaaffd9'});
    end

    -- PUP abilities
    if name == 'Activate' then
        return getGradient(cc.timerActivateReadyGradient, {'#3399ffe6', '#66bbffe6'}),
               getGradient(cc.timerActivateRecastGradient, {'#66bbffd9', '#99ccffd9'});
    end
    if name == 'Repair' then
        return getGradient(cc.timerRepairReadyGradient, {'#33cc66e6', '#66dd99e6'}),
               getGradient(cc.timerRepairRecastGradient, {'#66dd99d9', '#99eebbd9'});
    end
    if name == 'Deploy' then
        return getGradient(cc.timerDeployReadyGradient, {'#ff9933e6', '#ffbb66e6'}),
               getGradient(cc.timerDeployRecastGradient, {'#ffbb66d9', '#ffcc99d9'});
    end
    if name == 'Deactivate' then
        return getGradient(cc.timerDeactivateReadyGradient, {'#999999e6', '#bbbbbbe6'}),
               getGradient(cc.timerDeactivateRecastGradient, {'#bbbbbbd9', '#ccccccd9'});
    end
    if name == 'Retrieve' then
        return getGradient(cc.timerRetrieveReadyGradient, {'#66ccffe6', '#99ddffe6'}),
               getGradient(cc.timerRetrieveRecastGradient, {'#99ddffd9', '#bbeeffd9'});
    end
    if name == 'Deus Ex Automata' then
        return getGradient(cc.timerDeusExAutomataReadyGradient, {'#ffcc33e6', '#ffdd66e6'}),
               getGradient(cc.timerDeusExAutomataRecastGradient, {'#ffdd66d9', '#ffee99d9'});
    end

    -- Two-Hour abilities
    if name == 'Astral Flow' or name == 'Familiar' or name == 'Spirit Surge' or name == 'Overdrive' then
        return getGradient(cc.timer2hReadyGradient, {'#ff00ffe6', '#ff66ffe6'}),
               getGradient(cc.timer2hRecastGradient, {'#ff66ffd9', '#ff99ffd9'});
    end

    -- Fallback for unknown abilities
    return defaultReadyGradient, defaultRecastGradient;
end

-- ============================================
-- Draw Recast Icon with configurable fill style (compact mode)
-- Styles: 'square' (vertical fill), 'circle' (radial fill), 'clock' (arc sweep, 4.3+ only)
-- ============================================
local function DrawRecastIcon(drawList, x, y, size, timerInfo, colorConfig, fillStyle)
    fillStyle = fillStyle or 'square';

    -- Get gradients based on ability category (use start color for compact mode)
    local readyGradient, recastGradient = GetTimerGradients(timerInfo.name, colorConfig);
    local bgColor = imgui.GetColorU32({0.01, 0.07, 0.17, 1.0});
    local borderColor = imgui.GetColorU32({0.01, 0.05, 0.12, 1.0});

    -- Calculate progress
    local progress = 1.0;
    local isOnCooldown = not timerInfo.isReady and timerInfo.timer > 0 and timerInfo.maxTimer and timerInfo.maxTimer > 0;
    if isOnCooldown then
        progress = 1.0 - (timerInfo.timer / timerInfo.maxTimer);
        progress = math.max(0, math.min(1, progress));
    end

    local fillColor = isOnCooldown
        and color.HexToU32(recastGradient[1])
        or color.HexToU32(readyGradient[1]);

    if fillStyle == 'circle' or fillStyle == 'clock' then
        -- Circle-based styles
        local radius = size / 2;
        local centerX = x + radius;
        local centerY = y + radius;
        local innerRadius = radius - 2;

        -- Background circle
        drawList:AddCircleFilled({centerX, centerY}, radius, bgColor, 32);

        if isOnCooldown then
            if progress > 0 then
                if fillStyle == 'clock' and drawList.PathClear then
                    -- Clock sweep (arc) - only available on Ashita 4.3+
                    local startAngle = -math.pi / 2;
                    local endAngle = startAngle + (progress * 2 * math.pi);
                    drawList:PathClear();
                    drawList:PathLineTo({centerX, centerY});
                    local numSegments = math.max(3, math.floor(32 * progress));
                    drawList:PathArcTo({centerX, centerY}, innerRadius, startAngle, endAngle, numSegments);
                    drawList:PathFillConvex(fillColor);
                else
                    -- Circle fill (fallback for clock on 4.0, or explicit circle style)
                    drawList:AddCircleFilled({centerX, centerY}, innerRadius * progress, fillColor, 32);
                end
            end
        else
            -- Ready state - full circle
            drawList:AddCircleFilled({centerX, centerY}, innerRadius, fillColor, 32);
        end

        -- Border circle
        drawList:AddCircle({centerX, centerY}, radius, borderColor, 32, 2);
    else
        -- Square style (vertical fill from bottom to top)
        local rounding = 4;
        local padding = 2;

        -- Background
        drawList:AddRectFilled({x, y}, {x + size, y + size}, bgColor, rounding);

        -- Inner area
        local innerX = x + padding;
        local innerY = y + padding;
        local innerSize = size - (padding * 2);

        if isOnCooldown then
            if progress > 0 then
                local fillHeight = innerSize * progress;
                local fillTop = innerY + innerSize - fillHeight;
                drawList:AddRectFilled({innerX, fillTop}, {innerX + innerSize, innerY + innerSize}, fillColor, rounding - 1);
            end
        else
            -- Ready state - full square
            drawList:AddRectFilled({innerX, innerY}, {innerX + innerSize, innerY + innerSize}, fillColor, rounding - 1);
        end

        -- Border
        drawList:AddRect({x, y}, {x + size, y + size}, borderColor, rounding, nil, 1.5);
    end
end

-- ============================================
-- Draw Recast Icons for Charge Abilities (compact mode)
-- Draws multiple smaller icons representing charges
-- Returns total width consumed
-- ============================================
local function DrawRecastIconCharged(drawList, x, y, size, timerInfo, colorConfig, fillStyle)
    fillStyle = fillStyle or 'square';

    local charges = timerInfo.charges or 0;
    local maxCharges = timerInfo.maxCharges or 3;
    local nextChargeTimer = timerInfo.nextChargeTimer or 0;

    -- Get gradients based on ability category
    local readyGradient, recastGradient = GetTimerGradients(timerInfo.name, colorConfig);
    local bgColor = imgui.GetColorU32({0.01, 0.07, 0.17, 1.0});
    local borderColor = imgui.GetColorU32({0.01, 0.05, 0.12, 1.0});

    local readyColor = color.HexToU32(readyGradient[1]);
    local recastColor = color.HexToU32(recastGradient[1]);

    -- Size for each charge icon (same size as normal icons)
    local chargeSize = size;
    local chargeSpacing = 4;
    local rounding = 3;
    local padding = 2;

    for i = 1, maxCharges do
        local chargeX = x + (i - 1) * (chargeSize + chargeSpacing);

        if fillStyle == 'circle' or fillStyle == 'clock' then
            -- Circle style for charges
            local radius = chargeSize / 2;
            local centerX = chargeX + radius;
            local centerY = y + radius;
            local innerRadius = radius - 2;

            -- Background circle
            drawList:AddCircleFilled({centerX, centerY}, radius, bgColor, 24);

            if i <= charges then
                -- Full charge available
                drawList:AddCircleFilled({centerX, centerY}, innerRadius, readyColor, 24);
            elseif i == charges + 1 and nextChargeTimer > 0 then
                -- Recharging charge - show progress
                local progress = 1.0 - (nextChargeTimer / data.READY_BASE_RECAST);
                progress = math.max(0, math.min(1, progress));

                if fillStyle == 'clock' and drawList.PathClear then
                    -- Clock sweep arc
                    local startAngle = -math.pi / 2;
                    local endAngle = startAngle + (progress * 2 * math.pi);
                    drawList:PathClear();
                    drawList:PathLineTo({centerX, centerY});
                    local numSegments = math.max(3, math.floor(24 * progress));
                    drawList:PathArcTo({centerX, centerY}, innerRadius, startAngle, endAngle, numSegments);
                    drawList:PathFillConvex(recastColor);
                else
                    -- Circle fill
                    drawList:AddCircleFilled({centerX, centerY}, innerRadius * progress, recastColor, 24);
                end
            end
            -- Empty charges get no fill (just background)

            -- Border circle
            drawList:AddCircle({centerX, centerY}, radius, borderColor, 24, 1.5);
        else
            -- Square style for charges
            -- Background
            drawList:AddRectFilled({chargeX, y}, {chargeX + chargeSize, y + chargeSize}, bgColor, rounding);

            -- Inner area
            local innerX = chargeX + padding;
            local innerY = y + padding;
            local innerSize = chargeSize - (padding * 2);

            if i <= charges then
                -- Full charge available
                drawList:AddRectFilled({innerX, innerY}, {innerX + innerSize, innerY + innerSize}, readyColor, rounding - 1);
            elseif i == charges + 1 and nextChargeTimer > 0 then
                -- Recharging charge - show progress (vertical fill)
                local progress = 1.0 - (nextChargeTimer / data.READY_BASE_RECAST);
                progress = math.max(0, math.min(1, progress));

                if progress > 0 then
                    local fillHeight = innerSize * progress;
                    local fillTop = innerY + innerSize - fillHeight;
                    drawList:AddRectFilled({innerX, fillTop}, {innerX + innerSize, innerY + innerSize}, recastColor, rounding - 1);
                end
            end
            -- Empty charges get no fill (just background)

            -- Border
            drawList:AddRect({chargeX, y}, {chargeX + chargeSize, y + chargeSize}, borderColor, rounding, nil, 1.5);
        end
    end

    -- Return total width consumed
    return maxCharges * chargeSize + (maxCharges - 1) * chargeSpacing;
end

-- ============================================
-- Format recast time for display
-- rawTimer is in 60ths of a second (60 units = 1 second)
-- ============================================
local function FormatRecastTime(rawTimer)
    local seconds = rawTimer / 60;
    if seconds <= 0 then
        return 'Ready';
    elseif seconds < 60 then
        return string.format('%ds', math.ceil(seconds));
    else
        local mins = math.floor(seconds / 60);
        local secs = math.ceil(seconds % 60);
        if secs == 60 then
            mins = mins + 1;
            secs = 0;
        end
        return string.format('%d:%02d', mins, secs);
    end
end

-- ============================================
-- Draw Recast - Full Display Mode
-- Shows name and recast timer with progress bar using GdiFonts
-- fontIndex: 1-based index for which font slot to use
-- ============================================
local function DrawRecastFull(drawList, x, y, timerInfo, colorConfig, fullSettings, fontIndex)
    local showName = fullSettings.showName;
    local showRecast = fullSettings.showRecast;
    local nameFontSize = fullSettings.nameFontSize or 10;
    local recastFontSize = fullSettings.recastFontSize or 10;

    -- Get font objects from data module
    local nameFont = data.recastNameFonts and data.recastNameFonts[fontIndex];
    local recastFont = data.recastTimerFonts and data.recastTimerFonts[fontIndex];

    -- Get gradients based on ability category
    local readyGradient, recastGradient = GetTimerGradients(timerInfo.name, colorConfig);
    local barGradient = timerInfo.isReady and readyGradient or recastGradient;

    -- Get text color from gradient start (convert hex to ARGB for GdiFonts)
    local textColorHex = color.GetGradientTextColor(barGradient[1]);

    -- Prepare text content
    local nameText = timerInfo.name or 'Unknown';
    local recastText = FormatRecastTime(timerInfo.timer or 0);

    -- Calculate the max font size for vertical positioning
    local maxFontSize = 0;
    if showName then maxFontSize = math.max(maxFontSize, nameFontSize); end
    if showRecast then maxFontSize = math.max(maxFontSize, recastFontSize); end
    if maxFontSize == 0 then maxFontSize = 10; end

    -- Text Y position at top of row
    local textY = y;

    -- Hide fonts by default, will show if needed
    if nameFont then nameFont:set_visible(false); end
    if recastFont then recastFont:set_visible(false); end

    -- Calculate progress for bar (0 = just started cooldown, 1 = ready)
    local progress = 1.0;
    if not timerInfo.isReady and timerInfo.timer > 0 and timerInfo.maxTimer and timerInfo.maxTimer > 0 then
        progress = 1.0 - (timerInfo.timer / timerInfo.maxTimer);
        progress = math.max(0, math.min(1, progress));
    end

    -- Progress bar settings (configurable)
    local barHeight = fullSettings.barHeight or 4;
    local barWidth = fullSettings.barWidth or 150;
    local barY = textY + maxFontSize + 2;  -- Position below the text

    -- Track where text/bar should start
    local barStartX = x;

    -- Name - left-aligned at start of bar
    if showName and nameFont then
        nameFont:set_font_height(nameFontSize);
        nameFont:set_text(nameText);
        nameFont:set_position_x(barStartX);
        nameFont:set_position_y(textY);
        nameFont:set_font_color(textColorHex);
        nameFont:set_font_alignment(0); -- Left alignment
        nameFont:set_visible(true);
    end

    -- Recast timer - right-aligned at far right of progress bar
    if showRecast and recastFont then
        recastFont:set_font_height(recastFontSize);
        recastFont:set_text(recastText);
        recastFont:set_position_x(barStartX + barWidth);  -- Right edge of bar
        recastFont:set_position_y(textY);
        recastFont:set_font_color(textColorHex);
        recastFont:set_font_alignment(2); -- Right alignment
        recastFont:set_visible(true);
    end

    -- Draw progress bar using the progressbar library with custom drawList
    local showBookends = fullSettings.showBookends;
    if showBookends == nil then showBookends = false; end

    progressbar.ProgressBar(
        {{progress, barGradient}},
        {barWidth, barHeight},
        {
            decorate = showBookends,
            absolutePosition = {barStartX, barY},
            drawList = drawList,
        }
    )

    -- Return the bar height for layout purposes
    return barHeight;
end

-- ============================================
-- Draw Recast - Full Display Mode for Charge Abilities
-- Shows name and recast timer with 3 segmented progress bars
-- fontIndex: 1-based index for which font slot to use
-- ============================================
local function DrawRecastFullCharged(drawList, x, y, timerInfo, colorConfig, fullSettings, fontIndex)
    local showName = fullSettings.showName;
    local showRecast = fullSettings.showRecast;
    local nameFontSize = fullSettings.nameFontSize or 10;
    local recastFontSize = fullSettings.recastFontSize or 10;

    local charges = timerInfo.charges or 0;
    local maxCharges = timerInfo.maxCharges or 3;
    local nextChargeTimer = timerInfo.nextChargeTimer or 0;

    -- Get font objects from data module
    local nameFont = data.recastNameFonts and data.recastNameFonts[fontIndex];
    local recastFont = data.recastTimerFonts and data.recastTimerFonts[fontIndex];

    -- Get gradients based on ability category
    local readyGradient, recastGradient = GetTimerGradients(timerInfo.name, colorConfig);

    -- Determine text color based on charge state
    local barGradient = (charges > 0) and readyGradient or recastGradient;

    -- Get text color from gradient start (convert hex to ARGB for GdiFonts)
    local textColorHex = color.GetGradientTextColor(barGradient[1]);

    -- Prepare text content
    local nameText = timerInfo.name or 'Unknown';
    -- For charges, show "[charges]" or timer to next charge
    local recastText;
    if charges >= maxCharges then
        recastText = string.format('[%d]', charges);
    elseif charges > 0 then
        recastText = string.format('[%d] %s', charges, FormatRecastTime(nextChargeTimer));
    else
        recastText = FormatRecastTime(nextChargeTimer);
    end

    -- Calculate the max font size for vertical positioning
    local maxFontSize = 0;
    if showName then maxFontSize = math.max(maxFontSize, nameFontSize); end
    if showRecast then maxFontSize = math.max(maxFontSize, recastFontSize); end
    if maxFontSize == 0 then maxFontSize = 10; end

    -- Text Y position at top of row
    local textY = y;

    -- Hide fonts by default, will show if needed
    if nameFont then nameFont:set_visible(false); end
    if recastFont then recastFont:set_visible(false); end

    -- Progress bar settings (configurable)
    local barHeight = fullSettings.barHeight or 4;
    local barWidth = fullSettings.barWidth or 150;
    local barY = textY + maxFontSize + 2;  -- Position below the text

    -- Track where text/bar should start
    local barStartX = x;

    -- Name - left-aligned at start of bar
    if showName and nameFont then
        nameFont:set_font_height(nameFontSize);
        nameFont:set_text(nameText);
        nameFont:set_position_x(barStartX);
        nameFont:set_position_y(textY);
        nameFont:set_font_color(textColorHex);
        nameFont:set_font_alignment(0); -- Left alignment
        nameFont:set_visible(true);
    end

    -- Recast timer - right-aligned at far right of progress bar
    if showRecast and recastFont then
        recastFont:set_font_height(recastFontSize);
        recastFont:set_text(recastText);
        recastFont:set_position_x(barStartX + barWidth);  -- Right edge of bar
        recastFont:set_position_y(textY);
        recastFont:set_font_color(textColorHex);
        recastFont:set_font_alignment(2); -- Right alignment
        recastFont:set_visible(true);
    end

    -- Draw 3 segmented progress bars using progressbar library
    local showBookends = fullSettings.showBookends;
    if showBookends == nil then showBookends = false; end

    local segmentGap = 3;
    local totalGapWidth = (maxCharges - 1) * segmentGap;
    local segmentWidth = (barWidth - totalGapWidth) / maxCharges;

    for i = 1, maxCharges do
        local segmentX = barStartX + (i - 1) * (segmentWidth + segmentGap);

        local segmentProgress;
        local segmentGradient;

        if i <= charges then
            -- Full charge available
            segmentProgress = 1.0;
            segmentGradient = readyGradient;
        elseif i == charges + 1 and nextChargeTimer > 0 then
            -- Recharging charge - show progress
            segmentProgress = 1.0 - (nextChargeTimer / data.READY_BASE_RECAST);
            segmentProgress = math.max(0, math.min(1, segmentProgress));
            segmentGradient = recastGradient;
        else
            -- Empty charge
            segmentProgress = 0;
            segmentGradient = recastGradient;
        end

        progressbar.ProgressBar(
            {{segmentProgress, segmentGradient}},
            {segmentWidth, barHeight},
            {
                decorate = showBookends,
                absolutePosition = {segmentX, barY},
                drawList = drawList,
            }
        );
    end

    -- Return the bar height for layout purposes
    return barHeight;
end

-- ============================================
-- DrawWindow - Main Pet Bar Rendering
-- ============================================
function display.DrawWindow(settings)
    -- Get pet data from data module (handles preview internally)
    local petData = data.GetPetData();

    if petData == nil then
        data.currentPetName = nil;
        data.SetAllFontsVisible(false);
        data.HideBackground();
        -- Reset window state when hidden so bottom alignment starts fresh
        windowState.x = nil;
        windowState.y = nil;
        windowState.height = nil;
        return false;
    end

    -- Use petData directly - no preview checks needed
    local petName = petData.name;
    local petHpPercent = petData.hpPercent;
    local petDistance = petData.distance;
    local petMpPercent = petData.mpPercent;
    local petTp = petData.tp;
    local petJob = petData.job;
    local showMp = petData.showMp;
    -- New fields
    local petLevel = petData.level;
    local isJug = petData.isJug;
    local isCharmed = petData.isCharmed;
    local jugTimeRemaining = petData.jugTimeRemaining;
    local charmTimeRemaining = petData.charmTimeRemaining;

    -- Set current pet name for background image rendering
    data.currentPetName = petName;

    local petTpPercent = math.min(petTp / 1000, 1.0);

    -- Build window flags
    -- Only allow movement when config is open and preview is enabled (like partylist)
    local windowFlags = data.getBaseWindowFlags();
    if gConfig.lockPositions and not (showConfig[1] and gConfig.petBarPreview) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    -- Apply saved position on first render
    if not hasAppliedSavedPosition and gConfig.petBarWindowPosX ~= nil and gConfig.petBarWindowPosY ~= nil then
        imgui.SetNextWindowPos({gConfig.petBarWindowPosX, gConfig.petBarWindowPosY}, ImGuiCond_Once);
        hasAppliedSavedPosition = true;
        lastSavedPosX = gConfig.petBarWindowPosX;
        lastSavedPosY = gConfig.petBarWindowPosY;
    end

    -- Get per-pet-type settings and colors
    local typeSettings = GetPetTypeSettings();
    local colorConfig = GetPetTypeColors();

    -- Calculate dimensions (base values)
    local barWidth = settings.barWidth;
    local barHeight = settings.barHeight;
    local barSpacing = settings.barSpacing;

    -- Individual bar scales (from per-type settings with legacy fallback)
    local hpScaleX = typeSettings.hpScaleX or gConfig.petBarHpScaleX or 1.0;
    local hpScaleY = typeSettings.hpScaleY or gConfig.petBarHpScaleY or 1.0;
    local mpScaleX = typeSettings.mpScaleX or gConfig.petBarMpScaleX or 1.0;
    local mpScaleY = typeSettings.mpScaleY or gConfig.petBarMpScaleY or 1.0;
    local tpScaleX = typeSettings.tpScaleX or gConfig.petBarTpScaleX or 1.0;
    local tpScaleY = typeSettings.tpScaleY or gConfig.petBarTpScaleY or 1.0;
    local recastScaleX = typeSettings.recastScaleX or 1.0;
    local recastScaleY = typeSettings.recastScaleY or 0.5;  -- Default to half height for recast bars

    -- Calculate scaled bar dimensions
    -- HP bar is full width
    local hpBarWidth = barWidth * hpScaleX;
    local hpBarHeight = barHeight * hpScaleY;
    -- MP and TP bars split the HP bar width (minus spacing between them)
    local halfBarWidth = (hpBarWidth - barSpacing) / 2;
    local mpBarWidth = halfBarWidth * mpScaleX;
    local mpBarHeight = barHeight * mpScaleY;
    local tpBarWidth = halfBarWidth * tpScaleX;
    local tpBarHeight = barHeight * tpScaleY;
    -- Recast bars use full HP bar width by default, scaled height
    local recastBarWidth = hpBarWidth * recastScaleX;
    local recastBarHeight = barHeight * recastScaleY;

    -- Total row width for proper window sizing (based on HP bar width)
    local totalRowWidth = hpBarWidth;

    -- Store for pet target window
    data.lastTotalRowWidth = totalRowWidth;
    data.lastWindowFlags = windowFlags;
    data.lastColorConfig = colorConfig;
    data.lastSettings = settings;

    local windowPosX, windowPosY = 0, 0;

    if imgui.Begin('PetBar', true, windowFlags) then
        windowPosX, windowPosY = imgui.GetWindowPos();
        local startX, startY = imgui.GetCursorScreenPos();

        -- Row 1: Pet Name (with optional level) (left) and HP% (right, same line)
        local nameFontSize = typeSettings.nameFontSize or gConfig.petBarNameFontSize or settings.name_font_settings.font_height;
        local hpFontSize = typeSettings.hpFontSize or typeSettings.vitalsFontSize or gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;
        local mpFontSize = typeSettings.mpFontSize or typeSettings.vitalsFontSize or gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;
        local tpFontSize = typeSettings.tpFontSize or typeSettings.vitalsFontSize or gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;

        -- Format name with level if available and enabled
        local showLevel = typeSettings.showLevel;
        if showLevel == nil then showLevel = gConfig.petBarShowLevel ~= false; end
        local displayName = petName;
        if petLevel and showLevel then
            displayName = string.format('Lv.%d %s', petLevel, petName);
        end

        data.nameText:set_font_height(nameFontSize);
        data.nameText:set_text(displayName);
        data.nameText:set_position_x(startX);
        data.nameText:set_position_y(startY);
        local nameColor = colorConfig.nameTextColor or 0xFFFFFFFF;
        if data.lastNameColor ~= nameColor then
            data.nameText:set_font_color(nameColor);
            data.lastNameColor = nameColor;
        end
        data.nameText:set_visible(true);

        -- Distance text (anchored to top right edge of background)
        local showDistance = typeSettings.showDistance;
        if showDistance == nil then showDistance = gConfig.petBarShowDistance; end
        if showDistance then
            local distanceFontSize = typeSettings.distanceFontSize or gConfig.petBarDistanceFontSize or settings.distance_font_settings.font_height;
            local distanceOffsetX = typeSettings.distanceOffsetX or gConfig.petBarDistanceOffsetX or 0;
            local distanceOffsetY = typeSettings.distanceOffsetY or gConfig.petBarDistanceOffsetY or 0;

            data.distanceText:set_font_height(distanceFontSize);
            data.distanceText:set_text(string.format('%.1f', petDistance));
            data.distanceText:set_position_x(startX + totalRowWidth + distanceOffsetX);
            data.distanceText:set_position_y(windowPosY - 13 + distanceOffsetY);
            data.distanceText:set_font_alignment(2); -- Right alignment (text grows left)

            local distColor = colorConfig.distanceTextColor or 0xFFFFFFFF;
            if data.lastDistanceColor ~= distColor then
                data.distanceText:set_font_color(distColor);
                data.lastDistanceColor = distColor;
            end
            data.distanceText:set_visible(true);
        else
            data.distanceText:set_visible(false);
        end

        -- Per-type vitals toggles
        local showHP = typeSettings.showHP;
        if showHP == nil then showHP = gConfig.petBarShowVitals ~= false; end
        local showMP = typeSettings.showMP;
        if showMP == nil then showMP = gConfig.petBarShowVitals ~= false; end
        local showTP = typeSettings.showTP;
        if showTP == nil then showTP = gConfig.petBarShowVitals ~= false; end

        -- HP% text (right-aligned to HP bar width)
        if showHP then
            data.hpText:set_font_height(hpFontSize);
            data.hpText:set_text(tostring(petHpPercent) .. '%');
            data.hpText:set_position_x(startX + hpBarWidth);
            data.hpText:set_position_y(startY + (nameFontSize - hpFontSize) / 2);
            local hpColor = colorConfig.hpTextColor or 0xFFFFFFFF;
            if data.lastHpColor ~= hpColor then
                data.hpText:set_font_color(hpColor);
                data.lastHpColor = hpColor;
            end
            data.hpText:set_visible(true);
        else
            data.hpText:set_visible(false);
        end

        imgui.Dummy({totalRowWidth, nameFontSize + 4});

        -- Get bookends setting (shared across all bars)
        local showBookends = typeSettings.showBookends;
        if showBookends == nil then showBookends = gConfig.petBarShowBookends; end

        -- Combine pet capability (showMp from data) with user setting (showMP from config)
        local displayMpBar = showMp and showMP;
        local displayTpBar = showTP;

        -- Track bar positions for text placement
        local barsStartX, barsStartY = imgui.GetCursorScreenPos();
        local mpBarX, mpBarY = barsStartX, barsStartY;
        local tpBarX = barsStartX;
        local textRowY = barsStartY;

        -- Row 2: HP Bar (full width) with interpolation
        if showHP then
            local hpGradient = GetCustomGradient(colorConfig, 'hpGradient') or {'#e26c6c', '#fa9c9c'};

            -- Use HP interpolation for damage/healing animations (with nil check)
            local hpPercentData;
            if HpInterpolation and HpInterpolation.update then
                local currentTime = os.clock();
                local petEntity = data.GetPetEntity();
                local petIndex = petEntity and petEntity.TargetIndex or 0;
                hpPercentData = HpInterpolation.update('petbar', petHpPercent, petIndex, settings, currentTime, hpGradient);
            else
                -- Fallback: no interpolation
                hpPercentData = {{petHpPercent / 100, hpGradient}};
            end

            progressbar.ProgressBar(
                hpPercentData,
                {hpBarWidth, hpBarHeight},
                {decorate = showBookends}
            );

            -- Update position for next row
            mpBarX, mpBarY = imgui.GetCursorScreenPos();
            tpBarX = mpBarX;
        end

        -- Row 3: MP and TP bars side by side (half width each)
        -- Calculate actual widths based on what's displayed
        local actualMpWidth = mpBarWidth;
        local actualTpWidth = tpBarWidth;
        if displayMpBar and not displayTpBar then
            -- MP bar takes full width when no TP bar
            actualMpWidth = hpBarWidth;
        elseif not displayMpBar and displayTpBar then
            -- TP bar takes full width when no MP bar
            actualTpWidth = hpBarWidth;
        end

        if displayMpBar then
            local mpGradient = GetCustomGradient(colorConfig, 'mpGradient') or {'#9abb5a', '#bfe07d'};
            progressbar.ProgressBar(
                {{petMpPercent / 100, mpGradient}},
                {actualMpWidth, mpBarHeight},
                {decorate = showBookends}
            );

            if displayTpBar then
                imgui.SameLine(0, barSpacing);
                tpBarX = imgui.GetCursorScreenPos();
            end
        end

        if displayTpBar then
            local tpGradient = GetCustomGradient(colorConfig, 'tpGradient') or {'#3898ce', '#78c4ee'};
            progressbar.ProgressBar(
                {{petTpPercent, tpGradient}},
                {actualTpWidth, tpBarHeight},
                {decorate = showBookends}
            );
        end

        -- Calculate text Y positions based on respective bar heights
        -- When both bars are shown, use max height for consistent text alignment
        -- When only one bar is shown, use that bar's height
        local mpTextRowY = mpBarY;
        local tpTextRowY = mpBarY;
        if displayMpBar and displayTpBar then
            -- Both bars shown - align text at the same level using max height
            local maxBarHeight = math.max(mpBarHeight, tpBarHeight);
            mpTextRowY = mpBarY + maxBarHeight + 2;
            tpTextRowY = mpBarY + maxBarHeight + 2;
        elseif displayMpBar then
            -- Only MP bar shown
            mpTextRowY = mpBarY + mpBarHeight + 2;
        elseif displayTpBar then
            -- Only TP bar shown
            tpTextRowY = mpBarY + tpBarHeight + 2;
        end

        -- MP text (independent of TP bar visibility)
        if displayMpBar then
            data.mpText:set_font_height(mpFontSize);
            data.mpText:set_text(tostring(petMpPercent) .. '%');
            -- Right-align MP text under MP bar
            data.mpText:set_position_x(mpBarX + actualMpWidth);
            data.mpText:set_position_y(mpTextRowY);
            local mpColor = colorConfig.mpTextColor or 0xFFFFFFFF;
            if data.lastMpColor ~= mpColor then
                data.mpText:set_font_color(mpColor);
                data.lastMpColor = mpColor;
            end
            data.mpText:set_visible(true);
        else
            data.mpText:set_visible(false);
        end

        -- TP text (independent of MP bar visibility)
        if displayTpBar then
            data.tpText:set_font_height(tpFontSize);
            data.tpText:set_text(tostring(petTp));
            -- Right-align TP text under TP bar
            data.tpText:set_position_x(tpBarX + actualTpWidth);
            data.tpText:set_position_y(tpTextRowY);
            local tpColor = colorConfig.tpTextColor or 0xFFFFFFFF;
            if data.lastTpColor ~= tpColor then
                data.tpText:set_font_color(tpColor);
                data.lastTpColor = tpColor;
            end
            data.tpText:set_visible(true);
        else
            data.tpText:set_visible(false);
        end

        -- Add spacing for text row if any vitals text is shown
        -- recastTopSpacing controls the gap between vitals text and recast section (anchored mode)
        local recastTopSpacing = typeSettings.recastTopSpacing or 2;
        if displayMpBar or displayTpBar then
            local maxVitalsFontSize = math.max(displayMpBar and mpFontSize or 0, displayTpBar and tpFontSize or 0);
            imgui.Dummy({totalRowWidth, maxVitalsFontSize + recastTopSpacing});
        end

        -- Row 4: Ability Icons
        local showTimers = typeSettings.showTimers;
        if showTimers == nil then showTimers = gConfig.petBarShowTimers ~= false; end

        -- Helper to hide all recast fonts
        local function hideAllRecastFonts()
            for i = 1, data.MAX_RECAST_SLOTS do
                if data.recastNameFonts and data.recastNameFonts[i] then
                    data.recastNameFonts[i]:set_visible(false);
                end
                if data.recastTimerFonts and data.recastTimerFonts[i] then
                    data.recastTimerFonts[i]:set_visible(false);
                end
            end
        end

        if showTimers then
            -- Get recasts from data module (handles preview internally)
            local timers = data.GetPetRecasts();
            if #timers > 0 then
                local iconOffsetX = typeSettings.iconsOffsetX or gConfig.petBarIconsOffsetX or 0;
                local iconOffsetY = typeSettings.iconsOffsetY or gConfig.petBarIconsOffsetY or 0;
                local iconsAbsolute = typeSettings.iconsAbsolute;
                if iconsAbsolute == nil then iconsAbsolute = gConfig.petBarIconsAbsolute; end
                local fillStyle = typeSettings.timerFillStyle or 'square';
                local displayStyle = typeSettings.recastDisplayStyle or 'compact';
                -- Scale only applies to compact mode; full mode always uses 1.0
                local iconScale = (displayStyle == 'full') and 1.0 or (typeSettings.iconsScale or gConfig.petBarIconsScale or 1.0);
                local scaledIconSize = data.RECAST_ICON_SIZE * iconScale;
                local iconSpacing = typeSettings.recastFullSpacing or 4;

                local iconX, iconY;
                local drawList;

                if iconsAbsolute then
                    -- Absolute positioning: relative to window top-left
                    iconX = windowPosX + iconOffsetX;
                    iconY = windowPosY + iconOffsetY;
                    -- Use UI draw list for consistent rendering
                    drawList = drawing.GetUIDrawList();
                else
                    -- Anchored: flow within the pet bar container
                    -- Use recastTopSpacing for vertical offset, no X offset in anchored mode
                    local topSpacing = typeSettings.recastTopSpacing or 2;
                    iconX, iconY = imgui.GetCursorScreenPos();
                    iconY = iconY + topSpacing;
                    -- Use UI draw list for consistent rendering
                    drawList = drawing.GetUIDrawList();
                end

                if displayStyle == 'full' then
                    -- Full display: vertical list with name and recast timer
                    -- Note: Alignment is forced to 'left' for full mode - right alignment
                    -- doesn't work properly with the stacked vertical layout
                    local recastShowBookends = typeSettings.showBookends;
                    if recastShowBookends == nil then recastShowBookends = gConfig.petBarShowBookends; end

                    local fullSettings = {
                        showName = typeSettings.recastFullShowName ~= false,
                        showRecast = typeSettings.recastFullShowTimer ~= false,
                        nameFontSize = typeSettings.recastFullNameFontSize or 10,
                        recastFontSize = typeSettings.recastFullTimerFontSize or 10,
                        alignment = 'left',
                        iconSize = scaledIconSize,
                        barWidth = recastBarWidth,
                        barHeight = recastBarHeight,
                        showBookends = recastShowBookends,
                    };

                    -- Calculate row height based on what's visible
                    -- Text row height
                    local textRowHeight = 0;
                    if fullSettings.showName then
                        textRowHeight = math.max(textRowHeight, fullSettings.nameFontSize);
                    end
                    if fullSettings.showRecast then
                        textRowHeight = math.max(textRowHeight, fullSettings.recastFontSize);
                    end
                    -- Entry height = text row + gap + bar height
                    local textBarGap = 2;
                    local contentHeight = textRowHeight + textBarGap + recastBarHeight;
                    -- If nothing visible (no text), just use bar height
                    if textRowHeight == 0 then
                        contentHeight = recastBarHeight;
                    end
                    local rowHeight = contentHeight + iconSpacing;

                    for i, timerInfo in ipairs(timers) do
                        if i > data.MAX_RECAST_SLOTS then break; end

                        local posY = iconY + (i - 1) * rowHeight;
                        if timerInfo.isChargeAbility then
                            DrawRecastFullCharged(drawList, iconX, posY, timerInfo, colorConfig, fullSettings, i);
                        else
                            DrawRecastFull(drawList, iconX, posY, timerInfo, colorConfig, fullSettings, i);
                        end
                    end

                    -- Hide unused font slots
                    for i = #timers + 1, data.MAX_RECAST_SLOTS do
                        if data.recastNameFonts and data.recastNameFonts[i] then
                            data.recastNameFonts[i]:set_visible(false);
                        end
                        if data.recastTimerFonts and data.recastTimerFonts[i] then
                            data.recastTimerFonts[i]:set_visible(false);
                        end
                    end

                    if not iconsAbsolute then
                        -- Only add spacing between rows, not after the last row
                        local totalHeight = #timers * contentHeight + math.max(0, #timers - 1) * iconSpacing;
                        imgui.Dummy({totalRowWidth, totalHeight});
                    end
                else
                    -- Compact display: horizontal row of icons only
                    -- Hide all full display fonts when in compact mode
                    for i = 1, data.MAX_RECAST_SLOTS do
                        if data.recastNameFonts and data.recastNameFonts[i] then
                            data.recastNameFonts[i]:set_visible(false);
                        end
                        if data.recastTimerFonts and data.recastTimerFonts[i] then
                            data.recastTimerFonts[i]:set_visible(false);
                        end
                    end

                    local compactSpacing = 4 * iconScale;
                    local currentX = iconX;

                    for i, timerInfo in ipairs(timers) do
                        if i > data.MAX_RECAST_SLOTS then break; end

                        if timerInfo.isChargeAbility then
                            -- Draw multiple charge icons
                            local chargeWidth = DrawRecastIconCharged(drawList, currentX, iconY, scaledIconSize, timerInfo, colorConfig, fillStyle);
                            currentX = currentX + chargeWidth + compactSpacing;
                        else
                            -- Draw single normal icon
                            DrawRecastIcon(drawList, currentX, iconY, scaledIconSize, timerInfo, colorConfig, fillStyle);
                            currentX = currentX + scaledIconSize + compactSpacing;
                        end
                    end

                    if not iconsAbsolute then
                        imgui.Dummy({totalRowWidth, scaledIconSize});
                    end
                end
            else
                -- No timers to display, hide all fonts
                hideAllRecastFonts();
            end
        else
            -- Timers disabled, hide all fonts
            hideAllRecastFonts();
        end

        -- BST Pet Timer Display (Jug countdown or Charm elapsed)
        local showJugTimer = isJug and gConfig.petBarShowJugTimer ~= false and jugTimeRemaining;
        local showCharmTimer = isCharmed and gConfig.petBarShowCharmIndicator ~= false;

        if showJugTimer or showCharmTimer then
            local drawList = drawing.GetUIDrawList();

            -- Get timer text for positioning
            local timerStr = nil;
            local textColor = colorConfig.charmTimerColor or 0xFFFFFFFF;
            local iconSize, timerX, timerY, timerFontSize;

            if showJugTimer then
                -- Jug-specific settings
                iconSize = gConfig.petBarJugIconSize or 16;
                local offsetX = gConfig.petBarJugOffsetX or 0;
                local offsetY = gConfig.petBarJugOffsetY or -20;
                timerFontSize = gConfig.petBarJugTimerFontSize or 12;
                timerX = windowPosX + offsetX;
                timerY = windowPosY + offsetY;

                timerStr = data.FormatTimeMMSS(jugTimeRemaining);
                -- Warning color if under 5 minutes
                if jugTimeRemaining and jugTimeRemaining < 300 then
                    textColor = colorConfig.durationWarningColor or 0xFFFF6600;
                end

                -- Draw jug icon using texture
                if data.jugIconTexture and data.jugIconTexture.image then
                    local jugColor = color.ARGBToU32(colorConfig.jugIconColor or 0xFFFFFFFF);
                    drawList:AddImage(
                        tonumber(ffi.cast("uint32_t", data.jugIconTexture.image)),
                        {timerX, timerY},
                        {timerX + iconSize, timerY + iconSize},
                        {0, 0}, {1, 1},
                        jugColor
                    );
                end
            elseif showCharmTimer then
                -- Charm-specific settings
                iconSize = gConfig.petBarCharmIconSize or 16;
                local offsetX = gConfig.petBarCharmOffsetX or 0;
                local offsetY = gConfig.petBarCharmOffsetY or -20;
                timerFontSize = gConfig.petBarCharmTimerFontSize or 12;
                timerX = windowPosX + offsetX;
                timerY = windowPosY + offsetY;

                if charmTimeRemaining then
                    timerStr = data.FormatTimeMMSS(charmTimeRemaining);
                    -- Warning color if under 30 seconds
                    if charmTimeRemaining < 30 then
                         textColor = colorConfig.durationWarningColor or 0xFFFF6600;
                    end
                else
                    timerStr = "??:??";
                end

                -- Charmed pet: Show heart icon
                local heartColor = color.ARGBToU32(colorConfig.charmHeartColor or 0xFFFF6699);

                -- Draw heart shape using filled triangles/circles
                local centerX = timerX + iconSize / 2;
                local centerY = timerY + iconSize / 2;
                local halfSize = iconSize / 2;

                -- Heart is made of two circles and a triangle
                local circleRadius = halfSize * 0.5;
                local circleY = centerY - circleRadius * 0.3;
                drawList:AddCircleFilled({centerX - circleRadius * 0.6, circleY}, circleRadius, heartColor, 16);
                drawList:AddCircleFilled({centerX + circleRadius * 0.6, circleY}, circleRadius, heartColor, 16);
                -- Triangle for bottom of heart
                drawList:AddTriangleFilled(
                    {centerX - halfSize * 0.9, centerY - circleRadius * 0.2},
                    {centerX + halfSize * 0.9, centerY - circleRadius * 0.2},
                    {centerX, centerY + halfSize * 0.8},
                    heartColor
                );
            end

            -- Draw timer text using GDI font
            if timerStr and data.bstTimerText then
                local textX = timerX + iconSize + 1;
                local textY = timerY + (iconSize - timerFontSize) / 2;
                data.bstTimerText:set_font_height(timerFontSize);
                data.bstTimerText:set_text(timerStr);
                data.bstTimerText:set_position_x(textX);
                data.bstTimerText:set_position_y(textY);
                if data.lastBstTimerColor ~= textColor then
                    data.bstTimerText:set_font_color(textColor);
                    data.lastBstTimerColor = textColor;
                end
                data.bstTimerText:set_visible(true);
            else
                if data.bstTimerText then
                    data.bstTimerText:set_visible(false);
                end
            end
        else
            -- Hide BST timer text when not showing
            if data.bstTimerText then
                data.bstTimerText:set_visible(false);
            end
        end

        -- Get final window size for background
        local windowWidth, windowHeight = imgui.GetWindowSize();

        -- Handle bottom alignment
        if typeSettings.alignBottom then
            if windowState.height ~= nil and windowState.height ~= windowHeight then
                -- Height changed, adjust Y to keep bottom edge fixed
                local newPosY = windowState.y + windowState.height - windowHeight;
                imgui.SetWindowPos('PetBar', { windowPosX, newPosY });
                windowPosY = newPosY;
            end

            -- Save current state
            windowState.x = windowPosX;
            windowState.y = windowPosY;
            windowState.height = windowHeight;
        end

        -- Store main window position for pet target window
        data.lastMainWindowPosX = windowPosX;
        data.lastMainWindowBottom = windowPosY + windowHeight + 4;

        -- Update background primitives
        data.UpdateBackground(windowPosX, windowPosY, windowWidth, windowHeight, settings);

        -- Save position when user moves window (check on mouse release)
        local canMove = not gConfig.lockPositions or (showConfig[1] and gConfig.petBarPreview);
        if canMove then
            -- Only save if position changed significantly (avoid floating point noise)
            local posChanged = (lastSavedPosX == nil or lastSavedPosY == nil) or
                               (math.abs(windowPosX - lastSavedPosX) > 1) or
                               (math.abs(windowPosY - lastSavedPosY) > 1);
            if posChanged and not imgui.IsMouseDown(0) then
                -- Mouse released and position changed - save to settings
                gConfig.petBarWindowPosX = windowPosX;
                gConfig.petBarWindowPosY = windowPosY;
                lastSavedPosX = windowPosX;
                lastSavedPosY = windowPosY;
                if SaveSettingsToDisk then
                    SaveSettingsToDisk();
                end
            end
        end
    end
    imgui.End();

    return true;  -- Pet exists (or preview mode), target window can render
end

return display;
