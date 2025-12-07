--[[
* XIUI Pet Bar - Pet Target Module
* Displays information about what the pet is targeting
* Separate window that appears below the main pet bar
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local primitives = require('primitives');

local data = require('modules.petbar.data');

local pettarget = {};

-- ============================================
-- State Variables
-- ============================================

-- Font objects
local targetText = nil;
local lastTargetColor = nil;

-- Background primitives
local backgroundPrim = {};
local loadedBgName = nil;

-- ============================================
-- Background Helpers
-- ============================================

local function HideBackground()
    for _, k in ipairs(data.bgImageKeys) do
        if backgroundPrim[k] then
            backgroundPrim[k].visible = false;
        end
    end
end

local function UpdateBackground(x, y, width, height, bgScale)
    local bgPadding = data.PADDING;
    local bgWidth = width + (bgPadding * 2);
    local bgHeight = height + (bgPadding * 2);
    local bgTheme = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';

    -- Hide border primitives
    backgroundPrim.br.visible = false;
    backgroundPrim.tr.visible = false;
    backgroundPrim.tl.visible = false;
    backgroundPrim.bl.visible = false;

    -- Handle background based on theme
    if bgTheme == '-None-' then
        backgroundPrim.bg.visible = false;
    else
        -- Main background
        backgroundPrim.bg.visible = backgroundPrim.bg.exists;
        backgroundPrim.bg.position_x = x - bgPadding;
        backgroundPrim.bg.position_y = y - bgPadding;
        backgroundPrim.bg.width = bgWidth / (bgScale or 1.0);
        backgroundPrim.bg.height = bgHeight / (bgScale or 1.0);
        -- Apply background color/tint and opacity
        local bgOpacity = gConfig.petTargetBackgroundOpacity or gConfig.petBarBackgroundOpacity or 1.0;
        local bgColor = gConfig.colorCustomization and gConfig.colorCustomization.petTarget and gConfig.colorCustomization.petTarget.bgColor or 0xFFFFFFFF;
        -- Extract RGB from bgColor (ARGB format) and apply opacity
        local bgAlphaByte = math.floor(bgOpacity * 255);
        local bgRGB = bit.band(bgColor, 0x00FFFFFF);
        backgroundPrim.bg.color = bit.bor(bit.lshift(bgAlphaByte, 24), bgRGB);
    end
end

-- ============================================
-- DrawWindow
-- ============================================
function pettarget.DrawWindow(settings)
    -- Only show if pet target tracking is enabled and we have a target
    if gConfig.petBarShowTarget == false or data.petTargetServerId == nil then
        if targetText then
            targetText:set_visible(false);
        end
        HideBackground();
        return;
    end

    local targetEnt = data.GetEntityByServerId(data.petTargetServerId);
    if targetEnt == nil or targetEnt.ActorPointer == 0 or targetEnt.HPPercent <= 0 then
        if targetText then
            targetText:set_visible(false);
        end
        HideBackground();
        data.petTargetServerId = nil;
        return;
    end

    -- Use cached values from main pet bar
    local windowFlags = data.lastWindowFlags or data.getBaseWindowFlags();
    local colorConfig = data.lastColorConfig or {};
    local totalRowWidth = data.lastTotalRowWidth or 150;

    if gConfig.lockPositions then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    if imgui.Begin('PetBarTarget', true, windowFlags) then
        local targetWinPosX, targetWinPosY = imgui.GetWindowPos();
        local targetStartX, targetStartY = imgui.GetCursorScreenPos();

        local targetName = targetEnt.Name or 'Unknown';
        local targetHp = targetEnt.HPPercent;

        local targetFontSize = gConfig.petBarTargetFontSize or gConfig.petBarVitalsFontSize or settings.vitals_font_settings.font_height;
        targetText:set_font_height(targetFontSize);
        targetText:set_text('> ' .. targetName .. ' (' .. tostring(targetHp) .. '%)');
        targetText:set_position_x(targetStartX);
        targetText:set_position_y(targetStartY);

        local targetColor = colorConfig.targetTextColor or 0xFFFFFFFF;
        if lastTargetColor ~= targetColor then
            targetText:set_font_color(targetColor);
            lastTargetColor = targetColor;
        end
        targetText:set_visible(true);

        imgui.Dummy({totalRowWidth, targetFontSize});

        -- Update background
        local targetWinWidth, targetWinHeight = imgui.GetWindowSize();
        UpdateBackground(targetWinPosX, targetWinPosY, targetWinWidth, targetWinHeight, settings.bgScale);
    end
    imgui.End();
end

-- ============================================
-- Initialize
-- ============================================
function pettarget.Initialize(settings)
    -- Create font
    targetText = FontManager.create(settings.vitals_font_settings);

    -- Initialize background primitives
    local prim_data = settings.prim_data or {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };

    for _, k in ipairs(data.bgImageKeys) do
        backgroundPrim[k] = primitives:new(prim_data);
        backgroundPrim[k].visible = false;
        backgroundPrim[k].can_focus = false;
        backgroundPrim[k].exists = false;
    end

    -- Load background textures (use petTarget theme if set, otherwise petBar theme)
    local backgroundName = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    loadedBgName = backgroundName;

    for _, k in ipairs(data.bgImageKeys) do
        if backgroundName == '-None-' then
            backgroundPrim[k].exists = false;
        else
            local file_name = string.format('%s-%s.png', backgroundName, k);
            local filepath = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
            backgroundPrim[k].texture = filepath;
            backgroundPrim[k].exists = ashita.fs.exists(filepath);
        end
        if k == 'bg' then
            backgroundPrim[k].scale_x = settings.bgScale or 1.0;
            backgroundPrim[k].scale_y = settings.bgScale or 1.0;
        else
            backgroundPrim[k].scale_x = 1.0;
            backgroundPrim[k].scale_y = 1.0;
        end
    end
end

-- ============================================
-- UpdateVisuals
-- ============================================
function pettarget.UpdateVisuals(settings)
    -- Recreate font
    targetText = FontManager.recreate(targetText, settings.vitals_font_settings);

    -- Clear cached color
    lastTargetColor = nil;

    -- Update background textures if theme changed (use petTarget theme if set, otherwise petBar theme)
    local backgroundName = gConfig.petTargetBackgroundTheme or gConfig.petBarBackgroundTheme or 'Window1';
    if loadedBgName ~= backgroundName then
        loadedBgName = backgroundName;
        for _, k in ipairs(data.bgImageKeys) do
            if backgroundName == '-None-' then
                backgroundPrim[k].exists = false;
            else
                local file_name = string.format('%s-%s.png', backgroundName, k);
                local filepath = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
                backgroundPrim[k].texture = filepath;
                backgroundPrim[k].exists = ashita.fs.exists(filepath);
            end
        end
    end
end

-- ============================================
-- SetHidden
-- ============================================
function pettarget.SetHidden(hidden)
    if hidden and targetText then
        targetText:set_visible(false);
        HideBackground();
    end
end

-- ============================================
-- Cleanup
-- ============================================
function pettarget.Cleanup()
    targetText = FontManager.destroy(targetText);
    lastTargetColor = nil;

    -- Cleanup primitives
    for _, k in ipairs(data.bgImageKeys) do
        if backgroundPrim[k] then
            backgroundPrim[k]:destroy();
            backgroundPrim[k] = nil;
        end
    end
end

return pettarget;
