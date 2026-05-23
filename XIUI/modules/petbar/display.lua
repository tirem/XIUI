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
local imtext = require('libs.imtext');
local statusIcons = require('libs.statusicons');
local statusHandler = require('handlers.statushandler');
local buffTable = require('libs.bufftable');

local data = require('modules.petbar.data');
local color = require('libs.color');
local defaultPositions = require('libs.defaultpositions');

local display = {};

-- Window state for bottom alignment + previous-frame size cache (used for bg layering).
-- anchorBottom: locked screen Y of the window bottom edge while petBarResizeAnchor='bottom'
-- and AlwaysAutoResize is on. Stable across +/-1px height steps that the old
-- "delta > 1px" gate skipped, which caused the window to crawl upward over time.
local windowState = {
    x = nil,
    y = nil,
    height = nil,
    anchorBottom = nil,
    cachedWidth = nil,
    cachedHeight = nil,
};

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
    if name == 'Ready' or name == 'Sic' then
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
    local chargeValue = timerInfo.chargeValue or 1800;  -- Default 30s per charge (in 1/60ths)

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
                local progress = 1.0 - (nextChargeTimer / chargeValue);
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
                local progress = 1.0 - (nextChargeTimer / chargeValue);
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
-- Shows name and recast timer with progress bar
-- fontIndex: 1-based index for which font slot to use
-- ============================================
local function DrawRecastFull(drawList, x, y, timerInfo, colorConfig, fullSettings, fontIndex)
    local showName = fullSettings.showName;
    local showRecast = fullSettings.showRecast;
    local nameFontSize = fullSettings.nameFontSize or 10;
    local recastFontSize = fullSettings.recastFontSize or 10;
    local progressStyle = fullSettings.progressStyle or 'Fill';

    -- Jug Pet 'Ready' exception: Always Fill
    if fullSettings.isJug and timerInfo.name == 'Ready' then
        progressStyle = 'Fill';
    end

    -- Get gradients based on ability category
    local readyGradient, recastGradient = GetTimerGradients(timerInfo.name, colorConfig);
    local barGradient = timerInfo.isReady and readyGradient or recastGradient;

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

    -- Calculate progress
    local progress = 1.0;
    
    if timerInfo.isReady then
        progress = 1.0; -- Always full when ready
    elseif timerInfo.timer > 0 and timerInfo.maxTimer and timerInfo.maxTimer > 0 then
        progress = 1.0 - (timerInfo.timer / timerInfo.maxTimer);
        progress = math.max(0, math.min(1, progress));
        
        -- Handle Deplete style (invert progress only during cooldown)
        if progressStyle == 'Deplete' then
            progress = 1.0 - progress;
        end
    end

    -- Progress bar settings (configurable)
    local barHeight = fullSettings.barHeight or 4;
    local barWidth = fullSettings.barWidth or 150;
    local barY = textY + maxFontSize + (fullSettings.textBarGap or 2);  -- Position below the text

    -- Track where text/bar should start
    local barStartX = x;

    -- Name - left-aligned at start of bar
    if showName then
        imtext.Draw(drawList, nameText, barStartX, textY, textColorHex, nameFontSize);
    end

    -- Recast timer - right-aligned at far right of progress bar
    if showRecast then
        local recastW = imtext.Measure(recastText, recastFontSize);
        imtext.Draw(drawList, recastText, barStartX + barWidth - recastW, textY, textColorHex, recastFontSize);
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
            fillDirection = pbFill,
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
    local progressStyle = fullSettings.progressStyle or 'Fill';

    -- Jug Pet 'Ready' exception: Always Fill
    if fullSettings.isJug and timerInfo.name == 'Ready' then
        progressStyle = 'Fill';
    end

    local charges = timerInfo.charges or 0;
    local maxCharges = timerInfo.maxCharges or 3;
    local nextChargeTimer = timerInfo.nextChargeTimer or 0;
    local chargeValue = timerInfo.chargeValue or 1800;  -- Default 30s per charge (in 1/60ths)

    -- Get gradients based on ability category
    local readyGradient, recastGradient = GetTimerGradients(timerInfo.name, colorConfig);

    -- Determine text color based on charge state
    local barGradient = (charges > 0) and readyGradient or recastGradient;

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

    -- Progress bar settings (configurable)
    local barHeight = fullSettings.barHeight or 4;
    local barWidth = fullSettings.barWidth or 150;
    local barY = textY + maxFontSize + (fullSettings.textBarGap or 2);  -- Position below the text

    -- Track where text/bar should start
    local barStartX = x;

    -- Name - left-aligned at start of bar
    if showName then
        imtext.Draw(drawList, nameText, barStartX, textY, textColorHex, nameFontSize);
    end

    -- Recast timer - right-aligned at far right of progress bar
    if showRecast then
        local recastW = imtext.Measure(recastText, recastFontSize);
        imtext.Draw(drawList, recastText, barStartX + barWidth - recastW, textY, textColorHex, recastFontSize);
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

        if progressStyle == 'Fill' then
            if i <= charges then
                -- Full charge available
                segmentProgress = 1.0;
                segmentGradient = readyGradient;
            elseif i == charges + 1 and nextChargeTimer > 0 then
                -- Recharging charge - show progress
                segmentProgress = 1.0 - (nextChargeTimer / chargeValue);
                segmentProgress = math.max(0, math.min(1, segmentProgress));
                segmentGradient = recastGradient;
            else
                -- Empty charge
                segmentProgress = 0;
                segmentGradient = recastGradient;
            end
        else -- Deplete
            if i <= charges then
                -- Available (No cooldown) -> Full bar (consistent with Fill/Ready visibility)
                segmentProgress = 1.0;
                segmentGradient = readyGradient;
            elseif i == charges + 1 and nextChargeTimer > 0 then
                -- Recharging -> Show remaining cooldown (Full to Empty)
                local fillProgress = 1.0 - (nextChargeTimer / chargeValue);
                segmentProgress = 1.0 - math.max(0, math.min(1, fillProgress));
                segmentGradient = recastGradient;
            else
                -- Unavailable (Full cooldown) -> Full bar
                segmentProgress = 1.0;
                segmentGradient = recastGradient;
            end
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

-- gConfig.petBarResizeAnchor: 'top' | 'bottom' pins which edge when AlwaysAutoResize changes height.
-- When unset/nil (should not persist after migrate), falls back to per-type alignBottom for legacy saves.
local function PetBarResizeAnchoredBottom(typeSettings)
    local mode = gConfig.petBarResizeAnchor;
    if mode == 'bottom' then
        return true;
    end
    if mode == 'top' then
        return false;
    end
    return typeSettings.alignBottom == true;
end

-- Resize-anchor preview stripe (shown when Pet Bar Preview + XIUI config open): a thin colored
-- band on the top or bottom edge indicating which edge is pinned during auto-resize.
local function DrawResizeAnchorEdgePreview(px, py, w, h, anchorBottom)
    if not (showConfig and showConfig[1] and gConfig.petBarPreview) then
        return;
    end

    local strip = math.min(7, math.max(5, math.floor(h * 0.04)));
    local inset = 3;
    local x0 = px + inset;
    local x1 = px + w - inset;

    local dl = imgui.GetWindowDrawList();
    local fillCol;
    local outlineCol;
    local y0;
    local y1;
    if anchorBottom then
        fillCol = imgui.GetColorU32({1.0, 0.52, 0.1, 0.76});
        outlineCol = imgui.GetColorU32({1.0, 1.0, 0.95, 0.92});
        y0 = py + h - strip;
        y1 = py + h;
    else
        fillCol = imgui.GetColorU32({0.15, 0.82, 0.95, 0.74});
        outlineCol = imgui.GetColorU32({0.95, 0.98, 1.0, 0.9});
        y0 = py;
        y1 = py + strip;
    end

    dl:AddRectFilled({ x0, y0 }, { x1, y1 }, fillCol);
    dl:AddRect({ x0, y0 }, { x1, y1 }, outlineCol, 0, ImDrawCornerFlags_All, 1.5);
end

-- ============================================
-- DrawWindow - Main Pet Bar Rendering
-- ============================================
function display.DrawWindow(settings)
    -- Global UI scale multiplier. Applied to raw gConfig.petBar* fallbacks so they
    -- match dimensions coming from gAdjustedSettings (which is already gs-scaled in updater).
    local gs = gConfig.globalScale or 1.0;

    -- Get pet data from data module (handles preview internally)
    local petData = data.GetPetData();

    -- Get per-pet-type settings early to check Always Visible
    local typeSettings = GetPetTypeSettings();
    local alwaysVisible = typeSettings.alwaysVisible;

    -- Special handling for BST: Check Charm settings if Jug (default) is not visible
    if not alwaysVisible and data.GetPetJob() == data.JOB_BST then
        local charmSettings = gConfig.petBarCharm or {};
        if charmSettings.alwaysVisible then
            alwaysVisible = true;
        end
    end

    if petData == nil and not alwaysVisible then
        data.currentPetName = nil;
        -- Reset window state when hidden so bottom alignment starts fresh
        windowState.x = nil;
        windowState.y = nil;
        windowState.height = nil;
        windowState.anchorBottom = nil;
        return false;
    end

    -- Setup safe defaults if petData is nil
    local hasPet = (petData ~= nil);
    if not hasPet then
        petData = {
            name = '',
            hpPercent = 0,
            mpPercent = 0,
            tp = 0,
            distance = 0,
            job = data.GetPetJob(),
            showMp = false,
        };
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

    -- Get per-pet-type settings and colors
    -- typeSettings already retrieved at start of function
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

    -- Calculate scaled bar dimensions. Each bar's X scale is independent —
    -- previously halfBarWidth/recastBarWidth/totalRowWidth all derived from
    -- the HP-scaled width, so scaling HP X cascaded into MP/TP/recast widths
    -- and the window total. TP X scale appeared to do nothing because the
    -- half it lived in had already been resized by the HP slider.
    local hpBarWidth = barWidth * hpScaleX;
    local hpBarHeight = barHeight * hpScaleY;
    -- MP and TP bars split the un-scaled base width so their own scales
    -- operate on a stable half regardless of HP X.
    local halfBarWidth = (barWidth - barSpacing) / 2;
    local mpBarWidth = halfBarWidth * mpScaleX;
    local mpBarHeight = barHeight * mpScaleY;
    local tpBarWidth = halfBarWidth * tpScaleX;
    local tpBarHeight = barHeight * tpScaleY;
    -- Recast bars scale off the base width, independent of HP X.
    local recastBarWidth = barWidth * recastScaleX;
    local recastBarHeight = barHeight * recastScaleY;

    -- Window auto-fits whichever bar is widest so the user never loses a
    -- bar to clipping when they push one scale up.
    local mpTpRowWidth = mpBarWidth + barSpacing + tpBarWidth;
    local totalRowWidth = math.max(hpBarWidth, mpTpRowWidth, recastBarWidth);

    -- Store for pet target window
    data.lastTotalRowWidth = totalRowWidth;
    data.lastWindowFlags = windowFlags;
    data.lastColorConfig = colorConfig;
    data.lastSettings = settings;

    local windowPosX, windowPosY = 0, 0;

    local positionJustApplied = ApplyWindowPosition('PetBar');
    if imgui.Begin('PetBar', true, windowFlags) then
        local drawList = drawing.GetUIDrawList();
        imtext.SetConfigFromSettings(settings.name_font_settings);
        -- SaveWindowPosition moved to AFTER the bottom-anchor correction below so the
        -- corrected Y (not the pre-correction one) gets persisted.
        windowPosX, windowPosY = imgui.GetWindowPos();
        local startX, startY = imgui.GetCursorScreenPos();

        -- Draw background + pet image + borders FIRST so they sit beneath text/icons on the draw list.
        -- Window size only known after content; use the previous frame's cached size (updated below).
        if windowState.cachedWidth and windowState.cachedHeight then
            data.UpdateBackground(drawList, windowPosX, windowPosY, windowState.cachedWidth, windowState.cachedHeight, settings);
        end

        if hasPet then
            -- Row 1: Pet Name (with optional level) (left) and HP% (right, same line)
            -- First two fallbacks are raw user values (need gs); third is from adjusted settings (already scaled).
            local rawNameFontSize = typeSettings.nameFontSize or gConfig.petBarNameFontSize;
            local nameFontSize = rawNameFontSize and (rawNameFontSize * gs) or settings.name_font_settings.font_height;
            local rawHpFontSize = typeSettings.hpFontSize or typeSettings.vitalsFontSize or gConfig.petBarVitalsFontSize;
            local hpFontSize = rawHpFontSize and (rawHpFontSize * gs) or settings.vitals_font_settings.font_height;
            local rawMpFontSize = typeSettings.mpFontSize or typeSettings.vitalsFontSize or gConfig.petBarVitalsFontSize;
            local mpFontSize = rawMpFontSize and (rawMpFontSize * gs) or settings.vitals_font_settings.font_height;
            local rawTpFontSize = typeSettings.tpFontSize or typeSettings.vitalsFontSize or gConfig.petBarVitalsFontSize;
            local tpFontSize = rawTpFontSize and (rawTpFontSize * gs) or settings.vitals_font_settings.font_height;

            -- Format name with level if available and enabled
            local showLevel = typeSettings.showLevel;
            if showLevel == nil then showLevel = gConfig.petBarShowLevel ~= false; end
            local displayName = petName;
            if petLevel and showLevel then
                displayName = string.format('Lv.%d %s', petLevel, petName);
            end

            local nameColor = colorConfig.nameTextColor or 0xFFFFFFFF;
            imtext.Draw(drawList, displayName, startX, startY, nameColor, nameFontSize);

            -- Distance text (anchored to top right edge of background)
            local showDistance = typeSettings.showDistance;
            if showDistance == nil then showDistance = gConfig.petBarShowDistance; end
            if showDistance then
                local rawDistanceFontSize = typeSettings.distanceFontSize or gConfig.petBarDistanceFontSize;
                local distanceFontSize = rawDistanceFontSize and (rawDistanceFontSize * gs) or settings.distance_font_settings.font_height;
                local distanceOffsetX = (typeSettings.distanceOffsetX or gConfig.petBarDistanceOffsetX or 0) * gs;
                local distanceOffsetY = (typeSettings.distanceOffsetY or gConfig.petBarDistanceOffsetY or 0) * gs;

                local distStr = string.format('%.1f', petDistance);
                local distColor = colorConfig.distanceTextColor or 0xFFFFFFFF;
                local distW = imtext.Measure(distStr, distanceFontSize);
                imtext.Draw(drawList, distStr, startX + totalRowWidth + distanceOffsetX - distW, windowPosY - 13 + distanceOffsetY, distColor, distanceFontSize);
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
                local hpStr = tostring(petHpPercent) .. '%';
                local hpColor = colorConfig.hpTextColor or 0xFFFFFFFF;
                local hpW = imtext.Measure(hpStr, hpFontSize);
                imtext.Draw(drawList, hpStr, startX + hpBarWidth - hpW, startY + (nameFontSize - hpFontSize) / 2, hpColor, hpFontSize);
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
                -- MP bar takes the full base row width, scaled by its own MP X
                -- (not HP X — otherwise the HP slider would resize the lone MP bar).
                actualMpWidth = barWidth * mpScaleX;
            elseif not displayMpBar and displayTpBar then
                -- TP bar takes the full base row width, scaled by its own TP X.
                actualTpWidth = barWidth * tpScaleX;
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
                -- Right-align MP text under MP bar
                local mpStr = tostring(petMpPercent) .. '%';
                local mpColor = colorConfig.mpTextColor or 0xFFFFFFFF;
                local mpW = imtext.Measure(mpStr, mpFontSize);
                imtext.Draw(drawList, mpStr, mpBarX + actualMpWidth - mpW, mpTextRowY, mpColor, mpFontSize);
            end

            -- TP text (independent of MP bar visibility)
            if displayTpBar then
                -- Right-align TP text under TP bar
                local tpStr = tostring(petTp);
                local tpColor = colorConfig.tpTextColor or 0xFFFFFFFF;
                local tpW = imtext.Measure(tpStr, tpFontSize);
                imtext.Draw(drawList, tpStr, tpBarX + actualTpWidth - tpW, tpTextRowY, tpColor, tpFontSize);
            end

            -- ============================================
            -- Pet Status Icons (buffs/debuffs on pet)
            -- Positioned on same row as MP/TP text values
            -- ============================================
            local showStatusIcons = gConfig.petBarShowStatusIcons;
            if showStatusIcons == nil then showStatusIcons = true; end

            -- Calculate the text row Y position (same as MP/TP text)
            local textRowY = mpBarY;
            if displayMpBar and displayTpBar then
                local maxBarHeight = math.max(mpBarHeight, tpBarHeight);
                textRowY = mpBarY + maxBarHeight + 2;
            elseif displayMpBar then
                textRowY = mpBarY + mpBarHeight + 2;
            elseif displayTpBar then
                textRowY = mpBarY + tpBarHeight + 2;
            end

            -- Draw status icons on the same row as MP/TP text (left side)
            if showStatusIcons then
                local effectIds, effectTimes = data.GetPetStatusEffects();
                -- When settings open with preview, show 2 dummy icons if none (so user can see layout)
                if showConfig and showConfig[1] and gConfig.petBarPreview and (not effectIds or #effectIds == 0) then
                    effectIds = { 56, 92 };   -- Berserk, Evasion Boost (common pet buffs)
                    effectTimes = { 45, nil };
                end
                if effectIds and #effectIds > 0 then
                    -- Clamp so 0/invalid from saved config doesn't hide icons (default 16)
                    local statusIconSize = math.max(8, tonumber(gConfig.petBarStatusIconSize) or 16) * gs;

                    -- Position icons at left side, same Y as MP/TP text
                    imgui.SetCursorScreenPos({barsStartX, textRowY});

                    statusIcons.DrawStatusIcons(
                        effectIds,
                        statusIconSize,
                        6,      -- maxColumns (single row)
                        1,      -- maxRows
                        false,  -- drawBg (background behind icons)
                        0,      -- xOffset
                        effectTimes,
                        nil,    -- settings (use defaults)
                        statusHandler,
                        buffTable
                    );

                    -- Set cursor to fixed position after icons (icon + timer height)
                    imgui.SetCursorScreenPos({barsStartX, textRowY + statusIconSize - 5});
                end
            end
            -- Add spacing for text row if any vitals text is shown
            -- recastTopSpacing controls the gap between vitals text and recast section (anchored mode)
            local recastTopSpacing = (typeSettings.recastTopSpacing or 2) * gs;
            if displayMpBar or displayTpBar then
                local maxVitalsFontSize = math.max(displayMpBar and mpFontSize or 0, displayTpBar and tpFontSize or 0);
                imgui.Dummy({totalRowWidth, maxVitalsFontSize + recastTopSpacing});
            end
        end

        -- Row 4: Ability Icons
        local showTimers = typeSettings.showTimers;
        if showTimers == nil then showTimers = gConfig.petBarShowTimers ~= false; end

        if showTimers then
            -- Get recasts from data module (handles preview internally)
            local timers = data.GetPetRecasts();
            if #timers > 0 then
                local iconOffsetX = (typeSettings.iconsOffsetX or gConfig.petBarIconsOffsetX or 0) * gs;
                local iconOffsetY = (typeSettings.iconsOffsetY or gConfig.petBarIconsOffsetY or 0) * gs;
                local iconsAbsolute = typeSettings.iconsAbsolute;
                if iconsAbsolute == nil then iconsAbsolute = gConfig.petBarIconsAbsolute; end
                local fillStyle = typeSettings.timerFillStyle or 'square';
                local displayStyle = typeSettings.recastDisplayStyle or 'compact';
                -- Scale only applies to compact mode; full mode always uses 1.0. Multiplied by gs (global scale).
                local iconScale = (displayStyle == 'full') and 1.0 or ((typeSettings.iconsScale or gConfig.petBarIconsScale or 1.0) * gs);
                local scaledIconSize = data.RECAST_ICON_SIZE * iconScale;
                local iconSpacing = (typeSettings.recastFullSpacing or 4) * gs;

                local iconX, iconY;

                if iconsAbsolute then
                    -- Absolute positioning: relative to window top-left
                    iconX = windowPosX + iconOffsetX;
                    iconY = windowPosY + iconOffsetY;
                else
                    -- Anchored: flow within the pet bar container
                    -- Use recastTopSpacing for vertical offset, no X offset in anchored mode
                    local topSpacing = (typeSettings.recastTopSpacing or 2) * gs;
                    iconX, iconY = imgui.GetCursorScreenPos();
                    iconY = iconY + topSpacing;
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
                        nameFontSize = (typeSettings.recastFullNameFontSize or 10) * gs,
                        recastFontSize = (typeSettings.recastFullTimerFontSize or 10) * gs,
                        alignment = 'left',
                        iconSize = scaledIconSize,
                        barWidth = recastBarWidth,
                        barHeight = recastBarHeight,
                        showBookends = recastShowBookends,
                        progressStyle = typeSettings.recastProgressStyle or 'Fill',
                        isJug = isJug,
                        textBarGap = 2 * gs,
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
                    local textBarGap = 2 * gs;
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

                    if not iconsAbsolute then
                        -- Only add spacing between rows, not after the last row
                        local totalHeight = #timers * contentHeight + math.max(0, #timers - 1) * iconSpacing;
                        imgui.Dummy({totalRowWidth, totalHeight});
                    end
                else
                    -- Compact display: horizontal row of icons only
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
            end
        end

        -- BST Pet Timer Display (Jug countdown or Charm elapsed)
        local showJugTimer = isJug and gConfig.petBarShowJugTimer ~= false and jugTimeRemaining;
        local showCharmTimer = isCharmed and gConfig.petBarShowCharmIndicator ~= false;

        if showJugTimer or showCharmTimer then
            -- Get timer text for positioning
            local timerStr = nil;
            local textColor = colorConfig.charmTimerColor or 0xFFFFFFFF;
            local iconSize, timerX, timerY, timerFontSize;

            if showJugTimer then
                -- Jug-specific settings
                iconSize = (gConfig.petBarJugIconSize or 16) * gs;
                local offsetX = (gConfig.petBarJugOffsetX or 0) * gs;
                local offsetY = (gConfig.petBarJugOffsetY or -20) * gs;
                timerFontSize = (gConfig.petBarJugTimerFontSize or 12) * gs;
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
                iconSize = (gConfig.petBarCharmIconSize or 16) * gs;
                local offsetX = (gConfig.petBarCharmOffsetX or 0) * gs;
                local offsetY = (gConfig.petBarCharmOffsetY or -20) * gs;
                timerFontSize = (gConfig.petBarCharmTimerFontSize or 12) * gs;
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

            -- Draw timer text
            if timerStr then
                local textX = timerX + iconSize + 1;
                local textY = timerY + (iconSize - timerFontSize) / 2;
                imtext.Draw(drawList, timerStr, textX, textY, textColor, timerFontSize);
            end
        end

        -- Get final window size for background
        local windowWidth, windowHeight = imgui.GetWindowSize();

        local resizeAnchoredBottom = PetBarResizeAnchoredBottom(typeSettings);

        -- Bottom alignment: lock the on-screen Y of the window's bottom edge so AlwaysAutoResize
        -- height changes pin to the bottom (instead of the simple "delta > 1px" gate which let
        -- +/-1px steps slip through and made the bar crawl upward over time). Skip the correction
        -- while the user is dragging the window so their placement isn't fought.
        local petBarCanMove = not gConfig.lockPositions or (showConfig and showConfig[1] and gConfig.petBarPreview);
        local petBarDragging = petBarCanMove and imgui.IsMouseDragging(0) and imgui.IsWindowHovered();
        if resizeAnchoredBottom then
            local curBottom = windowPosY + windowHeight;
            if data.petBarSyncResizeAnchorNextFrame then
                -- Cluster drag from PetBarTarget just moved us; re-sync the anchor to the new bottom.
                windowState.anchorBottom = curBottom;
                data.petBarSyncResizeAnchorNextFrame = false;
            elseif windowState.anchorBottom == nil or positionJustApplied then
                -- First frame after open / save-restore: seed the anchor from the current bottom.
                windowState.anchorBottom = curBottom;
            elseif petBarDragging then
                -- User is dragging; track the bottom edge live so the anchor follows.
                windowState.anchorBottom = curBottom;
            else
                local newPosY = windowState.anchorBottom - windowHeight;
                if math.abs(newPosY - windowPosY) > 0.01 then
                    imgui.SetWindowPos('PetBar', { windowPosX, newPosY });
                    windowPosY = newPosY;
                end
            end

            windowState.x = windowPosX;
            windowState.y = windowPosY;
            windowState.height = windowHeight;
        else
            windowState.x = nil;
            windowState.y = nil;
            windowState.height = nil;
            windowState.anchorBottom = nil;
        end

        -- Store main window position for pet target window snap (rounded to integers so saved
        -- snap offsets aren't drifted by subpixel noise across re-renders).
        data.lastMainWindowPosX = math.floor(windowPosX + 0.5);
        data.lastMainWindowTop = math.floor(windowPosY + 0.5);
        -- Themed window borders extend above/below the ImGui outer rect (~NoBackground + windowBg).
        -- Top snap must reference a line above the ImGui top edge or the visual gap collapses
        -- to zero; +4 below remains the bottom-snap default that pairs with petTargetSnapOffsetY.
        local petBarTopSnapOutset = 8;
        data.petBarSnapTopReferenceY = data.lastMainWindowTop - petBarTopSnapOutset;
        data.lastMainWindowBottom = math.floor(windowPosY + windowHeight + 0.5) + 4;
        data.lastPetBarWindowHeight = math.floor(windowHeight + 0.5);

        DrawResizeAnchorEdgePreview(windowPosX, windowPosY, windowWidth, windowHeight, resizeAnchoredBottom);

        -- Cache window size for next frame's bg draw at the top of this function.
        windowState.cachedWidth = windowWidth;
        windowState.cachedHeight = windowHeight;

        SaveWindowPosition('PetBar');
    end
    imgui.End();

    return true;  -- Pet exists (or preview mode), target window can render
end

-- ============================================
-- ResetPositions - Reset window to default position
-- ============================================
display.ResetPositions = function()
    local defX, defY = defaultPositions.GetPetBarPosition();
    if gConfig.windowPositions then
        gConfig.windowPositions['PetBar'] = { x = defX, y = defY };
    end
    if gConfig.appliedPositions then
        gConfig.appliedPositions['PetBar'] = nil;
    end
    -- Clear bottom-anchor tracking so the next frame re-seeds against the default position.
    windowState.x = nil;
    windowState.y = nil;
    windowState.height = nil;
    windowState.anchorBottom = nil;
end

return display;
