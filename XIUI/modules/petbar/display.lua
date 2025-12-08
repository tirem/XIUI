--[[
* XIUI Pet Bar - Display Module
* Handles rendering of the main pet bar window
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local progressbar = require('libs.progressbar');

local data = require('modules.petbar.data');
local color = require('libs.color');

local display = {};

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
-- Get Timer Colors Based on Individual Ability
-- ============================================
-- Each ability has its own unique color for better visual distinction
local function GetTimerColors(abilityName, colorConfig)
    local name = abilityName or '';
    local cc = colorConfig or {};

    -- SMN abilities
    if name:find('Blood Pact') then
        if name:find('Rage') then
            return cc.timerBPRageReadyColor or 0xE6FF3333,
                   cc.timerBPRageRecastColor or 0xD9FF6666;
        elseif name:find('Ward') then
            return cc.timerBPWardReadyColor or 0xE600CCCC,
                   cc.timerBPWardRecastColor or 0xD966DDDD;
        end
        -- Generic Blood Pact - default to Rage colors
        return cc.timerBPRageReadyColor or 0xE6FF3333,
               cc.timerBPRageRecastColor or 0xD9FF6666;
    end
    if name == 'Apogee' then
        return cc.timerApogeeReadyColor or 0xE6FFCC00,
               cc.timerApogeeRecastColor or 0xD9FFDD66;
    end
    if name == 'Mana Cede' then
        return cc.timerManaCedeReadyColor or 0xE6009999,
               cc.timerManaCedeRecastColor or 0xD966BBBB;
    end

    -- BST abilities
    if name == 'Ready' then
        return cc.timerReadyReadyColor or 0xE6FF6600,
               cc.timerReadyRecastColor or 0xD9FF9933;
    end
    if name == 'Reward' then
        return cc.timerRewardReadyColor or 0xE600CC66,
               cc.timerRewardRecastColor or 0xD966DD99;
    end
    if name == 'Call Beast' then
        return cc.timerCallBeastReadyColor or 0xE63399FF,
               cc.timerCallBeastRecastColor or 0xD966BBFF;
    end
    if name == 'Bestial Loyalty' then
        return cc.timerBestialLoyaltyReadyColor or 0xE69966FF,
               cc.timerBestialLoyaltyRecastColor or 0xD9BB99FF;
    end

    -- DRG abilities
    if name == 'Call Wyvern' then
        return cc.timerCallWyvernReadyColor or 0xE63366FF,
               cc.timerCallWyvernRecastColor or 0xD96699FF;
    end
    if name == 'Spirit Link' then
        return cc.timerSpiritLinkReadyColor or 0xE633CC33,
               cc.timerSpiritLinkRecastColor or 0xD966DD66;
    end
    if name == 'Deep Breathing' then
        return cc.timerDeepBreathingReadyColor or 0xE6FFFF33,
               cc.timerDeepBreathingRecastColor or 0xD9FFFF99;
    end
    if name == 'Steady Wing' then
        return cc.timerSteadyWingReadyColor or 0xE6CC66FF,
               cc.timerSteadyWingRecastColor or 0xD9DD99FF;
    end

    -- PUP abilities
    if name == 'Activate' then
        return cc.timerActivateReadyColor or 0xE63399FF,
               cc.timerActivateRecastColor or 0xD966BBFF;
    end
    if name == 'Repair' then
        return cc.timerRepairReadyColor or 0xE633CC66,
               cc.timerRepairRecastColor or 0xD966DD99;
    end
    if name == 'Deploy' then
        return cc.timerDeployReadyColor or 0xE6FF9933,
               cc.timerDeployRecastColor or 0xD9FFBB66;
    end
    if name == 'Deactivate' then
        return cc.timerDeactivateReadyColor or 0xE6999999,
               cc.timerDeactivateRecastColor or 0xD9BBBBBB;
    end
    if name == 'Retrieve' then
        return cc.timerRetrieveReadyColor or 0xE666CCFF,
               cc.timerRetrieveRecastColor or 0xD999DDFF;
    end
    if name == 'Deus Ex Automata' then
        return cc.timerDeusExAutomataReadyColor or 0xE6FFCC33,
               cc.timerDeusExAutomataRecastColor or 0xD9FFDD66;
    end

    -- Two-Hour abilities - Magenta
    if name == 'Astral Flow' or name == 'Familiar' or name == 'Spirit Surge' or name == 'Overdrive' then
        return cc.timer2hReadyColor or 0xE6FF00FF,
               cc.timer2hRecastColor or 0xD9FF66FF;
    end

    -- Fallback for unknown abilities - use a neutral gray
    return 0xE6AAAAAA, 0xD9CCCCCC;
end

-- ============================================
-- Draw Ability Icon with Clockwise Fill
-- ============================================
local function DrawAbilityIcon(drawList, x, y, size, timerInfo, colorConfig)
    local radius = size / 2;
    local centerX = x + radius;
    local centerY = y + radius;
    local innerRadius = radius - 2;

    -- Get colors based on ability category
    local readyHex, recastHex = GetTimerColors(timerInfo.name, colorConfig);

    -- Background circle (dark blue)
    local bgColor = imgui.GetColorU32({0.01, 0.07, 0.17, 1.0});
    drawList:AddCircleFilled({centerX, centerY}, radius, bgColor, 32);

    if not timerInfo.isReady and timerInfo.timer > 0 and timerInfo.maxTimer and timerInfo.maxTimer > 0 then
        -- Calculate progress (0 = just started cooldown, 1 = ready)
        local progress = 1.0 - (timerInfo.timer / timerInfo.maxTimer);
        progress = math.max(0, math.min(1, progress));

        if progress > 0 then
            local fillColor = imgui.GetColorU32(color.ARGBToImGui(recastHex));

            -- Check if Path methods are available (Ashita 4.3+)
            if drawList.PathClear then
                -- Draw clockwise fill arc (from 12 o'clock position)
                local startAngle = -math.pi / 2;
                local endAngle = startAngle + (progress * 2 * math.pi);

                drawList:PathClear();
                drawList:PathLineTo({centerX, centerY});
                local numSegments = math.max(3, math.floor(32 * progress));
                drawList:PathArcTo({centerX, centerY}, innerRadius, startAngle, endAngle, numSegments);
                drawList:PathFillConvex(fillColor);
            else
                -- Fallback for Ashita 4.0: draw simple filled circle for progress
                drawList:AddCircleFilled({centerX, centerY}, innerRadius * progress, fillColor, 32);
            end
        end
    else
        local readyColor = imgui.GetColorU32(color.ARGBToImGui(readyHex));
        drawList:AddCircleFilled({centerX, centerY}, innerRadius, readyColor, 32);
    end

    -- Border (darker blue)
    local borderColor = imgui.GetColorU32({0.01, 0.05, 0.12, 1.0});
    drawList:AddCircle({centerX, centerY}, radius, borderColor, 32, 2);
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
    local charmElapsed = petData.charmElapsed;

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

        -- Distance text (absolute or next to pet name)
        local showDistance = typeSettings.showDistance;
        if showDistance == nil then showDistance = gConfig.petBarShowDistance; end
        if showDistance then
            local distanceFontSize = typeSettings.distanceFontSize or gConfig.petBarDistanceFontSize or settings.distance_font_settings.font_height;
            local distanceAbsolute = typeSettings.distanceAbsolute;
            if distanceAbsolute == nil then distanceAbsolute = gConfig.petBarDistanceAbsolute; end
            local distanceOffsetX = typeSettings.distanceOffsetX or gConfig.petBarDistanceOffsetX or 0;
            local distanceOffsetY = typeSettings.distanceOffsetY or gConfig.petBarDistanceOffsetY or 0;

            data.distanceText:set_font_height(distanceFontSize);
            data.distanceText:set_text(string.format('%.1f', petDistance));

            if distanceAbsolute then
                -- Absolute positioning: relative to window top-left
                data.distanceText:set_position_x(windowPosX + distanceOffsetX);
                data.distanceText:set_position_y(windowPosY + distanceOffsetY);
            else
                -- Relative positioning: next to pet name
                local nameWidth, _ = data.nameText:get_text_size();
                data.distanceText:set_position_x(startX + nameWidth + 4);
                data.distanceText:set_position_y(startY + (nameFontSize - distanceFontSize) / 2);
            end

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

            -- Use HP interpolation for damage/healing animations
            local currentTime = os.clock();
            local petEntity = data.GetPetEntity();
            local petIndex = petEntity and petEntity.TargetIndex or 0;
            local hpPercentData = HpInterpolation.update('petbar', petHpPercent, petIndex, settings, currentTime, hpGradient);

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
        if displayMpBar or displayTpBar then
            local maxVitalsFontSize = math.max(displayMpBar and mpFontSize or 0, displayTpBar and tpFontSize or 0);
            imgui.Dummy({totalRowWidth, maxVitalsFontSize + 2});
        end

        -- Row 4: Ability Icons (circular)
        local showTimers = typeSettings.showTimers;
        if showTimers == nil then showTimers = gConfig.petBarShowTimers ~= false; end
        if showTimers then
            -- Get timers from data module (handles preview internally)
            local timers = data.GetPetAbilityTimers();
            if #timers > 0 then
                local iconScale = typeSettings.iconsScale or gConfig.petBarIconsScale or 1.0;
                local iconOffsetX = typeSettings.iconsOffsetX or gConfig.petBarIconsOffsetX or 0;
                local iconOffsetY = typeSettings.iconsOffsetY or gConfig.petBarIconsOffsetY or 0;
                local iconsAbsolute = typeSettings.iconsAbsolute;
                if iconsAbsolute == nil then iconsAbsolute = gConfig.petBarIconsAbsolute; end
                local scaledIconSize = data.ABILITY_ICON_SIZE * iconScale;
                local iconSpacing = 4 * iconScale;

                local iconX, iconY;
                local drawList;

                if iconsAbsolute then
                    -- Absolute positioning: relative to window top-left
                    iconX = windowPosX + iconOffsetX;
                    iconY = windowPosY + iconOffsetY;
                    drawList = imgui.GetForegroundDrawList();
                else
                    -- In container: flow within the pet bar
                    imgui.Dummy({0, barSpacing + 4});
                    iconX, iconY = imgui.GetCursorScreenPos();
                    iconX = iconX + iconOffsetX;
                    iconY = iconY + iconOffsetY;
                    drawList = imgui.GetWindowDrawList();
                end

                for i, timerInfo in ipairs(timers) do
                    if i > data.MAX_ABILITY_ICONS then break; end

                    local posX = iconX + (i - 1) * (scaledIconSize + iconSpacing);
                    DrawAbilityIcon(drawList, posX, iconY, scaledIconSize, timerInfo, colorConfig);
                end

                if not iconsAbsolute then
                    imgui.Dummy({totalRowWidth, scaledIconSize});
                end
            end
        end

        -- BST Pet Timer Display (Jug countdown or Charm elapsed)
        local showJugTimer = isJug and gConfig.petBarShowJugTimer ~= false and jugTimeRemaining;
        local showCharmTimer = isCharmed and gConfig.petBarShowCharmIndicator ~= false;

        if showJugTimer or showCharmTimer then
            local drawList = imgui.GetForegroundDrawList();

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
                    local jugColor = imgui.GetColorU32(color.ARGBToImGui(colorConfig.jugIconColor or 0xFFFFFFFF));
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

                if charmElapsed then
                    timerStr = data.FormatTimeMMSS(charmElapsed);
                end

                -- Charmed pet: Show heart icon
                local heartColor = imgui.GetColorU32(color.ARGBToImGui(colorConfig.charmHeartColor or 0xFFFF6699));

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

        -- Store main window position for pet target window
        data.lastMainWindowPosX = windowPosX;
        data.lastMainWindowBottom = windowPosY + windowHeight + 4;

        -- Update background primitives
        data.UpdateBackground(windowPosX, windowPosY, windowWidth, windowHeight, settings);
    end
    imgui.End();

    return true;  -- Pet exists (or preview mode), target window can render
end

return display;
