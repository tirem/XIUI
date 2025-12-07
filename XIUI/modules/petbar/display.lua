--[[
* XIUI Pet Bar - Display Module
* Handles rendering of the main pet bar window
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local progressbar = require('libs.progressbar');

local data = require('modules.petbar.data');

local display = {};

-- ============================================
-- Draw Ability Icon with Clockwise Fill
-- ============================================
local function DrawAbilityIcon(drawList, x, y, size, timerInfo, colorConfig)
    local radius = size / 2;
    local centerX = x + radius;
    local centerY = y + radius;
    local innerRadius = radius - 2;

    -- Background circle (dark)
    local bgColor = imgui.GetColorU32({0.15, 0.15, 0.15, 0.95});
    drawList:AddCircleFilled({centerX, centerY}, radius, bgColor, 32);

    if not timerInfo.isReady and timerInfo.timer > 0 and timerInfo.maxTimer and timerInfo.maxTimer > 0 then
        -- Calculate progress (0 = just started cooldown, 1 = ready)
        local progress = 1.0 - (timerInfo.timer / timerInfo.maxTimer);
        progress = math.max(0, math.min(1, progress));

        if progress > 0 then
            -- Draw clockwise fill arc (from 12 o'clock position)
            local startAngle = -math.pi / 2;
            local endAngle = startAngle + (progress * 2 * math.pi);

            -- Get recast color for the fill (yellow when on cooldown)
            local recastColor = colorConfig and colorConfig.timerRecastColor or 0xFFFFFF00;
            local r = bit.band(bit.rshift(recastColor, 16), 0xFF) / 255;
            local g = bit.band(bit.rshift(recastColor, 8), 0xFF) / 255;
            local b = bit.band(recastColor, 0xFF) / 255;
            local fillColor = imgui.GetColorU32({r, g, b, 0.7});

            -- Draw filled arc using PathArcTo
            drawList:PathClear();
            drawList:PathLineTo({centerX, centerY});
            local segments = math.max(3, math.floor(32 * progress));
            drawList:PathArcTo({centerX, centerY}, innerRadius, startAngle, endAngle, segments);
            drawList:PathFillConvex(fillColor);
        end
    else
        -- Ready indicator (full green circle)
        local readyColor = colorConfig and colorConfig.timerReadyColor or 0xFF00FF00;
        local r = bit.band(bit.rshift(readyColor, 16), 0xFF) / 255;
        local g = bit.band(bit.rshift(readyColor, 8), 0xFF) / 255;
        local b = bit.band(readyColor, 0xFF) / 255;
        local innerColor = imgui.GetColorU32({r, g, b, 0.8});
        drawList:AddCircleFilled({centerX, centerY}, innerRadius, innerColor, 32);
    end

    -- Border
    local borderColor = imgui.GetColorU32({0.5, 0.5, 0.5, 1.0});
    drawList:AddCircle({centerX, centerY}, radius, borderColor, 32, 2);
end

-- ============================================
-- DrawWindow - Main Pet Bar Rendering
-- ============================================
function display.DrawWindow(settings)
    local player = GetPlayerSafe();
    local party = GetPartySafe();
    local playerEnt = GetPlayerEntity();

    if player == nil or party == nil or playerEnt == nil then
        data.SetAllFontsVisible(false);
        data.HideBackground();
        return false;
    end

    local currJob = player:GetMainJob();
    if player.isZoning or currJob == 0 then
        data.SetAllFontsVisible(false);
        data.HideBackground();
        return false;
    end

    -- Check if we have a pet
    local pet = data.GetPetEntity();
    if pet == nil then
        data.currentPetName = nil;
        data.SetAllFontsVisible(false);
        data.HideBackground();
        return false;
    end

    -- Get pet stats
    local petName = pet.Name or 'Pet';
    -- Update current pet name for image display
    data.currentPetName = petName;
    local petHpPercent = pet.HPPercent or 0;
    local petDistance = math.sqrt(pet.Distance);
    local petMpPercent = player:GetPetMPPercent() or 0;
    local petTp = player:GetPetTP() or 0;
    local petTpPercent = math.min(petTp / 1000, 1.0);

    local petJob = data.GetPetJob();
    local showMp = petJob == data.JOB_SMN or petJob == data.JOB_PUP;

    -- Build window flags
    local windowFlags = data.getBaseWindowFlags();
    if gConfig.lockPositions then
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
    local hpBarWidth = barWidth * hpScaleX;
    local hpBarHeight = barHeight * hpScaleY;
    local mpBarWidth = (barWidth / 2 - barSpacing / 2) * mpScaleX;
    local mpBarHeight = barHeight * mpScaleY;
    local tpBarWidth = (barWidth / 2 - barSpacing / 2) * tpScaleX;
    local tpBarHeight = barHeight * tpScaleY;

    -- Text positioning
    local textGap = 8;
    local textOffsetX = barWidth + textGap;
    local maxTextWidth = 50;

    -- Color config
    local colorConfig = gConfig.colorCustomization and gConfig.colorCustomization.petBar or {};

    -- Total row width for proper window sizing
    local totalRowWidth = barWidth + textGap + maxTextWidth;

    -- Store for pet target window
    data.lastTotalRowWidth = totalRowWidth;
    data.lastWindowFlags = windowFlags;
    data.lastColorConfig = colorConfig;
    data.lastSettings = settings;

    local windowPosX, windowPosY = 0, 0;

    if imgui.Begin('PetBar', true, windowFlags) then
        windowPosX, windowPosY = imgui.GetWindowPos();
        local startX, startY = imgui.GetCursorScreenPos();

        -- Row 1: Pet Name and Distance
        local nameFontSize = gConfig.petBarNameFontSize or settings.name_font_settings.font_height;
        data.nameText:set_font_height(nameFontSize);
        data.nameText:set_text(petName);
        data.nameText:set_position_x(startX);
        data.nameText:set_position_y(startY);
        local nameColor = colorConfig.nameTextColor or 0xFFFFFFFF;
        if data.lastNameColor ~= nameColor then
            data.nameText:set_font_color(nameColor);
            data.lastNameColor = nameColor;
        end
        data.nameText:set_visible(true);

        -- Distance text (right side)
        data.distanceText:set_font_height(gConfig.petBarDistanceFontSize or settings.distance_font_settings.font_height);
        data.distanceText:set_text(string.format('%.1fy', petDistance));
        data.distanceText:set_position_x(startX + barWidth);
        data.distanceText:set_position_y(startY);
        local distColor = colorConfig.distanceTextColor or 0xFFFFFFFF;
        if data.lastDistColor ~= distColor then
            data.distanceText:set_font_color(distColor);
            data.lastDistColor = distColor;
        end
        data.distanceText:set_visible(gConfig.petBarShowDistance ~= false);

        imgui.Dummy({totalRowWidth, nameFontSize + 4});

        -- Row 2: HP Bar with text to the right
        if gConfig.petBarShowVitals ~= false then
            local hpGradient = GetCustomGradient(colorConfig, 'hpGradient') or {'#e26c6c', '#fa9c9c'};
            local hpBarX, hpBarY = imgui.GetCursorScreenPos();

            progressbar.ProgressBar(
                {{petHpPercent / 100, hpGradient}},
                {hpBarWidth, hpBarHeight},
                {decorate = gConfig.petBarShowBookends}
            );

            -- HP Text to the right of bar
            local vitalsFontSize = gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;
            data.hpText:set_font_height(vitalsFontSize);
            data.hpText:set_text(tostring(petHpPercent) .. '%');
            data.hpText:set_position_x(hpBarX + textOffsetX);
            data.hpText:set_position_y(hpBarY + (barHeight - vitalsFontSize) / 2);
            local hpColor = colorConfig.hpTextColor or 0xFFFFFFFF;
            if data.lastHpColor ~= hpColor then
                data.hpText:set_font_color(hpColor);
                data.lastHpColor = hpColor;
            end
            data.hpText:set_visible(true);

            imgui.Dummy({0, barSpacing});

            -- Row 3: MP and TP bars side by side (half width each)
            local mpTpBarY;
            local mpBarX, mpBarY = imgui.GetCursorScreenPos();
            mpTpBarY = mpBarY;

            if showMp then
                local mpGradient = GetCustomGradient(colorConfig, 'mpGradient') or {'#9abb5a', '#bfe07d'};
                progressbar.ProgressBar(
                    {{petMpPercent / 100, mpGradient}},
                    {mpBarWidth, mpBarHeight},
                    {decorate = gConfig.petBarShowBookends}
                );

                imgui.SameLine();
                imgui.Dummy({barSpacing, 0});
                imgui.SameLine();
            end

            -- TP Bar
            local tpBarX, tpBarY = imgui.GetCursorScreenPos();
            local tpGradient = GetCustomGradient(colorConfig, 'tpGradient') or {'#3898ce', '#78c4ee'};
            local actualTpWidth = showMp and tpBarWidth or (barWidth * tpScaleX);
            local actualTpHeight = tpBarHeight;

            progressbar.ProgressBar(
                {{petTpPercent, tpGradient}},
                {actualTpWidth, actualTpHeight},
                {decorate = gConfig.petBarShowBookends}
            );

            -- MP/TP Text to the right
            if showMp then
                data.mpText:set_font_height(vitalsFontSize);
                data.mpText:set_text(tostring(petMpPercent) .. '%');
                data.mpText:set_position_x(mpBarX + textOffsetX);
                data.mpText:set_position_y(mpTpBarY + (barHeight - vitalsFontSize) / 2);
                local mpColor = colorConfig.mpTextColor or 0xFFFFFFFF;
                if data.lastMpColor ~= mpColor then
                    data.mpText:set_font_color(mpColor);
                    data.lastMpColor = mpColor;
                end
                data.mpText:set_visible(true);
            else
                data.mpText:set_visible(false);
            end

            data.tpText:set_font_height(vitalsFontSize);
            data.tpText:set_text(tostring(petTp));
            data.tpText:set_position_x(mpBarX + textOffsetX + (showMp and 40 or 0));
            data.tpText:set_position_y(mpTpBarY + (barHeight - vitalsFontSize) / 2);
            local tpColor = colorConfig.tpTextColor or 0xFFFFFFFF;
            if data.lastTpColor ~= tpColor then
                data.tpText:set_font_color(tpColor);
                data.lastTpColor = tpColor;
            end
            data.tpText:set_visible(true);
        else
            data.hpText:set_visible(false);
            data.mpText:set_visible(false);
            data.tpText:set_visible(false);
        end

        -- Row 4: Ability Icons (circular)
        if gConfig.petBarShowTimers ~= false then
            local timers = data.GetPetAbilityTimers();
            if #timers > 0 then
                imgui.Dummy({0, barSpacing + 4});

                local iconX, iconY = imgui.GetCursorScreenPos();
                local drawList = imgui.GetWindowDrawList();
                local iconSpacing = 4;

                for i, timerInfo in ipairs(timers) do
                    if i > data.MAX_ABILITY_ICONS then break; end

                    local posX = iconX + (i - 1) * (data.ABILITY_ICON_SIZE + iconSpacing);
                    DrawAbilityIcon(drawList, posX, iconY, data.ABILITY_ICON_SIZE, timerInfo, colorConfig);
                end

                imgui.Dummy({totalRowWidth, data.ABILITY_ICON_SIZE});
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

    return true;  -- Pet exists, target window can render
end

return display;
