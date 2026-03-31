--[[
* XIUI Cast Cost Display Layer
* Handles rendering of cast cost information with imtext and window backgrounds
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');
local shared = require('modules.castcost.shared');
local defaultPositions = require('libs.defaultpositions');

local M = {};

-- Background handle
local bgHandle;

-- Reference height cache keyed by fontSize to avoid re-measuring every frame
local refHeightCache = {};
local REF_STRING = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

local function getRefHeight(fontSettings)
    local h = fontSettings.font_height;
    if refHeightCache[h] then return refHeightCache[h]; end
    imtext.SetConfigFromSettings(fontSettings);
    local _, rh = imtext.Measure(REF_STRING, h);
    refHeightCache[h] = rh;
    return rh;
end

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
local forcePositionReset = false;

-- ============================================
-- Initialization
-- ============================================

function M.Initialize(settings)
    local cc = gConfig.castCost or {};
    bgHandle = windowBg.create(settings.prim_data, cc.backgroundTheme or 'Window1', cc.bgScale or 1.0, cc.borderScale or 1.0);
end

-- ============================================
-- Update Visuals (font/theme changes)
-- ============================================

function M.UpdateVisuals(settings)
    imtext.Reset();
    refHeightCache = {};

    local cc = gConfig.castCost or {};
    if bgHandle then
        windowBg.setTheme(bgHandle, cc.backgroundTheme or 'Window1', cc.bgScale or 1.0, cc.borderScale or 1.0);
    end
end

-- ============================================
-- Visibility Control
-- ============================================

function M.SetHidden(hidden)
    if bgHandle then
        windowBg.hide(bgHandle);
    end
    if hidden then
        windowState.x = nil;
        windowState.y = nil;
        windowState.height = nil;
        shared.Clear();
    end
end

-- ============================================
-- Cleanup
-- ============================================

function M.Cleanup()
    if bgHandle then
        windowBg.destroy(bgHandle);
        bgHandle = nil;
    end
end

-- ============================================
-- Rendering Helpers
-- ============================================

local function formatTime(seconds)
    if seconds == nil or seconds <= 0 then return ''; end
    if seconds >= 60 then
        local mins = math.floor(seconds / 60);
        local secs = seconds % 60;
        return string.format('%dm %ds', mins, secs);
    end
    return string.format('%ds', seconds);
end

local function formatCooldown(seconds)
    if seconds == nil or seconds <= 0 then return ''; end
    if seconds >= 60 then
        local mins = math.floor(seconds / 60);
        local secs = math.floor(seconds % 60);
        return string.format('%d:%02d', mins, secs);
    elseif seconds >= 10 then
        return string.format('%ds', math.floor(seconds));
    else
        return string.format('%.1fs', seconds);
    end
end

-- ============================================
-- Main Render Function
-- ============================================

function M.Render(itemInfo, itemType, settings, colors)
    if itemInfo == nil then
        if bgHandle then
            windowBg.hide(bgHandle);
        end
        shared.Clear();
        return;
    end

    -- Build display strings based on item type
    local nameText = '';
    if settings.showName then
        nameText = itemInfo.name or '';
    end
    local costText = '';
    local timeText = '';
    local hasEnoughMp = true;
    local hasEnoughTp = true;

    local playerMp = 0;
    local playerTp = 0;
    local party = GetPartySafe();
    if party then
        playerMp = party:GetMemberMP(0) or 0;
        playerTp = party:GetMemberTP(0) or 0;
    end

    shared.Update(itemInfo, itemType, playerMp);

    local isOnCooldown = itemInfo.currentRecast and itemInfo.currentRecast > 0;
    local isWeaponSkill = itemInfo.isWeaponSkill;
    if isWeaponSkill then
        hasEnoughTp = playerTp >= 1000;
    end
    local cooldownPercent = 0;
    local cooldownText = '';

    if itemType == 'spell' then
        if itemInfo.mpCost and itemInfo.mpCost > 0 then
            hasEnoughMp = playerMp >= itemInfo.mpCost;
            if settings.showMpCost then
                costText = string.format('MP: %d', itemInfo.mpCost);
            end
        end
        if settings.showRecast and itemInfo.recastDelay and itemInfo.recastDelay > 0 then
            local recastSeconds = itemInfo.recastDelay / 4;
            timeText = string.format('Recast: %s', formatTime(recastSeconds));
        end
        if isOnCooldown and itemInfo.maxRecast and itemInfo.maxRecast > 0 then
            cooldownPercent = 1 - (itemInfo.currentRecast / itemInfo.maxRecast);
            cooldownPercent = math.clamp(cooldownPercent, 0, 1);
            cooldownText = formatCooldown(itemInfo.currentRecast);
        end

    elseif itemType == 'ability' then
        if isWeaponSkill then
            if settings.showTpCost ~= false then
                costText = string.format('TP: %d', playerTp);
            end
        end
        if settings.showRecast and itemInfo.recastDelay and itemInfo.recastDelay > 0 then
            local recastSeconds = itemInfo.recastDelay / 4;
            timeText = string.format('Recast: %s', formatTime(recastSeconds));
        end
        if isOnCooldown and itemInfo.maxRecast and itemInfo.maxRecast > 0 then
            cooldownPercent = 1 - (itemInfo.currentRecast / itemInfo.maxRecast);
            cooldownPercent = math.clamp(cooldownPercent, 0, 1);
            cooldownText = formatCooldown(itemInfo.currentRecast);
        end

    elseif itemType == 'mount' then
        if isOnCooldown and itemInfo.maxRecast and itemInfo.maxRecast > 0 then
            cooldownPercent = 1 - (itemInfo.currentRecast / itemInfo.maxRecast);
            cooldownPercent = math.clamp(cooldownPercent, 0, 1);
            cooldownText = formatCooldown(itemInfo.currentRecast);
        end
    end

    -- Set up ImGui window
    imgui.SetNextWindowSize({ -1, -1 }, ImGuiCond_Always);

    ApplyWindowPosition('CastCost');

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav,
        ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoBringToFrontOnFocus,
        ImGuiWindowFlags_NoDocking
    );
    if gConfig.lockPositions then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    if imgui.Begin('CastCost', true, windowFlags) then
        SaveWindowPosition('CastCost');
        local drawList = GetUIDrawList();
        local cursorX, cursorY = imgui.GetCursorScreenPos();

        -- Measure text with reference heights for baseline alignment
        local nameRefHeight = getRefHeight(settings.name_font_settings);
        imtext.SetConfigFromSettings(settings.name_font_settings);
        local nameWidth = 0;
        if nameText ~= '' then
            nameWidth = imtext.Measure(nameText, settings.name_font_settings.font_height);
        end

        local costRefHeight = getRefHeight(settings.cost_font_settings);
        imtext.SetConfigFromSettings(settings.cost_font_settings);
        local costWidth = 0;
        if costText ~= '' then
            costWidth = imtext.Measure(costText, settings.cost_font_settings.font_height);
        end

        local timeRefHeight = getRefHeight(settings.time_font_settings);
        imtext.SetConfigFromSettings(settings.time_font_settings);
        local timeWidth = 0;
        if timeText ~= '' then
            timeWidth = imtext.Measure(timeText, settings.time_font_settings.font_height);
        end

        local cooldownRefHeight = getRefHeight(settings.cooldown_font_settings);
        imtext.SetConfigFromSettings(settings.cooldown_font_settings);
        local cooldownWidth = imtext.Measure('Next: ready', settings.cooldown_font_settings.font_height);

        -- Calculate total content size using reference heights for consistent line spacing
        local lineSpacing = 2;
        local barHeight = 8 * (settings.barScaleY or 1.0);
        local showCooldown = settings.showCooldown ~= false;
        local contentWidth = math.max(nameWidth, costWidth, timeWidth);
        local contentHeight = 0;
        local hasContent = false;
        if nameText ~= '' then
            contentHeight = nameRefHeight;
            hasContent = true;
        end
        if costText ~= '' then
            if hasContent then
                contentHeight = contentHeight + lineSpacing;
            end
            contentHeight = contentHeight + costRefHeight;
            hasContent = true;
        end
        if timeText ~= '' then
            if hasContent then
                contentHeight = contentHeight + lineSpacing;
            end
            contentHeight = contentHeight + timeRefHeight;
            hasContent = true;
        end
        local cooldownRowHeight = math.max(barHeight, cooldownRefHeight);
        if showCooldown then
            if hasContent then
                contentHeight = contentHeight + lineSpacing;
            end
            contentHeight = contentHeight + cooldownRowHeight;
            hasContent = true;
        end

        local minWidth = settings.minWidth or 100;
        contentWidth = math.max(contentWidth, minWidth);

        local padding = settings.bgPadding or 8;
        local paddingY = settings.bgPaddingY or padding;
        imgui.Dummy({ contentWidth, contentHeight });

        -- Update background
        local cc = gConfig.castCost or {};
        if bgHandle then
            windowBg.update(bgHandle, cursorX, cursorY, contentWidth, contentHeight, {
                theme = cc.backgroundTheme or 'Window1',
                padding = padding,
                paddingY = paddingY,
                bgScale = cc.bgScale or 1.0,
                borderScale = cc.borderScale or 1.0,
                bgOpacity = cc.backgroundOpacity or 1.0,
                bgColor = colors.bgColor or 0xFFFFFFFF,
                borderSize = settings.borderSize or 21,
                bgOffset = settings.bgOffset or 1,
                borderOpacity = cc.borderOpacity or 1.0,
                borderColor = colors.borderColor or 0xFFFFFFFF,
            });
        end

        -- Position and render text using reference heights for consistent spacing
        local yPos = cursorY;

        if nameText ~= '' then
            local isNotReady = isOnCooldown or not hasEnoughMp or not hasEnoughTp;
            local nameColor = isNotReady
                and (colors.nameOnCooldownColor or 0xFF888888)
                or (colors.nameTextColor or 0xFFFFFFFF);
            imtext.SetConfigFromSettings(settings.name_font_settings);
            imtext.Draw(drawList, nameText, cursorX, yPos, nameColor, settings.name_font_settings.font_height);
            yPos = yPos + nameRefHeight + lineSpacing;
        end

        if costText ~= '' then
            local costColor;
            if itemType == 'spell' and not hasEnoughMp then
                costColor = colors.mpNotEnoughColor or 0xFFFF6666;
            elseif isWeaponSkill and not hasEnoughTp then
                costColor = colors.tpNotEnoughColor or 0xFFFF6666;
            elseif isWeaponSkill then
                costColor = colors.tpCostTextColor or 0xFFFFCC00;
            else
                costColor = colors.mpCostTextColor or 0xFFD4FF97;
            end
            imtext.SetConfigFromSettings(settings.cost_font_settings);
            imtext.Draw(drawList, costText, cursorX, yPos, costColor, settings.cost_font_settings.font_height);
            yPos = yPos + costRefHeight + lineSpacing;
        end

        if timeText ~= '' then
            imtext.SetConfigFromSettings(settings.time_font_settings);
            imtext.Draw(drawList, timeText, cursorX, yPos, colors.timeTextColor or 0xFFCCCCCC, settings.time_font_settings.font_height);
            yPos = yPos + timeRefHeight + lineSpacing;
        end

        if showCooldown then
            local textYOffset = (cooldownRowHeight - cooldownRefHeight) / 2;
            imtext.SetConfigFromSettings(settings.cooldown_font_settings);
            local cooldownFontSize = settings.cooldown_font_settings.font_height;

            if isOnCooldown then
                local cooldownColor = colors.cooldownTextColor or 0xFFFFFFFF;
                imtext.Draw(drawList, cooldownText, cursorX, yPos + textYOffset, cooldownColor, cooldownFontSize);

                local timerWidth = imtext.Measure(cooldownText, cooldownFontSize);
                local timerBarGap = 6;
                local barStartX = cursorX + timerWidth + timerBarGap;
                local barWidth = contentWidth - timerWidth - timerBarGap;

                local gradientSetting = colors.cooldownBarGradient;
                local barGradient;
                if gradientSetting then
                    if gradientSetting.enabled and gradientSetting.start and gradientSetting.stop then
                        barGradient = {gradientSetting.start, gradientSetting.stop};
                    elseif gradientSetting.start then
                        barGradient = {gradientSetting.start, gradientSetting.start};
                    else
                        barGradient = {'#44CC44', '#44CC44'};
                    end
                else
                    barGradient = {'#44CC44', '#44CC44'};
                end

                local barYOffset = (cooldownRowHeight - barHeight) / 2;

                local pbDrawList = imgui.GetWindowDrawList();
                progressbar.ProgressBar(
                    {{cooldownPercent, barGradient}},
                    {barWidth, barHeight},
                    {
                        absolutePosition = {barStartX, yPos + barYOffset},
                        decorate = false,
                        drawList = pbDrawList,
                    }
                );
            elseif isWeaponSkill and not hasEnoughTp then
                local notEnoughColor = colors.tpNotEnoughColor or 0xFFFF6666;
                imtext.Draw(drawList, 'Need TP', cursorX, yPos + textYOffset, notEnoughColor, cooldownFontSize);
            elseif itemType == 'spell' and not hasEnoughMp then
                local notEnoughColor = colors.mpNotEnoughColor or 0xFFFF6666;
                imtext.Draw(drawList, 'Need MP', cursorX, yPos + textYOffset, notEnoughColor, cooldownFontSize);
            else
                local readyColor = colors.readyTextColor or 0xFF44CC44;
                imtext.Draw(drawList, 'Ready', cursorX, yPos + textYOffset, readyColor, cooldownFontSize);
            end
        end

        -- Handle bottom alignment
        if settings.alignBottom then
            local winPosX, winPosY = imgui.GetWindowPos();
            local totalHeight = contentHeight + (paddingY * 2);

            if windowState.height ~= nil and windowState.height ~= totalHeight then
                local newPosY = windowState.y + windowState.height - totalHeight;
                imgui.SetWindowPos('CastCost', { winPosX, newPosY });
                winPosY = newPosY;
            end

            windowState.x = winPosX;
            windowState.y = winPosY;
            windowState.height = totalHeight;
        end

        -- Save position when user moves window (check on mouse release)
        if not gConfig.lockPositions then
            local winPosX, winPosY = imgui.GetWindowPos();
            local posChanged = (lastSavedPosX == nil or lastSavedPosY == nil) or
                               (math.abs(winPosX - lastSavedPosX) > 1) or
                               (math.abs(winPosY - lastSavedPosY) > 1);
            if posChanged and not imgui.IsMouseDown(0) then
                local cc2 = gConfig.castCost or {};
                cc2.windowPosX = winPosX;
                cc2.windowPosY = winPosY;
                gConfig.castCost = cc2;
                lastSavedPosX = winPosX;
                lastSavedPosY = winPosY;
            end
        end
    end
    imgui.End();
end

M.ResetPositions = function()
    forcePositionReset = true;
    hasAppliedSavedPosition = false;
end

return M;
