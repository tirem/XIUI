--[[
    Base Inventory Tracker Module
    Shared functionality for all inventory/storage trackers
]]

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local imtext = require('libs.imtext');
local defaultPositions = require('libs.defaultpositions');

local BaseTracker = {};

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

-- Helper function to get text color based on thresholds (returns ARGB hex)
local function GetTextColor(usedSlots, colorConfig, threshold1, threshold2, useThresholdColor)
    if useThresholdColor then
        local dotColor = GetUsedSlotColor(usedSlots, colorConfig, threshold1, threshold2);
        return ColorTableToARGB(dotColor);
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
local function DrawSingleContainerWindow(windowName, usedSlots, maxSlots, settings, colorConfig, threshold1, threshold2, drawList, fontSize, showDots, showText, label, textUseThresholdColor)
    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);

    ApplyWindowPosition(windowName);

    local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus, ImGuiWindowFlags_NoDocking);
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    -- For text-only mode, remove window padding so the draggable area matches the text exactly
    if not showDots then
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    end

    if (imgui.Begin(windowName, true, windowFlags)) then
        SaveWindowPosition(windowName);
        local locX, locY = imgui.GetWindowPos();

        local style = imgui.GetStyle();
        local framePaddingX = style.FramePadding.x;

        -- DEBUG: Set to true to visualize draggable areas
        local DEBUG_DRAW = false;

        if showDots then
            local winSizeX, winSizeY, groupOffsetX, totalGroups = CalculateDotsWindowSize(maxSlots > 0 and maxSlots or 30, settings);

            -- Calculate text dimensions if showing text (needed for combined draggable area)
            local textWidth, textHeight = 0, 0;
            local displayText;
            if showText then
                displayText = (label and (label .. ' ') or '') .. usedSlots .. '/' .. maxSlots;
                textWidth, textHeight = imtext.Measure(displayText, fontSize);
            end

            -- Create dummy that covers both text (above) and dots areas for dragging
            local totalHeight = winSizeY + (showText and textHeight or 0);
            imgui.Dummy({winSizeX, totalHeight});

            -- DEBUG: Draw red rectangle around draggable area
            if DEBUG_DRAW then
                local debugDrawList = imgui.GetWindowDrawList();
                debugDrawList:AddRect({locX, locY}, {locX + winSizeX, locY + totalHeight}, 0xFF0000FF, 0, 0, 2);
            end

            -- Dots are drawn below the text
            local dotsOffsetY = showText and textHeight or 0;
            DrawContainerDots(locX, locY + dotsOffsetY, framePaddingX, usedSlots, maxSlots, settings, colorConfig, threshold1, threshold2);

            if showText then
                -- Position text above the dots, right-aligned to the actual dots edge
                -- Right-aligned: left edge = right edge - textWidth
                local dotsWidth = (groupOffsetX * totalGroups) - settings.groupSpacing + settings.dotRadius;
                local textX = locX + framePaddingX + dotsWidth - textWidth;
                local textColor = GetTextColor(usedSlots, colorConfig, threshold1, threshold2, textUseThresholdColor);
                imtext.Draw(drawList, displayText, textX, locY, textColor, fontSize);
            end
        elseif showText then
            -- Text-only mode
            local displayText = (label and (label .. ' ') or '') .. usedSlots .. '/' .. maxSlots;
            local textWidth, textHeight = imtext.Measure(displayText, fontSize);

            -- Get cursor position (where content actually starts, after window padding)
            local cursorX, cursorY = imgui.GetCursorScreenPos();

            -- Create invisible dummy for dragging that matches text size
            imgui.Dummy({textWidth, textHeight});

            -- DEBUG: Draw red rectangle around draggable area
            if DEBUG_DRAW then
                local debugDrawList = imgui.GetWindowDrawList();
                debugDrawList:AddRect({cursorX, cursorY}, {cursorX + textWidth, cursorY + textHeight}, 0xFF0000FF, 0, 0, 2);
            end

            -- Position text at cursor position (over the dummy area)
            -- Left edge is cursorX (right-aligned equivalent: cursorX + textWidth - textWidth)
            local textColor = GetTextColor(usedSlots, colorConfig, threshold1, threshold2, textUseThresholdColor);
            imtext.Draw(drawList, displayText, cursorX, cursorY, textColor, fontSize);
        end
    end
    imgui.End();

    -- Pop the style var if we pushed it for text-only mode
    if not showDots then
        imgui.PopStyleVar(1);
    end
end

-- Create a new tracker instance
-- config: { windowName, containers (array of container IDs), configPrefix, colorKey, containerNames (optional) }
function BaseTracker.Create(config)
    local tracker = {};

    tracker.DrawWindow = function(settings)
        local player = GetPlayerSafe();
        if (player == nil) then return; end

        local mainJob = player:GetMainJob();
        if (player.isZoning or mainJob == 0) then return; end

        local inventory = GetInventorySafe();
        if (inventory == nil) then return; end

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

        if not anyUnlocked then return; end

        local colorConfig = gConfig.colorCustomization[config.colorKey];
        local threshold1 = gConfig[config.configPrefix .. 'ColorThreshold1'];
        local threshold2 = gConfig[config.configPrefix .. 'ColorThreshold2'];
        local showDots = settings.showDots;
        local showText = settings.showText;
        local showPerContainer = settings.showPerContainer;
        local textUseThresholdColor = settings.textUseThresholdColor;

        local showLabels = settings.showLabels;

        local drawList = GetUIDrawList();
        local fontSize = settings.font_settings.font_height;
        imtext.SetConfigFromSettings(settings.font_settings);

        -- Per-container mode: each unlocked container gets its own window
        if showPerContainer and #config.containers > 1 then
            for i, container in ipairs(containers) do
                if container.unlocked then
                    local windowName = config.windowName .. '_' .. i;
                    local label = (showLabels and config.containerLabels) and config.containerLabels[i] or nil;
                    DrawSingleContainerWindow(
                        windowName,
                        container.used,
                        container.max,
                        settings,
                        colorConfig,
                        threshold1,
                        threshold2,
                        drawList,
                        fontSize,
                        showDots,
                        showText,
                        label,
                        textUseThresholdColor
                    );
                end
            end
        else
            -- Combined mode: single window with all containers combined
            -- Use first label if showLabels is enabled (for single-container trackers or combined multi-container)
            local label = (showLabels and config.containerLabels) and config.containerLabels[1] or nil;
            DrawSingleContainerWindow(
                config.windowName,
                totalUsed,
                totalMax,
                settings,
                colorConfig,
                threshold1,
                threshold2,
                drawList,
                fontSize,
                showDots,
                showText,
                label,
                textUseThresholdColor
            );
        end
    end

    tracker.Initialize = function(settings)
        imtext.SetConfigFromSettings(settings.font_settings);
    end

    tracker.UpdateVisuals = function(settings)
        imtext.Reset();
        imtext.SetConfigFromSettings(settings.font_settings);
    end

    tracker.SetHidden = function(hidden)
    end

    tracker.Cleanup = function()
    end

    return tracker;
end

-- Reset position for all inventory windows
BaseTracker.ResetPositions = function()
    if not gConfig then return; end

    -- Initialize tables if needed
    if not gConfig.appliedPositions then gConfig.appliedPositions = {}; end
    if not gConfig.windowPositions then gConfig.windowPositions = {}; end

    -- Get base position and stagger offset
    local baseX, baseY = defaultPositions.GetInventoryPosition();
    local staggerY = 35;

    -- Tracker window names and their vertical offsets
    local trackerOffsets = {
        ['InventoryTracker'] = 0,
        ['SatchelTracker'] = 1,
        ['SafeTracker'] = 2,
        ['StorageTracker'] = 3,
        ['LockerTracker'] = 4,
        ['WardrobeTracker'] = 5,
    };

    -- Set default positions for each tracker
    for windowName, offsetIndex in pairs(trackerOffsets) do
        gConfig.appliedPositions[windowName] = nil;
        gConfig.windowPositions[windowName] = {
            x = baseX,
            y = baseY + (offsetIndex * staggerY)
        };
    end
end

return BaseTracker;
