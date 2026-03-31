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

-- ============================================
-- State Variables
-- ============================================

-- Background primitives (using windowbackground library)
local backgroundPrim = nil;
local loadedBgName = nil;

-- ============================================
-- Background Helpers
-- ============================================

local function HideBackground()
    if backgroundPrim then
        windowBg.hide(backgroundPrim);
    end
end

local function UpdateBackground(x, y, width, height, settings)
    if not backgroundPrim then return; end

    -- Get scale from active pet type settings (same pattern as petbar data.lua)
    local petTypeKey = data.GetPetTypeKey();
    local settingsKey = 'petBar' .. petTypeKey:gsub("^%l", string.upper);  -- 'petBarAvatar', etc.
    local typeSettings = gConfig[settingsKey] or {};
    local bgScale = typeSettings.bgScale or 1.0;
    local borderScale = typeSettings.borderScale or 1.0;

    local bgTheme = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    local bgOpacity = gConfig.petTargetBackgroundOpacity or gConfig.petBarBackgroundOpacity or 1.0;
    local bgColor = gConfig.colorCustomization and gConfig.colorCustomization.petTarget and gConfig.colorCustomization.petTarget.bgColor or 0xFFFFFFFF;
    local borderColor = gConfig.colorCustomization and gConfig.colorCustomization.petTarget and gConfig.colorCustomization.petTarget.borderColor or 0xFFFFFFFF;
    local borderOpacity = gConfig.petTargetBorderOpacity or gConfig.petBarBorderOpacity or 1.0;

    -- Common options for windowbackground library
    local bgOptions = {
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
    };

    -- Update background and borders using windowbackground library
    windowBg.update(backgroundPrim, x, y, width, height, bgOptions);
end

-- ============================================
-- DrawWindow
-- ============================================
function pettarget.DrawWindow(settings)
    local isPreview = showConfig and showConfig[1] and gConfig.petBarPreview;

    -- Only show if we have a valid pet (prevents showing when "Always Visible" is on but no pet)
    if data.GetPetData() == nil then
        HideBackground();
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
            HideBackground();
            return;
        end

        -- Check if pet is targeting itself (e.g., after self-buff like Aerial Armor)
        local petEntity = data.GetPetEntity();
        if petEntity and petEntity.ServerId and data.petTargetServerId == petEntity.ServerId then
            HideBackground();
            return;
        end

        local targetEnt = data.GetEntityByServerId(data.petTargetServerId);
        if targetEnt == nil or targetEnt.ActorPointer == 0 or targetEnt.HPPercent <= 0 then
            HideBackground();
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
        local snapOffsetX = gConfig.petTargetSnapOffsetX or 0;
        local snapOffsetY = gConfig.petTargetSnapOffsetY or 16;
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

        imtext.SetConfigFromSettings(settings.vitals_font_settings);

        local targetNameFontSize = gConfig.petBarTargetNameFontSize or gConfig.petBarTargetFontSize or settings.vitals_font_settings.font_height;
        local targetHpFontSize = gConfig.petBarTargetHpFontSize or gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;
        local targetDistanceFontSize = gConfig.petBarTargetDistanceFontSize or gConfig.petBarDistanceFontSize or settings.distance_font_settings.font_height;

        -- Bar dimensions with scale settings
        local barScaleX = gConfig.petTargetBarScaleX or 1.0;
        local barScaleY = gConfig.petTargetBarScaleY or 1.0;
        local barWidth = totalRowWidth * barScaleX;
        local barHeight = (settings.barHeight or 12) * barScaleY;

        -- Get positioning settings
        local nameAbsolute = gConfig.petTargetNameAbsolute;
        local nameOffsetX = gConfig.petTargetNameOffsetX or 0;
        local nameOffsetY = gConfig.petTargetNameOffsetY or 0;
        local hpAbsolute = gConfig.petTargetHpAbsolute;
        local hpOffsetX = gConfig.petTargetHpOffsetX or 0;
        local hpOffsetY = gConfig.petTargetHpOffsetY or 0;
        local distanceAbsolute = gConfig.petTargetDistanceAbsolute;
        local distanceOffsetX = gConfig.petTargetDistanceOffsetX or 0;
        local distanceOffsetY = gConfig.petTargetDistanceOffsetY or 0;

        -- Row 1: Target Name (left-aligned)
        local targetColor = colorConfig.targetTextColor or petBarColorConfig.targetTextColor or 0xFFFFFFFF;
        local nameW, nameH = imtext.Measure(targetName, targetNameFontSize);
        local nameDrawX, nameDrawY;
        if nameAbsolute then
            nameDrawX = targetWinPosX + nameOffsetX;
            nameDrawY = targetWinPosY + nameOffsetY;
        else
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
            hpDrawX = targetWinPosX + hpOffsetX - hpW;
            hpDrawY = targetWinPosY + hpOffsetY;
        else
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
            distDrawX = targetWinPosX + distanceOffsetX;
            distDrawY = targetWinPosY + distanceOffsetY;
        else
            local distanceY = targetStartY + targetNameFontSize + 4 + barHeight + 2;
            distDrawX = targetStartX + distanceOffsetX;
            distDrawY = distanceY + distanceOffsetY;
            imgui.Dummy({totalRowWidth, targetDistanceFontSize + 2});
        end
        imtext.Draw(drawList, distStr, distDrawX, distDrawY, distanceColor, targetDistanceFontSize);

        -- Update background
        local targetWinWidth, targetWinHeight = imgui.GetWindowSize();
        UpdateBackground(targetWinPosX, targetWinPosY, targetWinWidth, targetWinHeight, settings);
    end
    imgui.End();
end

-- ============================================
-- Initialize
-- ============================================
function pettarget.Initialize(settings)
    -- Initialize background primitives using windowbackground library
    local prim_data = settings.prim_data or {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };

    -- Load background textures (use petTarget theme if set, otherwise petBar theme)
    local backgroundName = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    loadedBgName = backgroundName;

    -- Get scale from active pet type settings
    local petTypeKey = data.GetPetTypeKey();
    local settingsKey = 'petBar' .. petTypeKey:gsub("^%l", string.upper);
    local typeSettings = gConfig[settingsKey] or {};
    local bgScale = typeSettings.bgScale or 1.0;
    local borderScale = typeSettings.borderScale or 1.0;

    -- Create combined background + borders (no middle layer needed for pettarget)
    backgroundPrim = windowBg.create(prim_data, backgroundName, bgScale, borderScale);
end

-- ============================================
-- UpdateVisuals
-- ============================================
function pettarget.UpdateVisuals(settings)
    imtext.Reset();

    -- Get scale from active pet type settings
    local petTypeKey = data.GetPetTypeKey();
    local settingsKey = 'petBar' .. petTypeKey:gsub("^%l", string.upper);
    local typeSettings = gConfig[settingsKey] or {};
    local bgScale = typeSettings.bgScale or 1.0;
    local borderScale = typeSettings.borderScale or 1.0;

    -- Update background textures if theme changed (use petTarget theme if set, otherwise petBar theme)
    local backgroundName = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    if loadedBgName ~= backgroundName then
        loadedBgName = backgroundName;
        windowBg.setTheme(backgroundPrim, backgroundName, bgScale, borderScale);
    end
end

-- ============================================
-- SetHidden
-- ============================================
function pettarget.SetHidden(hidden)
    if hidden then
        HideBackground();
    end
end

-- ============================================
-- Cleanup
-- ============================================
function pettarget.Cleanup()
    -- Cleanup background primitives using windowbackground library
    if backgroundPrim then
        windowBg.destroy(backgroundPrim);
        backgroundPrim = nil;
    end
end

return pettarget;
