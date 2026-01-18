--[[
    Base Inventory Tracker Module
    Shared functionality for all inventory/storage trackers
]]

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local gdi = require('submodules.gdifonts.include');
local defaultPositions = require('libs.defaultpositions');

local BaseTracker = {};

-- Position save/restore state (shared across all inventory containers)
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

-- Helper function to calculate dot grid offset
local function GetDotOffset(row, column, settings)
    local x = (column * settings.dotRadius * 2) + (settings.dotSpacing * (column - 1));
    local y = (row * settings.dotRadius * 2) + (settings.dotSpacing * (row - 1));
    return x, y;
end

-- Helper function to get used slot color based on thresholds
local function GetUsedSlotColor(usedSlots, colorConfig, threshold1, threshold2)
    if (usedSlots >= threshold2) then
        return colorConfig.usedSlotColorThreshold2;
    elseif (usedSlots >= threshold1) then
        return colorConfig.usedSlotColorThreshold1;
    else
        return colorConfig.usedSlotColor;
    end
end

-- Helper function to convert dot color (RGBA table) to ARGB hex for font
local function DotColorToFontColor(dotColor)
    return ColorTableToARGB(dotColor);
end

-- Helper function to get text color based on thresholds (returns ARGB hex)
local function GetTextColor(usedSlots, colorConfig, threshold1, threshold2, useThresholdColor)
    if useThresholdColor then
        local dotColor = GetUsedSlotColor(usedSlots, colorConfig, threshold1, threshold2);
        return DotColorToFontColor(dotColor);
    else
        return colorConfig.textColor;
    end
end

-- Draw dots for a single container
local function DrawContainerDots(locX, locY, framePaddingX, usedSlots, maxSlots, settings, colorConfig, threshold1, threshold2)
    local emptyColor = colorConfig.emptySlotColor;
    local usedColor = GetUsedSlotColor(usedSlots, colorConfig, threshold1, threshold2);

    local emptyColorArray = {emptyColor.r, emptyColor.g, emptyColor.b, emptyColor.a};
    local usedColorArray = {usedColor.r, usedColor.g, usedColor.b, usedColor.a};

    local groupOffsetX, _ = GetDotOffset(settings.rowCount, settings.columnCount, settings);
    groupOffsetX = groupOffsetX + settings.groupSpacing;
    local numPerGroup = settings.rowCount * settings.columnCount;

    for i = 1, maxSlots do
        local groupNum = math.ceil(i / numPerGroup);
        local offsetFromGroup = i - ((groupNum - 1) * numPerGroup);

        local rowNum = math.ceil(offsetFromGroup / settings.columnCount);
        local columnNum = offsetFromGroup - ((rowNum - 1) * settings.columnCount);
        local x, y = GetDotOffset(rowNum, columnNum, settings);
        x = x + ((groupNum - 1) * groupOffsetX);

        if (i > usedSlots) then
            draw_circle({x + locX + framePaddingX, y + locY}, settings.dotRadius, emptyColorArray, settings.dotRadius * 3, true)
        else
            draw_circle({x + locX + framePaddingX, y + locY}, settings.dotRadius, usedColorArray, settings.dotRadius * 3, true)
            draw_circle({x + locX + framePaddingX, y + locY}, settings.dotRadius, emptyColorArray, settings.dotRadius * 3, false)
        end
    end
end

-- Calculate window size for dots display
local function CalculateDotsWindowSize(maxSlots, settings)
    local groupOffsetX, groupOffsetY = GetDotOffset(settings.rowCount, settings.columnCount, settings);
    groupOffsetX = groupOffsetX + settings.groupSpacing;
    local numPerGroup = settings.rowCount * settings.columnCount;
    local totalGroups = math.ceil(maxSlots / numPerGroup);

    local style = imgui.GetStyle();
    local framePaddingX = style.FramePadding.x;
    local windowPaddingX = style.WindowPadding.x;
    local windowPaddingY = style.WindowPadding.y;
    local outlineThickness = 1;

    local winSizeX = (groupOffsetX * totalGroups) - settings.groupSpacing + settings.dotRadius + framePaddingX + windowPaddingX + outlineThickness;
    local winSizeY = groupOffsetY + settings.dotRadius + windowPaddingY + outlineThickness;

    return winSizeX, winSizeY, groupOffsetX, totalGroups;
end

-- Draw a single container window (used for both combined and per-container modes)
-- label: optional prefix like "W1" or "S2" for per-container mode
-- textUseThresholdColor: if true, text color follows dot threshold colors
local function DrawSingleContainerWindow(windowName, usedSlots, maxSlots, settings, colorConfig, threshold1, threshold2, textFont, lastTextColorRef, showDots, showText, label, textUseThresholdColor)
    -- If showText is requested but font is nil, disable text to prevent errors
    if showText and textFont == nil then
        showText = false;
    end

    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);

    local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus, ImGuiWindowFlags_NoDocking);
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    -- For text-only mode, remove window padding so the draggable area matches the text exactly
    if not showDots then
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    end

    local fontVisible = false;

    -- Handle position reset or restore
    if forcePositionReset then
        local defX, defY = defaultPositions.GetInventoryPosition();
        imgui.SetNextWindowPos({defX, defY}, ImGuiCond_Always);
        forcePositionReset = false;
        hasAppliedSavedPosition = true;
        lastSavedPosX, lastSavedPosY = defX, defY;
    elseif not hasAppliedSavedPosition and gConfig.inventoryWindowPosX ~= nil then
        imgui.SetNextWindowPos({gConfig.inventoryWindowPosX, gConfig.inventoryWindowPosY}, ImGuiCond_Once);
        hasAppliedSavedPosition = true;
        lastSavedPosX = gConfig.inventoryWindowPosX;
        lastSavedPosY = gConfig.inventoryWindowPosY;
    end

    if (imgui.Begin(windowName, true, windowFlags)) then
        local locX, locY = imgui.GetWindowPos();

        -- Save position if moved (with change detection to avoid spam)
        if not gConfig.lockPositions then
            if lastSavedPosX == nil or
               math.abs(locX - lastSavedPosX) > 1 or
               math.abs(locY - lastSavedPosY) > 1 then
                gConfig.inventoryWindowPosX = locX;
                gConfig.inventoryWindowPosY = locY;
                lastSavedPosX = locX;
                lastSavedPosY = locY;
            end
        end

        local style = imgui.GetStyle();
        local framePaddingX = style.FramePadding.x;

        -- DEBUG: Set to true to visualize draggable areas
        local DEBUG_DRAW = false;

        if showDots then
            local winSizeX, winSizeY, groupOffsetX, totalGroups = CalculateDotsWindowSize(maxSlots > 0 and maxSlots or 30, settings);

            -- Calculate text dimensions if showing text (needed for combined draggable area)
            local textWidth, textHeight = 0, 0;
            if showText then
                textFont:set_font_height(settings.font_settings.font_height);
                local displayText = (label and (label .. ' ') or '') .. usedSlots .. '/' .. maxSlots;
                textFont:set_text(displayText);
                textWidth, textHeight = textFont:get_text_size();
            end

            -- Create dummy that covers both text (above) and dots areas for dragging
            local totalHeight = winSizeY + (showText and textHeight or 0);
            imgui.Dummy({winSizeX, totalHeight});

            -- DEBUG: Draw red rectangle around draggable area
            if DEBUG_DRAW then
                local draw_list = imgui.GetWindowDrawList();
                draw_list:AddRect({locX, locY}, {locX + winSizeX, locY + totalHeight}, 0xFF0000FF, 0, 0, 2);
            end

            -- Dots are drawn below the text
            local dotsOffsetY = showText and textHeight or 0;
            DrawContainerDots(locX, locY + dotsOffsetY, framePaddingX, usedSlots, maxSlots, settings, colorConfig, threshold1, threshold2);

            if showText then
                -- Position text above the dots, right-aligned to the actual dots edge
                -- Font is right-aligned, so position_x is the RIGHT edge of text
                local dotsWidth = (groupOffsetX * totalGroups) - settings.groupSpacing + settings.dotRadius;
                textFont:set_position_x(locX + framePaddingX + dotsWidth);
                textFont:set_position_y(locY);

                local textColor = GetTextColor(usedSlots, colorConfig, threshold1, threshold2, textUseThresholdColor);
                if (lastTextColorRef.color ~= textColor) then
                    textFont:set_font_color(textColor);
                    lastTextColorRef.color = textColor;
                end
                fontVisible = true;
            end
        elseif showText then
            -- Text-only mode
            textFont:set_font_height(settings.font_settings.font_height);
            local displayText = (label and (label .. ' ') or '') .. usedSlots .. '/' .. maxSlots;
            textFont:set_text(displayText);
            local textWidth, textHeight = textFont:get_text_size();

            -- Get cursor position (where content actually starts, after window padding)
            local cursorX, cursorY = imgui.GetCursorScreenPos();

            -- Create invisible dummy for dragging that matches text size
            imgui.Dummy({textWidth, textHeight});

            -- DEBUG: Draw red rectangle around draggable area
            if DEBUG_DRAW then
                local draw_list = imgui.GetWindowDrawList();
                draw_list:AddRect({cursorX, cursorY}, {cursorX + textWidth, cursorY + textHeight}, 0xFF0000FF, 0, 0, 2);
            end

            -- Position text at cursor position (over the dummy area)
            -- Font is right-aligned by default, so position_x is the RIGHT edge of text
            -- We need to set it to cursorX + textWidth so text renders starting at cursorX
            textFont:set_position_x(cursorX + textWidth);
            textFont:set_position_y(cursorY);

            local textColor = GetTextColor(usedSlots, colorConfig, threshold1, threshold2, textUseThresholdColor);
            if (lastTextColorRef.color ~= textColor) then
                textFont:set_font_color(textColor);
                lastTextColorRef.color = textColor;
            end
            fontVisible = true;
        end
    end
    imgui.End();

    -- Pop the style var if we pushed it for text-only mode
    if not showDots then
        imgui.PopStyleVar(1);
    end

    return fontVisible;
end

-- Create a new tracker instance
-- config: { windowName, containers (array of container IDs), configPrefix, colorKey, containerNames (optional) }
function BaseTracker.Create(config)
    local tracker = {};

    -- Font storage - we need one font per potential container for per-container mode
    local fonts = {};  -- Array of fonts, index matches container index
    local lastTextColors = {};  -- Array of {color = value} refs for each font
    local maxContainers = #config.containers;

    tracker.DrawWindow = function(settings)
        local player = GetPlayerSafe();
        if (player == nil) then
            for i = 1, maxContainers do
                if fonts[i] then fonts[i]:set_visible(false); end
            end
            return;
        end

        local mainJob = player:GetMainJob();
        if (player.isZoning or mainJob == 0) then
            for i = 1, maxContainers do
                if fonts[i] then fonts[i]:set_visible(false); end
            end
            return;
        end

        local inventory = GetInventorySafe();
        if (inventory == nil) then
            for i = 1, maxContainers do
                if fonts[i] then fonts[i]:set_visible(false); end
            end
            return;
        end

        -- Gather container data
        local containers = {};
        local totalUsed = 0;
        local totalMax = 0;
        local anyUnlocked = false;
        local unlockedCount = 0;

        for i, containerId in ipairs(config.containers) do
            local used = inventory:GetContainerCount(containerId);
            local max = inventory:GetContainerCountMax(containerId);
            containers[i] = { used = used, max = max, unlocked = (max > 0), id = containerId };
            totalUsed = totalUsed + used;
            totalMax = totalMax + max;
            if max > 0 then
                anyUnlocked = true;
                unlockedCount = unlockedCount + 1;
            end
        end

        -- If no containers are unlocked, hide all
        if not anyUnlocked then
            for i = 1, maxContainers do
                if fonts[i] then fonts[i]:set_visible(false); end
            end
            return;
        end

        local colorConfig = gConfig.colorCustomization[config.colorKey];
        local threshold1 = gConfig[config.configPrefix .. 'ColorThreshold1'];
        local threshold2 = gConfig[config.configPrefix .. 'ColorThreshold2'];
        local showDots = settings.showDots;
        local showText = settings.showText;
        local showPerContainer = settings.showPerContainer;
        local textUseThresholdColor = settings.textUseThresholdColor;

        local showLabels = settings.showLabels;

        -- Per-container mode: each unlocked container gets its own window
        if showPerContainer and #config.containers > 1 then
            local fontIndex = 1;
            for i, container in ipairs(containers) do
                if container.unlocked then
                    local windowName = config.windowName .. '_' .. i;
                    local label = (showLabels and config.containerLabels) and config.containerLabels[i] or nil;
                    local fontVisible = DrawSingleContainerWindow(
                        windowName,
                        container.used,
                        container.max,
                        settings,
                        colorConfig,
                        threshold1,
                        threshold2,
                        fonts[fontIndex],
                        lastTextColors[fontIndex],
                        showDots,
                        showText,
                        label,
                        textUseThresholdColor
                    );
                    if fonts[fontIndex] then
                        fonts[fontIndex]:set_visible(fontVisible);
                    end
                    fontIndex = fontIndex + 1;
                end
            end
            -- Hide unused fonts
            for j = fontIndex, maxContainers do
                if fonts[j] then fonts[j]:set_visible(false); end
            end
        else
            -- Combined mode: single window with all containers combined
            -- Use first label if showLabels is enabled (for single-container trackers or combined multi-container)
            local label = (showLabels and config.containerLabels) and config.containerLabels[1] or nil;
            local fontVisible = DrawSingleContainerWindow(
                config.windowName,
                totalUsed,
                totalMax,
                settings,
                colorConfig,
                threshold1,
                threshold2,
                fonts[1],
                lastTextColors[1],
                showDots,
                showText,
                label,
                textUseThresholdColor
            );
            if fonts[1] then
                fonts[1]:set_visible(fontVisible);
            end
            -- Hide other fonts
            for j = 2, maxContainers do
                if fonts[j] then fonts[j]:set_visible(false); end
            end
        end
    end

    tracker.Initialize = function(settings)
        -- Create fonts for each potential container
        for i = 1, maxContainers do
            fonts[i] = FontManager.create(settings.font_settings);
            lastTextColors[i] = { color = nil };
        end
    end

    tracker.UpdateVisuals = function(settings)
        -- Recreate all fonts
        for i = 1, maxContainers do
            if fonts[i] then
                fonts[i] = FontManager.recreate(fonts[i], settings.font_settings);
            else
                fonts[i] = FontManager.create(settings.font_settings);
            end
            lastTextColors[i] = { color = nil };
        end
    end

    tracker.SetHidden = function(hidden)
        if (hidden == true) then
            for i = 1, maxContainers do
                if fonts[i] then fonts[i]:set_visible(false); end
            end
        end
    end

    tracker.Cleanup = function()
        for i = 1, maxContainers do
            if fonts[i] then
                fonts[i] = FontManager.destroy(fonts[i]);
            end
        end
        fonts = {};
        lastTextColors = {};
    end

    return tracker;
end

-- Reset position for all inventory windows (shared state)
BaseTracker.ResetPositions = function()
    forcePositionReset = true;
    hasAppliedSavedPosition = false;
end

return BaseTracker;
