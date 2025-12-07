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

-- Helper to convert hex color string to RGBA values (0-1 range)
local function hexToRgba(hex)
    hex = hex:gsub("#", "");
    local r = tonumber("0x"..hex:sub(1,2)) / 255;
    local g = tonumber("0x"..hex:sub(3,4)) / 255;
    local b = tonumber("0x"..hex:sub(5,6)) / 255;
    local a = 1.0;
    if #hex == 8 then
        a = tonumber("0x"..hex:sub(7,8)) / 255;
    end
    return r, g, b, a;
end

-- Helper to get gradient colors from config
local function getGradientColors(gradient, defaultStart, defaultStop)
    local startColor = (gradient and gradient.start) or defaultStart;
    local endColor = (gradient and gradient.stop) or defaultStop;
    local sr, sg, sb = hexToRgba(startColor);
    local er, eg, eb = hexToRgba(endColor);
    return sr, sg, sb, er, eg, eb;
end

-- Draw a filled circle with vertical gradient (top to bottom)
local function DrawGradientCircleFilled(drawList, centerX, centerY, radius, topR, topG, topB, bottomR, bottomG, bottomB, alpha, segments)
    segments = segments or 32;
    local topY = centerY - radius;
    local bottomY = centerY + radius;
    local height = bottomY - topY;

    -- Draw horizontal strips from top to bottom
    local numStrips = math.max(16, math.floor(radius));
    for i = 0, numStrips - 1 do
        local t1 = i / numStrips;
        local t2 = (i + 1) / numStrips;
        local y1 = topY + t1 * height;
        local y2 = topY + t2 * height;

        -- Interpolate colors
        local r1 = topR + t1 * (bottomR - topR);
        local g1 = topG + t1 * (bottomG - topG);
        local b1 = topB + t1 * (bottomB - topB);
        local r2 = topR + t2 * (bottomR - topR);
        local g2 = topG + t2 * (bottomG - topG);
        local b2 = topB + t2 * (bottomB - topB);

        -- Calculate x bounds at this y level (circle equation)
        local dy1 = y1 - centerY;
        local dy2 = y2 - centerY;
        local halfWidth1 = math.sqrt(math.max(0, radius * radius - dy1 * dy1));
        local halfWidth2 = math.sqrt(math.max(0, radius * radius - dy2 * dy2));

        -- Draw a quad for this strip
        local color1 = imgui.GetColorU32({r1, g1, b1, alpha});
        local color2 = imgui.GetColorU32({r2, g2, b2, alpha});

        drawList:AddRectFilledMultiColor(
            {centerX - halfWidth1, y1},
            {centerX + halfWidth2, y2},
            color1, color1, color2, color2
        );
    end
end

-- Draw a pie slice with vertical gradient
local function DrawGradientPieSlice(drawList, centerX, centerY, radius, startAngle, endAngle, topR, topG, topB, bottomR, bottomG, bottomB, alpha, segments)
    segments = segments or 32;
    local topY = centerY - radius;
    local height = radius * 2;

    -- Build the pie slice as triangles from center
    local angleStep = (endAngle - startAngle) / segments;

    for i = 0, segments - 1 do
        local angle1 = startAngle + i * angleStep;
        local angle2 = startAngle + (i + 1) * angleStep;

        local x1 = centerX + math.cos(angle1) * radius;
        local y1 = centerY + math.sin(angle1) * radius;
        local x2 = centerX + math.cos(angle2) * radius;
        local y2 = centerY + math.sin(angle2) * radius;

        -- Calculate gradient t values based on y position
        local tCenter = 0.5;  -- Center is middle of gradient
        local t1 = (y1 - topY) / height;
        local t2 = (y2 - topY) / height;

        -- Interpolate colors for each vertex
        local rC = topR + tCenter * (bottomR - topR);
        local gC = topG + tCenter * (bottomG - topG);
        local bC = topB + tCenter * (bottomB - topB);

        local r1 = topR + t1 * (bottomR - topR);
        local g1 = topG + t1 * (bottomG - topG);
        local b1 = topB + t1 * (bottomB - topB);

        local r2 = topR + t2 * (bottomR - topR);
        local g2 = topG + t2 * (bottomG - topG);
        local b2 = topB + t2 * (bottomB - topB);

        -- Use average color for the triangle (ImGui doesn't support per-vertex colors on triangles easily)
        local avgR = (rC + r1 + r2) / 3;
        local avgG = (gC + g1 + g2) / 3;
        local avgB = (bC + b1 + b2) / 3;
        local color = imgui.GetColorU32({avgR, avgG, avgB, alpha});

        drawList:AddTriangleFilled({centerX, centerY}, {x1, y1}, {x2, y2}, color);
    end
end

-- ============================================
-- Draw Ability Icon with Clockwise Fill
-- ============================================
local function DrawAbilityIcon(drawList, x, y, size, timerInfo, colorConfig)
    local radius = size / 2;
    local centerX = x + radius;
    local centerY = y + radius;
    local innerRadius = radius - 2;

    -- Background circle (dark blue)
    local bgColor = imgui.GetColorU32({0.01, 0.07, 0.17, 1.0});
    drawList:AddCircleFilled({centerX, centerY}, radius, bgColor, 32);

    if not timerInfo.isReady and timerInfo.timer > 0 and timerInfo.maxTimer and timerInfo.maxTimer > 0 then
        -- Calculate progress (0 = just started cooldown, 1 = ready)
        local progress = 1.0 - (timerInfo.timer / timerInfo.maxTimer);
        progress = math.max(0, math.min(1, progress));

        if progress > 0 then
            -- Recast color from config (default: yellow)
            local recastHex = (colorConfig and colorConfig.timerRecastColor) or 0xD9FFFF00;
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
        -- Ready indicator from config (default: green)
        local readyHex = (colorConfig and colorConfig.timerReadyColor) or 0xE600FF00;
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

        -- Row 1: Pet Name (left) and HP% (right, same line)
        local nameFontSize = gConfig.petBarNameFontSize or settings.name_font_settings.font_height;
        local vitalsFontSize = gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;

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

        -- Distance text (next to pet name)
        if gConfig.petBarShowDistance then
            local distanceFontSize = gConfig.petBarDistanceFontSize or settings.distance_font_settings.font_height;
            local nameWidth, _ = data.nameText:get_text_size();
            data.distanceText:set_font_height(distanceFontSize);
            data.distanceText:set_text(string.format('%.1f', petDistance));
            data.distanceText:set_position_x(startX + nameWidth + 4);
            data.distanceText:set_position_y(startY + (nameFontSize - distanceFontSize) / 2);
            local distColor = colorConfig.distanceTextColor or 0xFFFFFFFF;
            if data.lastDistanceColor ~= distColor then
                data.distanceText:set_font_color(distColor);
                data.lastDistanceColor = distColor;
            end
            data.distanceText:set_visible(true);
        else
            data.distanceText:set_visible(false);
        end

        -- HP% text (right side of name row)
        if gConfig.petBarShowVitals ~= false then
            data.hpText:set_font_height(vitalsFontSize);
            data.hpText:set_text(tostring(petHpPercent) .. '%');
            data.hpText:set_position_x(startX + barWidth);
            data.hpText:set_position_y(startY + (nameFontSize - vitalsFontSize) / 2);
            local hpColor = colorConfig.hpTextColor or 0xFFFFFFFF;
            if data.lastHpColor ~= hpColor then
                data.hpText:set_font_color(hpColor);
                data.lastHpColor = hpColor;
            end
            data.hpText:set_visible(true);
        end

        imgui.Dummy({totalRowWidth, nameFontSize + 4});

        -- Row 2: HP Bar (full width)
        if gConfig.petBarShowVitals ~= false then
            local hpGradient = GetCustomGradient(colorConfig, 'hpGradient') or {'#e26c6c', '#fa9c9c'};
            local hpBarX, hpBarY = imgui.GetCursorScreenPos();

            progressbar.ProgressBar(
                {{petHpPercent / 100, hpGradient}},
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
