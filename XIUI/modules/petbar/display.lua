--[[
* XIUI Pet Bar - Display Module
* Handles rendering of the main pet bar window
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local progressbar = require('libs.progressbar');

local data = require('modules.petbar.data');
local color = require('libs.color');

local display = {};

-- ============================================
-- Get Timer Colors Based on Ability Category
-- ============================================
-- Rage (offensive): Blood Pact: Rage, Ready, Sic, Deploy
-- Ward (defensive): Blood Pact: Ward, Reward, Repair, Spirit Link
-- Two-Hour: Astral Flow, Familiar, Spirit Surge, Overdrive
-- Other: Apogee, Mana Cede, Call Beast, Call Wyvern, Activate, etc.
local function GetTimerColors(abilityName, colorConfig)
    local name = abilityName or '';

    -- Blood Pact handling - check for Rage/Ward variants
    if name:find('Blood Pact') then
        if name:find('Rage') then
            local readyColor = (colorConfig and colorConfig.timerRageReadyColor) or 0xE6FF6600;
            local recastColor = (colorConfig and colorConfig.timerRageRecastColor) or 0xD9FF9933;
            return readyColor, recastColor;
        elseif name:find('Ward') then
            local readyColor = (colorConfig and colorConfig.timerWardReadyColor) or 0xE600CCFF;
            local recastColor = (colorConfig and colorConfig.timerWardRecastColor) or 0xD966E0FF;
            return readyColor, recastColor;
        end
        -- Generic Blood Pact without Rage/Ward - default to Rage colors
        local readyColor = (colorConfig and colorConfig.timerRageReadyColor) or 0xE6FF6600;
        local recastColor = (colorConfig and colorConfig.timerRageRecastColor) or 0xD9FF9933;
        return readyColor, recastColor;
    end

    -- Rage abilities (offensive) - Orange
    if name == 'Ready' or name == 'Sic' or name == 'Deploy' then
        local readyColor = (colorConfig and colorConfig.timerRageReadyColor) or 0xE6FF6600;
        local recastColor = (colorConfig and colorConfig.timerRageRecastColor) or 0xD9FF9933;
        return readyColor, recastColor;
    end

    -- Ward abilities (defensive) - Cyan
    if name == 'Reward' or name == 'Repair' or name == 'Spirit Link' then
        local readyColor = (colorConfig and colorConfig.timerWardReadyColor) or 0xE600CCFF;
        local recastColor = (colorConfig and colorConfig.timerWardRecastColor) or 0xD966E0FF;
        return readyColor, recastColor;
    end

    -- Two-Hour abilities - Magenta
    if name == 'Astral Flow' or name == 'Familiar' or name == 'Spirit Surge' or name == 'Overdrive' then
        local readyColor = (colorConfig and colorConfig.timer2hReadyColor) or 0xE6FF00FF;
        local recastColor = (colorConfig and colorConfig.timer2hRecastColor) or 0xD9FF66FF;
        return readyColor, recastColor;
    end

    -- Other abilities (utility) - Green/Yellow
    local readyColor = (colorConfig and colorConfig.timerReadyColor) or 0xE600FF00;
    local recastColor = (colorConfig and colorConfig.timerRecastColor) or 0xD9FFFF00;
    return readyColor, recastColor;
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

            -- Draw clockwise fill arc (from 12 o'clock position)
            local startAngle = -math.pi / 2;
            local endAngle = startAngle + (progress * 2 * math.pi);

            drawList:PathClear();
            drawList:PathLineTo({centerX, centerY});
            local numSegments = math.max(3, math.floor(32 * progress));
            drawList:PathArcTo({centerX, centerY}, innerRadius, startAngle, endAngle, numSegments);
            drawList:PathFillConvex(fillColor);
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

    -- Calculate dimensions (base values)
    local barWidth = settings.barWidth;
    local barHeight = settings.barHeight;
    local barSpacing = settings.barSpacing;

    -- Individual bar scales
    local hpScaleX = gConfig.petBarHpScaleX or 1.0;
    local hpScaleY = gConfig.petBarHpScaleY or 1.0;
    local mpScaleX = gConfig.petBarMpScaleX or 1.0;
    local mpScaleY = gConfig.petBarMpScaleY or 1.0;
    local tpScaleX = gConfig.petBarTpScaleX or 1.0;
    local tpScaleY = gConfig.petBarTpScaleY or 1.0;

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

    -- Color config
    local colorConfig = gConfig.colorCustomization and gConfig.colorCustomization.petBar or {};

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
        local nameFontSize = gConfig.petBarNameFontSize or settings.name_font_settings.font_height;
        local vitalsFontSize = gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;

        -- Format name with level if available and enabled
        local displayName = petName;
        if petLevel and gConfig.petBarShowLevel ~= false then
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
        if gConfig.petBarShowDistance then
            local distanceFontSize = gConfig.petBarDistanceFontSize or settings.distance_font_settings.font_height;
            data.distanceText:set_font_height(distanceFontSize);
            data.distanceText:set_text(string.format('%.1f', petDistance));

            if gConfig.petBarDistanceAbsolute then
                -- Absolute positioning: relative to window top-left
                local offsetX = gConfig.petBarDistanceOffsetX or 0;
                local offsetY = gConfig.petBarDistanceOffsetY or 0;
                data.distanceText:set_position_x(windowPosX + offsetX);
                data.distanceText:set_position_y(windowPosY + offsetY);
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

        -- HP% text (right-aligned to HP bar width)
        if gConfig.petBarShowVitals ~= false then
            data.hpText:set_font_height(vitalsFontSize);
            data.hpText:set_text(tostring(petHpPercent) .. '%');
            data.hpText:set_position_x(startX + hpBarWidth);
            data.hpText:set_position_y(startY + (nameFontSize - vitalsFontSize) / 2);
            local hpColor = colorConfig.hpTextColor or 0xFFFFFFFF;
            if data.lastHpColor ~= hpColor then
                data.hpText:set_font_color(hpColor);
                data.lastHpColor = hpColor;
            end
            data.hpText:set_visible(true);
        end

        imgui.Dummy({totalRowWidth, nameFontSize + 4});

        -- Row 2: HP Bar (full width) with interpolation
        if gConfig.petBarShowVitals ~= false then
            local hpGradient = GetCustomGradient(colorConfig, 'hpGradient') or {'#e26c6c', '#fa9c9c'};
            local hpBarX, hpBarY = imgui.GetCursorScreenPos();

            -- Use HP interpolation for damage/healing animations
            local currentTime = os.clock();
            local petEntity = data.GetPetEntity();
            local petIndex = petEntity and petEntity.TargetIndex or 0;
            local hpPercentData = HpInterpolation.update('petbar', petHpPercent, petIndex, settings, currentTime, hpGradient);

            progressbar.ProgressBar(
                hpPercentData,
                {hpBarWidth, hpBarHeight},
                {decorate = gConfig.petBarShowBookends}
            );

            -- Row 3: MP and TP bars side by side (half width each)
            local mpBarX, mpBarY = imgui.GetCursorScreenPos();
            local tpBarX = mpBarX;

            if showMp then
                local mpGradient = GetCustomGradient(colorConfig, 'mpGradient') or {'#9abb5a', '#bfe07d'};
                progressbar.ProgressBar(
                    {{petMpPercent / 100, mpGradient}},
                    {mpBarWidth, mpBarHeight},
                    {decorate = gConfig.petBarShowBookends}
                );

                imgui.SameLine(0, barSpacing);
                tpBarX = imgui.GetCursorScreenPos();
            end

            -- TP Bar
            local tpGradient = GetCustomGradient(colorConfig, 'tpGradient') or {'#3898ce', '#78c4ee'};
            -- When no MP bar, TP bar takes full HP bar width; otherwise use calculated tpBarWidth
            local actualTpWidth = showMp and tpBarWidth or hpBarWidth;
            local actualTpHeight = tpBarHeight;

            progressbar.ProgressBar(
                {{petTpPercent, tpGradient}},
                {actualTpWidth, actualTpHeight},
                {decorate = gConfig.petBarShowBookends}
            );

            -- Row 4: MP% and TP text below their respective bars (right-aligned)
            -- Position text 2px below the MP/TP bars
            local textRowY = mpBarY + mpBarHeight + 2;

            if showMp then
                data.mpText:set_font_height(vitalsFontSize);
                data.mpText:set_text(tostring(petMpPercent) .. '%');
                -- Right-align MP text under MP bar
                data.mpText:set_position_x(mpBarX + mpBarWidth);
                data.mpText:set_position_y(textRowY);
                local mpColor = colorConfig.mpTextColor or 0xFFFFFFFF;
                if data.lastMpColor ~= mpColor then
                    data.mpText:set_font_color(mpColor);
                    data.lastMpColor = mpColor;
                end
                data.mpText:set_visible(true);

                data.tpText:set_font_height(vitalsFontSize);
                data.tpText:set_text(tostring(petTp));
                -- Right-align TP text under TP bar
                data.tpText:set_position_x(tpBarX + actualTpWidth);
                data.tpText:set_position_y(textRowY);
                local tpColor = colorConfig.tpTextColor or 0xFFFFFFFF;
                if data.lastTpColor ~= tpColor then
                    data.tpText:set_font_color(tpColor);
                    data.lastTpColor = tpColor;
                end
                data.tpText:set_visible(true);
            else
                data.mpText:set_visible(false);

                data.tpText:set_font_height(vitalsFontSize);
                data.tpText:set_text(tostring(petTp));
                -- Right-align TP text under TP bar (full width when no MP)
                data.tpText:set_position_x(mpBarX + actualTpWidth);
                data.tpText:set_position_y(textRowY);
                local tpColor = colorConfig.tpTextColor or 0xFFFFFFFF;
                if data.lastTpColor ~= tpColor then
                    data.tpText:set_font_color(tpColor);
                    data.lastTpColor = tpColor;
                end
                data.tpText:set_visible(true);
            end

            imgui.Dummy({totalRowWidth, vitalsFontSize + 2});
        else
            data.hpText:set_visible(false);
            data.mpText:set_visible(false);
            data.tpText:set_visible(false);
        end

        -- Row 4: Ability Icons (circular)
        if gConfig.petBarShowTimers ~= false then
            -- Get timers from data module (handles preview internally)
            local timers = data.GetPetAbilityTimers();
            if #timers > 0 then
                local iconScale = gConfig.petBarIconsScale or 1.0;
                local iconOffsetX = gConfig.petBarIconsOffsetX or 0;
                local iconOffsetY = gConfig.petBarIconsOffsetY or 0;
                local scaledIconSize = data.ABILITY_ICON_SIZE * iconScale;
                local iconSpacing = 4 * iconScale;

                local iconX, iconY;
                local drawList;

                if gConfig.petBarIconsAbsolute then
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

                if not gConfig.petBarIconsAbsolute then
                    imgui.Dummy({totalRowWidth, scaledIconSize});
                end
            end
        end

        -- BST Pet Timer Display (Jug countdown or Charm elapsed)
        local showJugTimer = isJug and gConfig.petBarShowJugTimer ~= false and jugTimeRemaining;
        local showCharmTimer = isCharmed and gConfig.petBarShowCharmIndicator ~= false;

        if showJugTimer or showCharmTimer then
            local drawList = imgui.GetForegroundDrawList();
            local iconSize = gConfig.petBarCharmIconSize or 16;
            local offsetX = gConfig.petBarCharmOffsetX or 0;
            local offsetY = gConfig.petBarCharmOffsetY or -20;

            local timerX = windowPosX + offsetX;
            local timerY = windowPosY + offsetY;

            if showJugTimer then
                -- Jug pet: Show jug icon with countdown timer
                local jugColor = imgui.GetColorU32(color.ARGBToImGui(colorConfig.jugIconColor or 0xFFFFFFFF));

                -- Draw a simple jug/bottle icon (rounded rectangle)
                local iconCenterX = timerX + iconSize / 2;
                local iconCenterY = timerY + iconSize / 2;
                drawList:AddRectFilled(
                    {timerX + 2, timerY + iconSize * 0.3},
                    {timerX + iconSize - 2, timerY + iconSize},
                    jugColor, 3
                );
                -- Jug neck
                drawList:AddRectFilled(
                    {timerX + iconSize * 0.3, timerY},
                    {timerX + iconSize * 0.7, timerY + iconSize * 0.4},
                    jugColor, 2
                );

                -- Timer text (countdown)
                local timerStr = data.FormatTimeMMSS(jugTimeRemaining);
                if timerStr then
                    local textColor = colorConfig.charmTimerColor or 0xFFFFFFFF;
                    -- Warning color if under 5 minutes
                    if jugTimeRemaining < 300 then
                        textColor = colorConfig.durationWarningColor or 0xFFFF6600;
                    end
                    -- Draw timer text next to icon using ImGui
                    local textX = timerX + iconSize + 4;
                    local textY = timerY + (iconSize - 12) / 2;
                    drawList:AddText({textX, textY}, imgui.GetColorU32(color.ARGBToImGui(textColor)), timerStr);
                end
            elseif showCharmTimer then
                -- Charmed pet: Show heart icon with elapsed timer
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

                -- Timer text (elapsed time)
                if charmElapsed then
                    local timerStr = data.FormatTimeMMSS(charmElapsed);
                    if timerStr then
                        local textColor = colorConfig.charmTimerColor or 0xFFFFFFFF;
                        local textX = timerX + iconSize + 4;
                        local textY = timerY + (iconSize - 12) / 2;
                        drawList:AddText({textX, textY}, imgui.GetColorU32(color.ARGBToImGui(textColor)), timerStr);
                    end
                end
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
