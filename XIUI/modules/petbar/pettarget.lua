--[[
* XIUI Pet Bar - Pet Target Module
* Displays information about what the pet is targeting
* Separate window that appears below the main pet bar
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');

local data = require('modules.petbar.data');

local pettarget = {};

-- ============================================
-- State Variables
-- ============================================

-- Font objects
local targetNameText = nil;
local targetHpText = nil;
local targetDistanceText = nil;
local lastTargetColor = nil;
local lastHpColor = nil;
local lastDistanceColor = nil;

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

local function UpdateBackground(x, y, width, height, bgScale, settings)
    if not backgroundPrim then return; end

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
        bgScale = bgScale or 1.0,
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
    -- Only show if pet target tracking is enabled and we have a target
    if gConfig.petBarShowTarget == false or data.petTargetServerId == nil then
        if targetNameText then
            targetNameText:set_visible(false);
        end
        if targetHpText then
            targetHpText:set_visible(false);
        end
        if targetDistanceText then
            targetDistanceText:set_visible(false);
        end
        HideBackground();
        return;
    end

    local targetEnt = data.GetEntityByServerId(data.petTargetServerId);
    if targetEnt == nil or targetEnt.ActorPointer == 0 or targetEnt.HPPercent <= 0 then
        if targetNameText then
            targetNameText:set_visible(false);
        end
        if targetHpText then
            targetHpText:set_visible(false);
        end
        if targetDistanceText then
            targetDistanceText:set_visible(false);
        end
        HideBackground();
        data.petTargetServerId = nil;
        return;
    end

    -- Use cached values from main pet bar
    local windowFlags = data.lastWindowFlags or data.getBaseWindowFlags();
    local petBarColorConfig = data.lastColorConfig or {};
    local totalRowWidth = data.lastTotalRowWidth or 150;

    -- Get pet target specific color config
    local colorConfig = gConfig.colorCustomization and gConfig.colorCustomization.petTarget or {};

    if gConfig.lockPositions then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    if imgui.Begin('PetBarTarget', true, windowFlags) then
        local targetWinPosX, targetWinPosY = imgui.GetWindowPos();
        local targetStartX, targetStartY = imgui.GetCursorScreenPos();

        local targetName = targetEnt.Name or 'Unknown';
        local targetHp = targetEnt.HPPercent;
        local targetDistance = math.sqrt(targetEnt.Distance or 0);
        local targetIndex = targetEnt.TargetIndex or 0;

        local targetFontSize = gConfig.petBarTargetFontSize or gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;
        local vitalsFontSize = gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;
        local distanceFontSize = gConfig.petBarDistanceFontSize or settings.distance_font_settings.font_height;

        -- Bar dimensions (use same width as main pet bar HP bar)
        local barWidth = totalRowWidth;
        local barHeight = settings.barHeight or 12;

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

        -- Row 1: Target Name (left)
        targetNameText:set_font_height(targetFontSize);
        targetNameText:set_text(targetName);

        if nameAbsolute then
            -- Absolute positioning: relative to window top-left
            targetNameText:set_position_x(targetWinPosX + nameOffsetX);
            targetNameText:set_position_y(targetWinPosY + nameOffsetY);
        else
            -- Inline positioning: in layout flow with offsets
            targetNameText:set_position_x(targetStartX + nameOffsetX);
            targetNameText:set_position_y(targetStartY + nameOffsetY);
        end

        local targetColor = colorConfig.targetTextColor or petBarColorConfig.targetTextColor or 0xFFFFFFFF;
        if lastTargetColor ~= targetColor then
            targetNameText:set_font_color(targetColor);
            lastTargetColor = targetColor;
        end
        targetNameText:set_visible(true);

        -- HP% text (right-aligned by default)
        targetHpText:set_font_height(vitalsFontSize);
        targetHpText:set_text(tostring(targetHp) .. '%');

        if hpAbsolute then
            -- Absolute positioning: relative to window top-left
            targetHpText:set_position_x(targetWinPosX + hpOffsetX);
            targetHpText:set_position_y(targetWinPosY + hpOffsetY);
        else
            -- Inline positioning: right side of bar row with offsets
            targetHpText:set_position_x(targetStartX + barWidth + hpOffsetX);
            targetHpText:set_position_y(targetStartY + (targetFontSize - vitalsFontSize) / 2 + hpOffsetY);
        end

        local hpColor = colorConfig.hpTextColor or petBarColorConfig.hpTextColor or 0xFFFFA7A7;
        if lastHpColor ~= hpColor then
            targetHpText:set_font_color(hpColor);
            lastHpColor = hpColor;
        end
        targetHpText:set_visible(true);

        imgui.Dummy({totalRowWidth, targetFontSize + 4});

        -- Row 2: HP Bar with interpolation
        local currentTime = os.clock();
        local hpGradient = GetCustomGradient(colorConfig, 'hpGradient') or {'#e26c6c', '#fb9494'};
        local hpPercentData = HpInterpolation.update('pettarget', targetHp, targetIndex, settings, currentTime, hpGradient);

        progressbar.ProgressBar(hpPercentData, {barWidth, barHeight}, {decorate = gConfig.petBarShowBookends});

        -- Distance text positioning
        targetDistanceText:set_font_height(distanceFontSize);
        targetDistanceText:set_text(string.format('%.1fy', targetDistance));

        if distanceAbsolute then
            -- Absolute positioning: relative to window top-left
            targetDistanceText:set_position_x(targetWinPosX + distanceOffsetX);
            targetDistanceText:set_position_y(targetWinPosY + distanceOffsetY);
        else
            -- Inline positioning: below HP bar in layout flow
            local distanceY = targetStartY + targetFontSize + 4 + barHeight + 2;
            targetDistanceText:set_position_x(targetStartX + distanceOffsetX);
            targetDistanceText:set_position_y(distanceY + distanceOffsetY);
            -- Add dummy for inline layout
            imgui.Dummy({totalRowWidth, distanceFontSize + 2});
        end

        local distanceColor = colorConfig.distanceTextColor or petBarColorConfig.distanceTextColor or 0xFFFFFFFF;
        if lastDistanceColor ~= distanceColor then
            targetDistanceText:set_font_color(distanceColor);
            lastDistanceColor = distanceColor;
        end
        targetDistanceText:set_visible(true);

        -- Update background
        local targetWinWidth, targetWinHeight = imgui.GetWindowSize();
        UpdateBackground(targetWinPosX, targetWinPosY, targetWinWidth, targetWinHeight, settings.bgScale, settings);
    end
    imgui.End();
end

-- ============================================
-- Initialize
-- ============================================
function pettarget.Initialize(settings)
    -- Create fonts
    targetNameText = FontManager.create(settings.vitals_font_settings);

    targetHpText = FontManager.create(settings.vitals_font_settings);
    targetHpText:set_font_alignment(gdi.Alignment.Right);

    targetDistanceText = FontManager.create(settings.distance_font_settings);

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

    -- Create combined background + borders (no middle layer needed for pettarget)
    backgroundPrim = windowBg.create(prim_data, backgroundName, settings.bgScale);
end

-- ============================================
-- UpdateVisuals
-- ============================================
function pettarget.UpdateVisuals(settings)
    -- Recreate fonts
    targetNameText = FontManager.recreate(targetNameText, settings.vitals_font_settings);

    targetHpText = FontManager.recreate(targetHpText, settings.vitals_font_settings);
    targetHpText:set_font_alignment(gdi.Alignment.Right);

    targetDistanceText = FontManager.recreate(targetDistanceText, settings.distance_font_settings);

    -- Clear cached colors
    lastTargetColor = nil;
    lastHpColor = nil;
    lastDistanceColor = nil;

    -- Update background textures if theme changed (use petTarget theme if set, otherwise petBar theme)
    local backgroundName = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    if loadedBgName ~= backgroundName then
        loadedBgName = backgroundName;
        windowBg.setTheme(backgroundPrim, backgroundName, settings.bgScale);
    end
end

-- ============================================
-- SetHidden
-- ============================================
function pettarget.SetHidden(hidden)
    if hidden then
        if targetNameText then
            targetNameText:set_visible(false);
        end
        if targetHpText then
            targetHpText:set_visible(false);
        end
        if targetDistanceText then
            targetDistanceText:set_visible(false);
        end
        HideBackground();
    end
end

-- ============================================
-- Cleanup
-- ============================================
function pettarget.Cleanup()
    targetNameText = FontManager.destroy(targetNameText);
    targetHpText = FontManager.destroy(targetHpText);
    targetDistanceText = FontManager.destroy(targetDistanceText);
    lastTargetColor = nil;
    lastHpColor = nil;
    lastDistanceColor = nil;

    -- Cleanup background primitives using windowbackground library
    if backgroundPrim then
        windowBg.destroy(backgroundPrim);
        backgroundPrim = nil;
    end
end

return pettarget;
