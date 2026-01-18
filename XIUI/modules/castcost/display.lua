--[[
* XIUI Cast Cost Display Layer
* Handles rendering of cast cost information with GDI fonts and window backgrounds
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');
local shared = require('modules.castcost.shared');
local defaultPositions = require('libs.defaultpositions');

local M = {};

-- Font handles
local nameFont;
local costFont;
local timeFont;
local recastFont;    -- Right-aligned for timer on cooldown bar
local cooldownFont;  -- Left-aligned for "Next: ready" text
local allFonts;

-- Background handle
local bgHandle;

-- Cached colors (avoid expensive set_font_color calls)
local lastNameColor;
local lastCostColor;
local lastTimeColor;
local lastRecastColor;
local lastCooldownColor;

-- Reference text heights for baseline alignment (prevents text jumping with descenders)
-- Using strings with descender characters (y, g, j, p, q) to get maximum line height
local nameRefHeight = 0;
local costRefHeight = 0;
local timeRefHeight = 0;
local recastRefHeight = 0;
local cooldownRefHeight = 0;
local lastNameFontHeight = 0;
local lastCostFontHeight = 0;
local lastTimeFontHeight = 0;
local lastRecastFontHeight = 0;
local lastCooldownFontHeight = 0;

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
    -- Create fonts via FontManager
    nameFont = FontManager.create(settings.name_font_settings);
    costFont = FontManager.create(settings.cost_font_settings);
    timeFont = FontManager.create(settings.time_font_settings);
    recastFont = FontManager.create(settings.recast_font_settings);
    cooldownFont = FontManager.create(settings.cooldown_font_settings);
    allFonts = { nameFont, costFont, timeFont, recastFont, cooldownFont };

    -- Create window background (read scale directly from gConfig like partylist does)
    local cc = gConfig.castCost or {};
    bgHandle = windowBg.create(settings.prim_data, cc.backgroundTheme or 'Window1', cc.bgScale or 1.0, cc.borderScale or 1.0);
end

-- ============================================
-- Update Visuals (font/theme changes)
-- ============================================

function M.UpdateVisuals(settings)
    -- Recreate fonts when family/weight changes
    nameFont = FontManager.recreate(nameFont, settings.name_font_settings);
    costFont = FontManager.recreate(costFont, settings.cost_font_settings);
    timeFont = FontManager.recreate(timeFont, settings.time_font_settings);
    recastFont = FontManager.recreate(recastFont, settings.recast_font_settings);
    cooldownFont = FontManager.recreate(cooldownFont, settings.cooldown_font_settings);
    allFonts = { nameFont, costFont, timeFont, recastFont, cooldownFont };

    -- Reset cached colors and reference heights
    lastNameColor = nil;
    lastCostColor = nil;
    lastTimeColor = nil;
    lastRecastColor = nil;
    lastCooldownColor = nil;
    nameRefHeight = 0;
    costRefHeight = 0;
    timeRefHeight = 0;
    recastRefHeight = 0;
    cooldownRefHeight = 0;
    lastNameFontHeight = 0;
    lastCostFontHeight = 0;
    lastTimeFontHeight = 0;
    lastRecastFontHeight = 0;
    lastCooldownFontHeight = 0;

    -- Update background theme (read scale directly from gConfig like partylist does)
    local cc = gConfig.castCost or {};
    if bgHandle then
        windowBg.setTheme(bgHandle, cc.backgroundTheme or 'Window1', cc.bgScale or 1.0, cc.borderScale or 1.0);
    end
end

-- ============================================
-- Visibility Control
-- ============================================

function M.SetHidden(hidden)
    SetFontsVisible(allFonts, not hidden);
    if bgHandle then
        windowBg.hide(bgHandle);
    end
    -- Reset window state when hidden so bottom alignment starts fresh
    if hidden then
        windowState.x = nil;
        windowState.y = nil;
        windowState.height = nil;
        -- Clear shared state when hidden
        shared.Clear();
    end
end

-- ============================================
-- Cleanup
-- ============================================

function M.Cleanup()
    nameFont = FontManager.destroy(nameFont);
    costFont = FontManager.destroy(costFont);
    timeFont = FontManager.destroy(timeFont);
    recastFont = FontManager.destroy(recastFont);
    cooldownFont = FontManager.destroy(cooldownFont);
    allFonts = nil;

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

-- Format cooldown time with decimal for short durations
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
        SetFontsVisible(allFonts, false);
        if bgHandle then
            windowBg.hide(bgHandle);
        end
        -- Clear shared state when no selection
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
    local hasEnoughMp = true; -- Track if player has enough MP for spells
    local hasEnoughTp = true; -- Track if player has enough TP for weapon skills

    -- Get player's current MP and TP for cost comparison
    local playerMp = 0;
    local playerTp = 0;
    local party = GetPartySafe();
    if party then
        playerMp = party:GetMemberMP(0) or 0;
        playerTp = party:GetMemberTP(0) or 0;
    end

    -- Update shared state for other modules (playerbar, partylist) to consume
    shared.Update(itemInfo, itemType, playerMp);

    -- Check if on cooldown (currentRecast > 0 means spell/ability is on cooldown)
    local isOnCooldown = itemInfo.currentRecast and itemInfo.currentRecast > 0;
    -- For weapon skills, also consider "not ready" if not enough TP
    local isWeaponSkill = itemInfo.isWeaponSkill;
    if isWeaponSkill then
        hasEnoughTp = playerTp >= 1000;  -- WS requires at least 1000 TP
    end
    local cooldownPercent = 0;
    local cooldownText = '';

    if itemType == 'spell' then
        -- Spell: Show MP cost, recast
        -- Always check if player has enough MP (even if not displaying cost)
        if itemInfo.mpCost and itemInfo.mpCost > 0 then
            hasEnoughMp = playerMp >= itemInfo.mpCost;
            if settings.showMpCost then
                costText = string.format('MP: %d', itemInfo.mpCost);
            end
        end
        if settings.showRecast and itemInfo.recastDelay and itemInfo.recastDelay > 0 then
            -- RecastDelay is in 1/4 seconds
            local recastSeconds = itemInfo.recastDelay / 4;
            timeText = string.format('Recast: %s', formatTime(recastSeconds));
        end
        -- Calculate cooldown progress
        if isOnCooldown and itemInfo.maxRecast and itemInfo.maxRecast > 0 then
            -- Bar fills up as cooldown progresses (0% at start, 100% when ready)
            cooldownPercent = 1 - (itemInfo.currentRecast / itemInfo.maxRecast);
            cooldownPercent = math.clamp(cooldownPercent, 0, 1);
            cooldownText = formatCooldown(itemInfo.currentRecast);
        end

    elseif itemType == 'ability' then
        -- Ability: Show TP cost for weapon skills, recast for others
        if isWeaponSkill then
            -- Weapon skill: Show TP cost
            if settings.showTpCost ~= false then
                costText = string.format('TP: %d', playerTp);
            end
        end
        if settings.showRecast and itemInfo.recastDelay and itemInfo.recastDelay > 0 then
            -- RecastDelay is in 1/4 seconds
            local recastSeconds = itemInfo.recastDelay / 4;
            timeText = string.format('Recast: %s', formatTime(recastSeconds));
        end
        -- Calculate cooldown progress
        if isOnCooldown and itemInfo.maxRecast and itemInfo.maxRecast > 0 then
            cooldownPercent = 1 - (itemInfo.currentRecast / itemInfo.maxRecast);
            cooldownPercent = math.clamp(cooldownPercent, 0, 1);
            cooldownText = formatCooldown(itemInfo.currentRecast);
        end

    elseif itemType == 'mount' then
        -- Mount: Just show name
        -- No additional info needed
    end

    -- Set up ImGui window
    imgui.SetNextWindowSize({ -1, -1 }, ImGuiCond_Always);

    -- Apply saved position on first render or force reset to default
    local cc = gConfig.castCost or {};
    if forcePositionReset then
        local defX, defY = defaultPositions.GetCastCostPosition();
        imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
        forcePositionReset = false;
        hasAppliedSavedPosition = true;
        lastSavedPosX = defX;
        lastSavedPosY = defY;
    elseif not hasAppliedSavedPosition and cc.windowPosX ~= nil and cc.windowPosY ~= nil then
        imgui.SetNextWindowPos({cc.windowPosX, cc.windowPosY}, ImGuiCond_Once);
        hasAppliedSavedPosition = true;
        lastSavedPosX = cc.windowPosX;
        lastSavedPosY = cc.windowPosY;
    end

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
        local cursorX, cursorY = imgui.GetCursorScreenPos();

        -- Calculate content dimensions
        -- Set font heights and calculate reference heights for baseline alignment
        -- Reference string includes letters with descenders (y, g, j, p, q) to get max line height
        local refString = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

        nameFont:set_font_height(settings.name_font_settings.font_height);
        -- Update reference height when font height changes
        if lastNameFontHeight ~= settings.name_font_settings.font_height then
            nameFont:set_text(refString);
            local _, refH = nameFont:get_text_size();
            nameRefHeight = refH;
            lastNameFontHeight = settings.name_font_settings.font_height;
        end
        nameFont:set_text(nameText);
        local nameWidth, _ = nameFont:get_text_size();
        if nameText == '' then nameWidth = 0; end

        costFont:set_font_height(settings.cost_font_settings.font_height);
        -- Update reference height when font height changes
        if lastCostFontHeight ~= settings.cost_font_settings.font_height then
            costFont:set_text(refString);
            local _, refH = costFont:get_text_size();
            costRefHeight = refH;
            lastCostFontHeight = settings.cost_font_settings.font_height;
        end
        costFont:set_text(costText);
        local costWidth, _ = costFont:get_text_size();
        if costText == '' then costWidth = 0; end

        timeFont:set_font_height(settings.time_font_settings.font_height);
        -- Update reference height when font height changes
        if lastTimeFontHeight ~= settings.time_font_settings.font_height then
            timeFont:set_text(refString);
            local _, refH = timeFont:get_text_size();
            timeRefHeight = refH;
            lastTimeFontHeight = settings.time_font_settings.font_height;
        end
        timeFont:set_text(timeText);
        local timeWidth, _ = timeFont:get_text_size();
        if timeText == '' then timeWidth = 0; end

        -- Recast font for timer text on cooldown bar (right-aligned)
        recastFont:set_font_height(settings.recast_font_settings.font_height);
        if lastRecastFontHeight ~= settings.recast_font_settings.font_height then
            recastFont:set_text(refString);
            local _, refH = recastFont:get_text_size();
            recastRefHeight = refH;
            lastRecastFontHeight = settings.recast_font_settings.font_height;
        end
        recastFont:set_text(cooldownText);

        -- Cooldown font for "Next: ready" text (left-aligned)
        cooldownFont:set_font_height(settings.cooldown_font_settings.font_height);
        if lastCooldownFontHeight ~= settings.cooldown_font_settings.font_height then
            cooldownFont:set_text(refString);
            local _, refH = cooldownFont:get_text_size();
            cooldownRefHeight = refH;
            lastCooldownFontHeight = settings.cooldown_font_settings.font_height;
        end
        cooldownFont:set_text('Next: ready');
        local cooldownWidth, _ = cooldownFont:get_text_size();

        -- Calculate total content size using reference heights for consistent line spacing
        local lineSpacing = 2;
        local barHeight = 8 * (settings.barScaleY or 1.0); -- Base height of 8, scaled by barScaleY
        local showCooldown = settings.showCooldown ~= false; -- Default true
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
        -- Add space for cooldown row if enabled
        -- Use consistent height (max of bar and text) so content doesn't shift
        local cooldownRowHeight = math.max(barHeight, cooldownRefHeight);
        if showCooldown then
            if hasContent then
                contentHeight = contentHeight + lineSpacing;
            end
            contentHeight = contentHeight + cooldownRowHeight;
            hasContent = true;
        end

        -- Minimum size for background (user configurable)
        local minWidth = settings.minWidth or 100;
        contentWidth = math.max(contentWidth, minWidth);

        -- Create dummy for dragging
        local padding = settings.bgPadding or 8;
        local paddingY = settings.bgPaddingY or padding;
        imgui.Dummy({ contentWidth, contentHeight });

        -- Update background (read scale directly from gConfig like partylist does)
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

        -- Position and render fonts using reference heights for consistent spacing
        local yPos = cursorY;

        -- Name (if present)
        if nameText ~= '' then
            nameFont:set_position_x(cursorX);
            nameFont:set_position_y(yPos);
            -- Use greyed out color when on cooldown, not enough MP, or not enough TP
            local isNotReady = isOnCooldown or not hasEnoughMp or not hasEnoughTp;
            local nameColor = isNotReady
                and (colors.nameOnCooldownColor or 0xFF888888)
                or (colors.nameTextColor or 0xFFFFFFFF);
            if lastNameColor ~= nameColor then
                nameFont:set_font_color(nameColor);
                lastNameColor = nameColor;
            end
            yPos = yPos + nameRefHeight + lineSpacing;
        end

        -- Cost (if present)
        if costText ~= '' then
            costFont:set_position_x(cursorX);
            costFont:set_position_y(yPos);
            -- Use "not enough" color if player can't afford the spell/WS
            local costColor;
            if itemType == 'spell' and not hasEnoughMp then
                costColor = colors.mpNotEnoughColor or 0xFFFF6666;
            elseif isWeaponSkill and not hasEnoughTp then
                costColor = colors.tpNotEnoughColor or 0xFFFF6666;
            elseif isWeaponSkill then
                costColor = colors.tpCostTextColor or 0xFFFFCC00;  -- Gold/yellow for TP
            else
                costColor = colors.mpCostTextColor or 0xFFD4FF97;
            end
            if lastCostColor ~= costColor then
                costFont:set_font_color(costColor);
                lastCostColor = costColor;
            end
            yPos = yPos + costRefHeight + lineSpacing;
        end

        -- Time info (if present)
        if timeText ~= '' then
            timeFont:set_position_x(cursorX);
            timeFont:set_position_y(yPos);
            if lastTimeColor ~= colors.timeTextColor then
                timeFont:set_font_color(colors.timeTextColor or 0xFFCCCCCC);
                lastTimeColor = colors.timeTextColor;
            end
            yPos = yPos + timeRefHeight + lineSpacing;
        end

        -- Cooldown row (if enabled)
        -- Uses cooldownFont (left-aligned) for both states with appropriate text/color
        if showCooldown then
            -- Center text vertically within cooldownRowHeight
            local textYOffset = (cooldownRowHeight - cooldownRefHeight) / 2;
            cooldownFont:set_position_x(cursorX);
            cooldownFont:set_position_y(yPos + textYOffset);

            if isOnCooldown then
                -- On cooldown: show timer text + progress bar
                cooldownFont:set_text(cooldownText);
                local cooldownColor = colors.cooldownTextColor or 0xFFFFFFFF;
                if lastCooldownColor ~= cooldownColor then
                    cooldownFont:set_font_color(cooldownColor);
                    lastCooldownColor = cooldownColor;
                end

                -- Get timer text width for bar positioning
                local timerWidth, _ = cooldownFont:get_text_size();
                local timerBarGap = 6;
                local barStartX = cursorX + timerWidth + timerBarGap;
                local barWidth = contentWidth - timerWidth - timerBarGap;

                -- Get gradient colors from settings or use defaults
                local gradientSetting = colors.cooldownBarGradient;
                local barGradient;
                if gradientSetting then
                    if gradientSetting.enabled and gradientSetting.start and gradientSetting.stop then
                        -- Gradient enabled: use start to stop colors
                        barGradient = {gradientSetting.start, gradientSetting.stop};
                    elseif gradientSetting.start then
                        -- Gradient disabled: use solid color (start color)
                        barGradient = {gradientSetting.start, gradientSetting.start};
                    else
                        barGradient = {'#44CC44', '#44CC44'};
                    end
                else
                    barGradient = {'#44CC44', '#44CC44'};
                end

                -- Center bar vertically within cooldownRowHeight
                local barYOffset = (cooldownRowHeight - barHeight) / 2;

                -- Draw the progress bar using the progressbar library
                local drawList = imgui.GetWindowDrawList();
                progressbar.ProgressBar(
                    {{cooldownPercent, barGradient}},
                    {barWidth, barHeight},
                    {
                        absolutePosition = {barStartX, yPos + barYOffset},
                        decorate = false,
                        drawList = drawList,
                    }
                );
            elseif isWeaponSkill and not hasEnoughTp then
                -- Weapon skill without enough TP
                cooldownFont:set_text('Need TP');
                local notEnoughColor = colors.tpNotEnoughColor or 0xFFFF6666;
                if lastCooldownColor ~= notEnoughColor then
                    cooldownFont:set_font_color(notEnoughColor);
                    lastCooldownColor = notEnoughColor;
                end
            elseif itemType == 'spell' and not hasEnoughMp then
                -- Spell without enough MP
                cooldownFont:set_text('Need MP');
                local notEnoughColor = colors.mpNotEnoughColor or 0xFFFF6666;
                if lastCooldownColor ~= notEnoughColor then
                    cooldownFont:set_font_color(notEnoughColor);
                    lastCooldownColor = notEnoughColor;
                end
            else
                -- Ready: show "Ready" text
                cooldownFont:set_text('Ready');
                local readyColor = colors.readyTextColor or 0xFF44CC44;
                if lastCooldownColor ~= readyColor then
                    cooldownFont:set_font_color(readyColor);
                    lastCooldownColor = readyColor;
                end
            end
        end

        -- Show fonts
        nameFont:set_visible(nameText ~= '');
        costFont:set_visible(costText ~= '');
        timeFont:set_visible(timeText ~= '');
        recastFont:set_visible(false); -- No longer used in cooldown display
        cooldownFont:set_visible(showCooldown);

        -- Handle bottom alignment
        if settings.alignBottom then
            local winPosX, winPosY = imgui.GetWindowPos();
            local totalHeight = contentHeight + (paddingY * 2);

            if windowState.height ~= nil and windowState.height ~= totalHeight then
                -- Height changed, adjust Y to keep bottom edge fixed
                local newPosY = windowState.y + windowState.height - totalHeight;
                imgui.SetWindowPos('CastCost', { winPosX, newPosY });
                winPosY = newPosY;
            end

            -- Save current state
            windowState.x = winPosX;
            windowState.y = winPosY;
            windowState.height = totalHeight;
        end

        -- Save position when user moves window (check on mouse release)
        if not gConfig.lockPositions then
            local winPosX, winPosY = imgui.GetWindowPos();
            -- Only save if position changed significantly (avoid floating point noise)
            local posChanged = (lastSavedPosX == nil or lastSavedPosY == nil) or
                               (math.abs(winPosX - lastSavedPosX) > 1) or
                               (math.abs(winPosY - lastSavedPosY) > 1);
            if posChanged and not imgui.IsMouseDown(0) then
                -- Mouse released and position changed - save to settings
                local cc = gConfig.castCost or {};
                cc.windowPosX = winPosX;
                cc.windowPosY = winPosY;
                gConfig.castCost = cc;
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
