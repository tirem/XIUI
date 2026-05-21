--[[
* XIUI Pet Bar - Pet Target Module
* Displays information about what the pet is targeting
* Separate window that appears below the main pet bar
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');

local data = require('modules.petbar.data');

local pettarget = {};

-- Previous-frame window size cache (used for bg layering below content on the draw list)
local cachedWindowSize = { width = nil, height = nil };

local function DrawBackground(drawList, x, y, width, height, settings)
    -- Get scale from active pet type settings (same pattern as petbar data.lua)
    local petTypeKey = data.GetPetTypeKey();
    local settingsKey = 'petBar' .. petTypeKey:gsub("^%l", string.upper);
    local typeSettings = gConfig[settingsKey] or {};
    -- Prefer pet target's own scale sliders; fall back to the parent pet type
    -- so existing users see no change until they touch the pet target sliders.
    local bgScale = gConfig.petTargetBgScale or typeSettings.bgScale or 1.0;
    local borderScale = gConfig.petTargetBorderScale or typeSettings.borderScale or 1.0;

    local bgTheme = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    local bgOpacity = gConfig.petTargetBackgroundOpacity or gConfig.petBarBackgroundOpacity or 1.0;
    local bgColor = gConfig.colorCustomization and gConfig.colorCustomization.petTarget and gConfig.colorCustomization.petTarget.bgColor or 0xFFFFFFFF;
    local borderColor = gConfig.colorCustomization and gConfig.colorCustomization.petTarget and gConfig.colorCustomization.petTarget.borderColor or 0xFFFFFFFF;
    local borderOpacity = gConfig.petTargetBorderOpacity or gConfig.petBarBorderOpacity or 1.0;

    windowBg.Draw(drawList, x, y, width, height, {
        theme = bgTheme,
        padding = (settings and settings.bgPadding) or data.PADDING,
        paddingY = (settings and settings.bgPaddingY) or data.PADDING,
        bgScale = bgScale,
        borderScale = borderScale,
        bgOpacity = bgOpacity,
        bgColor = bgColor,
        borderSize = (settings and settings.borderSize) or 21,
        bgOffset = (settings and settings.bgOffset) or 1,
        borderOpacity = borderOpacity,
        borderColor = borderColor,
    });
end

-- ============================================
-- DrawWindow
-- ============================================
function pettarget.DrawWindow(settings)
    local isPreview = showConfig and showConfig[1] and gConfig.petBarPreview;

    -- Global UI scale multiplier; applied to raw gConfig.petTarget* / petBarTarget* fallbacks.
    local gs = gConfig.globalScale or 1.0;

    -- Only show if we have a valid pet (prevents showing when "Always Visible" is on but no pet)
    if data.GetPetData() == nil then
        return;
    end

    local targetName, targetHp, targetDistance, targetIndex;

    if isPreview then
        targetName = 'Goblin Mugger';
        targetHp = 72;
        targetDistance = 6.3;
        targetIndex = 999;
    else
        -- Only show if pet target tracking is enabled and we have a target
        if gConfig.petBarShowTarget == false or data.petTargetServerId == nil then
            return;
        end

        -- Check if pet is targeting itself (e.g., after self-buff like Aerial Armor)
        local petEntity = data.GetPetEntity();
        if petEntity and petEntity.ServerId and data.petTargetServerId == petEntity.ServerId then
            return;
        end

        local targetEnt = data.GetEntityByServerId(data.petTargetServerId);
        if targetEnt == nil or targetEnt.ActorPointer == 0 or targetEnt.HPPercent <= 0 then
            data.petTargetServerId = nil;
            return;
        end

        targetName = targetEnt.Name or 'Unknown';
        targetHp = targetEnt.HPPercent;
        targetDistance = math.sqrt(targetEnt.Distance or 0);
        targetIndex = targetEnt.TargetIndex or 0;
    end

    -- Use cached values from main pet bar
    local windowFlags = data.lastWindowFlags or data.getBaseWindowFlags();
    local petBarColorConfig = data.lastColorConfig or {};
    local totalRowWidth = data.lastTotalRowWidth or 150;

    -- Get pet target specific color config
    local colorConfig = gConfig.colorCustomization and gConfig.colorCustomization.petTarget or {};

    -- Handle snap to petbar positioning (anchor: bottom = offset from bottom, top = offset from top so it stays static when buffs change height)
    local snapEnabled = gConfig.petTargetSnapToPetBar;
    local anchor = gConfig.petTargetSnapAnchor or 'bottom';
    local anchorY = (anchor == 'top' and data.lastMainWindowTop) or data.lastMainWindowBottom;
    if snapEnabled and data.lastMainWindowPosX ~= nil and anchorY ~= nil then
        local snapOffsetX = (gConfig.petTargetSnapOffsetX or 0) * gs;
        local snapOffsetY = (gConfig.petTargetSnapOffsetY or 16) * gs;
        local snapX = data.lastMainWindowPosX + snapOffsetX;
        local snapY = anchorY + snapOffsetY;
        imgui.SetNextWindowPos({snapX, snapY}, ImGuiCond_Always);
    end

    if (gConfig.lockPositions and not isPreview) or snapEnabled then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    ApplyWindowPosition('PetBarTarget');
    if imgui.Begin('PetBarTarget', true, windowFlags) then
        SaveWindowPosition('PetBarTarget');
        local targetWinPosX, targetWinPosY = imgui.GetWindowPos();
        local targetStartX, targetStartY = imgui.GetCursorScreenPos();
        local drawList = GetUIDrawList();

        -- Draw background FIRST so it sits beneath text/bars on the draw list.
        -- Window size only known after content; use previous frame's cached size (updated below).
        if cachedWindowSize.width and cachedWindowSize.height then
            DrawBackground(drawList, targetWinPosX, targetWinPosY, cachedWindowSize.width, cachedWindowSize.height, settings);
        end

        imtext.SetConfigFromSettings(settings.vitals_font_settings);

        -- Font sizes: first two fallbacks are raw user values (gs-scaled); third is from adjusted settings (already scaled).
        local rawTargetNameFontSize = gConfig.petBarTargetNameFontSize or gConfig.petBarTargetFontSize;
        local targetNameFontSize = rawTargetNameFontSize and (rawTargetNameFontSize * gs) or settings.vitals_font_settings.font_height;
        local rawTargetHpFontSize = gConfig.petBarTargetHpFontSize or gConfig.petBarVitalsFontSize;
        local targetHpFontSize = rawTargetHpFontSize and (rawTargetHpFontSize * gs) or settings.vitals_font_settings.font_height;
        local rawTargetDistanceFontSize = gConfig.petBarTargetDistanceFontSize or gConfig.petBarDistanceFontSize;
        local targetDistanceFontSize = rawTargetDistanceFontSize and (rawTargetDistanceFontSize * gs) or settings.distance_font_settings.font_height;

        -- Bar dimensions with scale settings (settings.barWidth/Height come from updater, already gs-scaled)
        -- Use the un-HP-scaled base pet bar width so the target HP X slider is
        -- independent of the pet HP X slider.
        local barScaleX = gConfig.petTargetBarScaleX or 1.0;
        local barScaleY = gConfig.petTargetBarScaleY or 1.0;
        local barWidth = (settings.barWidth or 150) * barScaleX;
        local barHeight = (settings.barHeight or 12) * barScaleY;

        -- Get positioning settings (offsets scale with gs)
        local nameAbsolute = gConfig.petTargetNameAbsolute;
        local nameOffsetX = (gConfig.petTargetNameOffsetX or 0) * gs;
        local nameOffsetY = (gConfig.petTargetNameOffsetY or 0) * gs;
        local hpAbsolute = gConfig.petTargetHpAbsolute;
        local hpOffsetX = (gConfig.petTargetHpOffsetX or 0) * gs;
        local hpOffsetY = (gConfig.petTargetHpOffsetY or 0) * gs;
        local distanceAbsolute = gConfig.petTargetDistanceAbsolute;
        local distanceOffsetX = (gConfig.petTargetDistanceOffsetX or 0) * gs;
        local distanceOffsetY = (gConfig.petTargetDistanceOffsetY or 0) * gs;

        -- Row 1: Target Name (left-aligned)
        local targetColor = colorConfig.targetTextColor or petBarColorConfig.targetTextColor or 0xFFFFFFFF;
        local nameW, nameH = imtext.Measure(targetName, targetNameFontSize);
        local nameDrawX, nameDrawY;
        if nameAbsolute then
            -- Absolute positioning: relative to window top-left
            nameDrawX = targetWinPosX + nameOffsetX;
            nameDrawY = targetWinPosY + nameOffsetY;
        else
            -- Inline positioning: in layout flow with offsets
            nameDrawX = targetStartX + nameOffsetX;
            nameDrawY = targetStartY + nameOffsetY;
        end
        imtext.Draw(drawList, targetName, nameDrawX, nameDrawY, targetColor, targetNameFontSize);

        -- HP% text (right-aligned: subtract width to convert from right edge)
        local hpColor = colorConfig.hpTextColor or petBarColorConfig.hpTextColor or 0xFFFFA7A7;
        local hpStr = tostring(targetHp) .. '%';
        local hpW, hpH = imtext.Measure(hpStr, targetHpFontSize);
        local hpDrawX, hpDrawY;
        if hpAbsolute then
            -- Absolute positioning: relative to window top-left
            hpDrawX = targetWinPosX + hpOffsetX - hpW;
            hpDrawY = targetWinPosY + hpOffsetY;
        else
            -- Inline positioning: right side of bar row with offsets
            hpDrawX = targetStartX + barWidth + hpOffsetX - hpW;
            hpDrawY = targetStartY + (targetNameFontSize - targetHpFontSize) / 2 + hpOffsetY;
        end
        imtext.Draw(drawList, hpStr, hpDrawX, hpDrawY, hpColor, targetHpFontSize);

        -- Only add space for name row if name or HP are inline (not absolute)
        if not nameAbsolute or not hpAbsolute then
            imgui.Dummy({barWidth, targetNameFontSize + 4});
        end

        -- Row 2: HP Bar with interpolation
        local currentTime = os.clock();
        local hpGradient = GetCustomGradient(colorConfig, 'hpGradient') or {'#e26c6c', '#fb9494'};
        local hpPercentData = HpInterpolation.update('pettarget', targetHp, targetIndex, settings, currentTime, hpGradient);

        progressbar.ProgressBar(hpPercentData, {barWidth, barHeight}, {decorate = gConfig.petTargetShowBookends or gConfig.petBarShowBookends});

        -- Distance text (left-aligned)
        local distanceColor = colorConfig.distanceTextColor or petBarColorConfig.distanceTextColor or 0xFFFFFFFF;
        local distStr = string.format('%.1f', targetDistance);
        local distDrawX, distDrawY;
        if distanceAbsolute then
            -- Absolute positioning: relative to window top-left
            distDrawX = targetWinPosX + distanceOffsetX;
            distDrawY = targetWinPosY + distanceOffsetY;
        else
            -- Inline positioning: below HP bar in layout flow.
            -- Add the bar's border extent so the text clears the additive border.
            local borderThickness = gConfig.barBorderThickness or 1;
            local barBorderExtent = (borderThickness > 0) and (borderThickness / 2 + 0.5) or 0;
            local distanceY = targetStartY + targetNameFontSize + 4 + barHeight + barBorderExtent + 2;
            distDrawX = targetStartX + distanceOffsetX;
            distDrawY = distanceY + distanceOffsetY;
            -- Add dummy for inline layout
            imgui.Dummy({totalRowWidth, targetDistanceFontSize + 2});
        end
        imtext.Draw(drawList, distStr, distDrawX, distDrawY, distanceColor, targetDistanceFontSize);

        -- Cache window size for next frame's bg draw
        cachedWindowSize.width, cachedWindowSize.height = imgui.GetWindowSize();
    end
    imgui.End();
end

function pettarget.Initialize(settings)
end

function pettarget.UpdateVisuals(settings)
    imtext.Reset();
end

function pettarget.SetHidden(hidden)
end

function pettarget.Cleanup()
end

return pettarget;
