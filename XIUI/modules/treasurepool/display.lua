--[[
* XIUI Treasure Pool - Display Module
* Handles rendering of the treasure pool window
* Supports collapsed (compact) and expanded (detailed) views
* Uses imtext for stateless text rendering (no font lifecycle)
*
* Collapsed view (each item row):
*   - Item icon (24x24, left-aligned)
*   - Item name (after icon)
*   - Highest lot info (middle-right)
*   - Timer text (right-aligned)
*   - Progress bar (bottom of row)
*
* Expanded view adds:
*   - All lotters with lot values
*   - Passers list
*   - Pending party members
*   - Individual lot/pass buttons
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');
local button = require('libs.button');
local TextureManager = require('libs.texturemanager');
local imtext = require('libs.imtext');
local data = require('modules.treasurepool.data');
local actions = require('modules.treasurepool.actions');
local defaultPositions = require('libs.defaultpositions');

local M = {};

-- Position save/restore state
local hasAppliedSavedPosition = false;
local forcePositionReset = false;
local lastSavedPosX, lastSavedPosY = nil, nil;

-- Debug logging (set to true to enable)
local DEBUG_ENABLED = false;
local function debugLog(msg, ...)
    if DEBUG_ENABLED then
        local formatted = string.format('[TP Display] ' .. msg, ...);
        print(formatted);
    end
end

-- ============================================
-- Constants
-- ============================================

local ICON_SIZE = 24;
local ROW_HEIGHT = 32;
local PADDING = 8;
local ICON_TEXT_GAP = 6;
local ROW_SPACING = 4;
local BAR_HEIGHT = 3;

-- ============================================
-- State
-- ============================================

local bgPrimHandle = nil;
local loadedBgTheme = nil;
local selectedTab = 1;

-- ============================================
-- Helper Functions
-- ============================================

local TIMER_GRADIENTS = {
    critical = { '#ff4444', '#ff6666' },
    warning = { '#ffaa44', '#ffcc66' },
    normal = { '#4488ff', '#66aaff' },
};

local function getTimerGradient(remaining)
    if remaining < 60 then
        return TIMER_GRADIENTS.critical;
    elseif remaining < 120 then
        return TIMER_GRADIENTS.warning;
    end
    return TIMER_GRADIENTS.normal;
end

local function getTimerColor(remaining)
    if remaining < 60 then
        return 0xFFFF6666;
    elseif remaining < 120 then
        return 0xFFFFCC66;
    end
    return 0xFFFFFFFF;
end

-- ============================================
-- History View Constants
-- ============================================

local HISTORY_ROW_HEIGHT = 24;
local HISTORY_MAX_VISIBLE = 10;
local historyScrollOffset = 0;
local historyMaxScrollOffset = 0;

-- ============================================
-- Treasure Pool Window
-- ============================================

local EXPANDED_ITEM_HEADER_HEIGHT = 20;
local EXPANDED_MEMBER_ROW_HEIGHT = 12;
local EXPANDED_DETAIL_FONT_SIZE = 9;
local EXPANDED_ITEM_PADDING = 8;
local EXPANDED_MAX_VISIBLE_ITEMS = 3;

local scrollOffset = 0;
local maxScrollOffset = 0;

local function formatLottersList(lotters, maxChars)
    if #lotters == 0 then return '(none)'; end
    local parts = {};
    local totalLen = 0;
    for i, lotter in ipairs(lotters) do
        local entry = string.format('%s (%d)', lotter.name, lotter.lot);
        if totalLen + #entry > maxChars and i > 1 then
            table.insert(parts, '...');
            break;
        end
        table.insert(parts, entry);
        totalLen = totalLen + #entry + 2;
    end
    return table.concat(parts, ', ');
end

local function formatNamesList(list, maxChars)
    if #list == 0 then return '(none)'; end
    local parts = {};
    local totalLen = 0;
    for i, item in ipairs(list) do
        local name = item.name;
        if totalLen + #name > maxChars and i > 1 then
            table.insert(parts, '...');
            break;
        end
        table.insert(parts, name);
        totalLen = totalLen + #name + 2;
    end
    return table.concat(parts, ', ');
end

function M.DrawWindow(settings)
    local poolItems = data.GetSortedPoolItems();
    local historyItems = data.GetWonHistory();

    local hasPoolItems = #poolItems > 0;
    local hasHistoryItems = #historyItems > 0;

    local stateKey = string.format('%d_%s_%s_%d_%d', selectedTab, tostring(hasPoolItems), tostring(hasHistoryItems), #poolItems, #historyItems);
    if M._lastDisplayState ~= stateKey then
        debugLog('DrawWindow: tab=%d hasPool=%s hasHistory=%s poolCount=%d historyCount=%d',
            selectedTab, tostring(hasPoolItems), tostring(hasHistoryItems), #poolItems, #historyItems);
        M._lastDisplayState = stateKey;
    end

    if M._wasHidden then
        debugLog('DrawWindow: Window becoming visible');
        M._wasHidden = false;
    end

    local scaleX = gConfig.treasurePoolScaleX;
    if scaleX == nil or scaleX < 0.5 then scaleX = 1.0; end

    local scaleY = gConfig.treasurePoolScaleY;
    if scaleY == nil or scaleY < 0.5 then scaleY = 1.0; end

    local fontSize = gConfig.treasurePoolFontSize;
    if fontSize == nil or fontSize < 8 then fontSize = 10; end

    local showTitle = true;
    local showTimerBar = gConfig.treasurePoolShowTimerBar ~= false;
    local showTimerText = gConfig.treasurePoolShowTimerText ~= false;
    local showLots = gConfig.treasurePoolShowLots ~= false;
    local bgScale = gConfig.treasurePoolBgScale or 1.0;
    local borderScale = gConfig.treasurePoolBorderScale or 1.0;
    local bgOpacity = gConfig.treasurePoolBackgroundOpacity or 0.87;
    local borderOpacity = gConfig.treasurePoolBorderOpacity or 1.0;
    local bgTheme = gConfig.treasurePoolBackgroundTheme or 'Plain';
    local isExpanded = gConfig.treasurePoolExpanded == true;
    local isMinimized = gConfig.treasurePoolMinimized == true;

    local iconSize = math.floor(ICON_SIZE * scaleY);
    local padding = PADDING;
    local iconTextGap = math.floor(ICON_TEXT_GAP * scaleX);
    local rowSpacing = math.floor(ROW_SPACING * scaleY);
    local barHeight = math.floor(BAR_HEIGHT * scaleY);

    local contentBaseWidth = math.floor(320 * scaleX);
    local windowWidth = contentBaseWidth + (padding * 2);

    local itemRowHeights = {};
    local itemMemberData = {};
    local totalContentHeight = 0;
    local visibleContentHeight = 0;
    local needsScroll = false;

    if hasPoolItems then
        for i, item in ipairs(poolItems) do
            local slot = item.slot;
            if isExpanded then
                local partyData = data.GetMembersByParty(slot);
                partyData.maxMemberRows = data.GetMaxMemberCount(partyData);
                itemMemberData[slot] = partyData;

                local numParties = 0;
                if data.PartyHasMembers(partyData.partyA) then numParties = numParties + 1; end
                if data.PartyHasMembers(partyData.partyB) then numParties = numParties + 1; end
                if data.PartyHasMembers(partyData.partyC) then numParties = numParties + 1; end
                if numParties < 1 then numParties = 1; end

                local memberRows = data.GetMaxMemberCount(partyData);
                if memberRows < 1 then memberRows = 1; end

                local memberRowHeight = math.floor(EXPANDED_MEMBER_ROW_HEIGHT * scaleY);
                local itemPadding = math.floor(EXPANDED_ITEM_PADDING * scaleY);
                local headerRowHeight = math.floor(EXPANDED_ITEM_HEADER_HEIGHT * scaleY);
                local contentRowHeight = math.max(headerRowHeight, iconSize + 4);
                local memberBarGap = 4;

                itemRowHeights[i] = itemPadding + contentRowHeight + (memberRows * memberRowHeight) + memberBarGap + itemPadding + barHeight;
            else
                itemRowHeights[i] = math.floor(ROW_HEIGHT * scaleY);
            end
        end
    end

    if selectedTab == 1 then
        if #poolItems == 0 then
            totalContentHeight = fontSize + 4;
            visibleContentHeight = fontSize + 4;
            scrollOffset = 0;
            maxScrollOffset = 0;
        else
            for i = 1, #poolItems do
                totalContentHeight = totalContentHeight + itemRowHeights[i];
                if i < #poolItems then
                    totalContentHeight = totalContentHeight + rowSpacing;
                end
            end

            visibleContentHeight = totalContentHeight;

            if isExpanded and #poolItems > EXPANDED_MAX_VISIBLE_ITEMS then
                visibleContentHeight = 0;
                for i = 1, EXPANDED_MAX_VISIBLE_ITEMS do
                    visibleContentHeight = visibleContentHeight + itemRowHeights[i];
                    if i < EXPANDED_MAX_VISIBLE_ITEMS then
                        visibleContentHeight = visibleContentHeight + rowSpacing;
                    end
                end
                needsScroll = true;
                maxScrollOffset = totalContentHeight - visibleContentHeight;
            else
                scrollOffset = 0;
                maxScrollOffset = 0;
            end
        end
    else
        local historyRowHeight = math.floor(HISTORY_ROW_HEIGHT * scaleY);
        local historyCount = #historyItems;

        if historyCount == 0 then
            totalContentHeight = fontSize + 4;
            visibleContentHeight = fontSize + 4;
            historyScrollOffset = 0;
            historyMaxScrollOffset = 0;
        else
            totalContentHeight = (historyCount * historyRowHeight) + ((historyCount - 1) * rowSpacing);

            if historyCount > HISTORY_MAX_VISIBLE then
                visibleContentHeight = (HISTORY_MAX_VISIBLE * historyRowHeight) + ((HISTORY_MAX_VISIBLE - 1) * rowSpacing);
                needsScroll = true;
                historyMaxScrollOffset = totalContentHeight - visibleContentHeight;
                if historyScrollOffset > historyMaxScrollOffset then
                    historyScrollOffset = historyMaxScrollOffset;
                end
                if historyScrollOffset < 0 then
                    historyScrollOffset = 0;
                end
            else
                visibleContentHeight = totalContentHeight;
                historyScrollOffset = 0;
                historyMaxScrollOffset = 0;
            end
        end
    end

    local headerHeight = 0;
    if showTitle then
        headerHeight = fontSize + math.floor(6 * scaleY);
    end

    local headerItemGap = showTitle and 4 or 0;
    local totalHeight;
    if isMinimized then
        totalHeight = padding + headerHeight + padding;
    else
        totalHeight = padding + headerHeight + headerItemGap + visibleContentHeight + padding;
    end

    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);

    ApplyWindowPosition('TreasurePool');
    if imgui.Begin('TreasurePool', true, windowFlags) then
        SaveWindowPosition('TreasurePool');
        local startX, startY = imgui.GetCursorScreenPos();
        local drawList = imgui.GetBackgroundDrawList();
        local uiDrawList = GetUIDrawList();

        if not drawList or not uiDrawList then
            imgui.End();
            return;
        end

        imtext.SetConfigFromSettings(settings.font_settings);

        imgui.Dummy({windowWidth, totalHeight});

        local winPosX, winPosY = imgui.GetWindowPos();
        if not gConfig.lockPositions then
            if lastSavedPosX == nil or
               math.abs(winPosX - lastSavedPosX) > 1 or
               math.abs(winPosY - lastSavedPosY) > 1 then
                gConfig.treasurePoolWindowPosX = winPosX;
                gConfig.treasurePoolWindowPosY = winPosY;
                lastSavedPosX = winPosX;
                lastSavedPosY = winPosY;
            end
        end

        if needsScroll and imgui.IsWindowHovered() then
            local wheel = imgui.GetIO().MouseWheel;
            if wheel ~= 0 then
                local scrollSpeed = 30;
                scrollOffset = scrollOffset - (wheel * scrollSpeed);
                if scrollOffset < 0 then scrollOffset = 0; end
                if scrollOffset > maxScrollOffset then scrollOffset = maxScrollOffset; end
            end
        end

        local contentWidth = windowWidth - (padding * 2);
        local contentHeightTotal;
        if isMinimized then
            contentHeightTotal = headerHeight;
        else
            contentHeightTotal = headerHeight + headerItemGap + visibleContentHeight;
        end

        if bgPrimHandle then
            if loadedBgTheme ~= bgTheme then
                loadedBgTheme = bgTheme;
                pcall(function()
                    windowBg.setTheme(bgPrimHandle, bgTheme, bgScale, borderScale);
                end);
            end

            pcall(function()
                local bgColor = 0xFFFFFFFF;
                if bgTheme == 'Plain' then
                    bgColor = 0xFF1A1A1A;
                end

                windowBg.update(bgPrimHandle, startX + padding, startY + padding, contentWidth, contentHeightTotal, {
                    theme = bgTheme,
                    padding = padding,
                    bgScale = bgScale,
                    borderScale = borderScale,
                    bgOpacity = bgOpacity,
                    borderOpacity = borderOpacity,
                    bgColor = bgColor,
                });
            end);
        end

        local y = startY + padding;

        -- Draw header with tabs and action buttons
        if showTitle then
            local btnHeight = fontSize + 6;
            local btnY = y - 1;
            local btnSpacing = 4;
            local tabBtnWidth = fontSize * 4;
            local textBtnWidth = fontSize * 4;
            local toggleSize = btnHeight;

            local TAB_COLORS_SELECTED = {
                normal = 0xDD4a6a8a,
                hovered = 0xDD5a7a9a,
                pressed = 0xDD3a5a7a,
                border = 0xFF2a4a6a,
            };
            local TAB_COLORS_UNSELECTED = {
                normal = 0xAA333333,
                hovered = 0xCC4a4a4a,
                pressed = 0xAA222222,
                border = 0xFF1a1a1a,
            };

            -- Draw Pool tab button
            local poolTabX = startX + padding;
            local poolTabColors = (selectedTab == 1) and TAB_COLORS_SELECTED or TAB_COLORS_UNSELECTED;
            local poolTabClicked = button.DrawPrim('tpTabPool', poolTabX, btnY, tabBtnWidth, btnHeight, {
                colors = poolTabColors,
                tooltip = 'Treasure Pool',
            });
            if poolTabClicked then
                debugLog('Pool tab clicked, setting selectedTab = 1');
                selectedTab = 1;
            end

            -- Draw Pool tab label
            local poolTextW, poolTextH = imtext.Measure('Pool', fontSize);
            poolTextW = poolTextW or (fontSize * 2);
            poolTextH = poolTextH or fontSize;
            local poolTextColor = (selectedTab == 1) and 0xFFFFFFFF or 0xFFAAAAAA;
            imtext.Draw(uiDrawList, 'Pool', poolTabX + (tabBtnWidth - poolTextW) / 2, btnY + (btnHeight - poolTextH) / 2, poolTextColor, fontSize);

            -- Draw History tab button
            local historyTabX = poolTabX + tabBtnWidth + btnSpacing;
            local historyTabColors = (selectedTab == 2) and TAB_COLORS_SELECTED or TAB_COLORS_UNSELECTED;
            local historyTabClicked = button.DrawPrim('tpTabHistory', historyTabX, btnY, tabBtnWidth, btnHeight, {
                colors = historyTabColors,
                tooltip = 'Recent Winners',
            });
            if historyTabClicked then
                debugLog('History tab clicked, setting selectedTab = 2');
                selectedTab = 2;
            end

            -- Draw History tab label
            local histTextW, histTextH = imtext.Measure('History', fontSize);
            histTextW = histTextW or (fontSize * 3);
            histTextH = histTextH or fontSize;
            local histTextColor = (selectedTab == 2) and 0xFFFFFFFF or 0xFFAAAAAA;
            imtext.Draw(uiDrawList, 'History', historyTabX + (tabBtnWidth - histTextW) / 2, btnY + (btnHeight - histTextH) / 2, histTextColor, fontSize);

            -- Pool tab: show Lot All, Pass All, Minimize, Toggle buttons
            if selectedTab == 1 then
                local afterTabsX = historyTabX + tabBtnWidth + btnSpacing;
                local lotAllX = afterTabsX;
                local passAllX = lotAllX + textBtnWidth + btnSpacing;
                local toggleX = startX + windowWidth - padding - toggleSize;
                local minimizeX = toggleX - toggleSize - btnSpacing;

                -- Draw minimize/maximize button
                local minimizeClicked = button.DrawMinimizePrim('tpMinimize', minimizeX, btnY, toggleSize, isMinimized, {
                    colors = button.COLORS_NEUTRAL,
                    tooltip = isMinimized and 'Maximize window' or 'Minimize to header only',
                }, GetUIDrawList());
                if minimizeClicked then
                    gConfig.treasurePoolMinimized = not gConfig.treasurePoolMinimized;
                    SaveSettingsToDisk();
                end

                -- Draw expand/collapse arrow button
                local arrowDirection = isExpanded and 'up' or 'down';
                local toggleClicked = button.DrawArrowPrim('tpToggle', toggleX, btnY, toggleSize, arrowDirection, {
                    colors = button.COLORS_NEUTRAL,
                    tooltip = isMinimized
                        and (isExpanded and 'Maximize and collapse' or 'Maximize and expand')
                        or (isExpanded and 'Collapse' or 'Expand'),
                }, GetUIDrawList());
                if toggleClicked then
                    if isMinimized then
                        gConfig.treasurePoolMinimized = false;
                    end
                    gConfig.treasurePoolExpanded = not gConfig.treasurePoolExpanded;
                    scrollOffset = 0;
                    SaveSettingsToDisk();
                end

                if hasPoolItems then
                    -- Draw Pass All button
                    local passAllClicked = button.DrawPrim('tpPassAll', passAllX, btnY, textBtnWidth, btnHeight, {
                        colors = button.COLORS_NEGATIVE,
                        tooltip = 'Pass on all items',
                    });
                    if passAllClicked then
                        actions.PassAll();
                    end

                    -- Draw Pass All label
                    local passTextW, passTextH = imtext.Measure('Pass All', fontSize);
                    passTextW = passTextW or (fontSize * 2.5);
                    passTextH = passTextH or fontSize;
                    imtext.Draw(uiDrawList, 'Pass All', passAllX + (textBtnWidth - passTextW) / 2, btnY + (btnHeight - passTextH) / 2, 0xFFFFFFFF, fontSize);

                    if (not HzLimitedMode) then
                        -- Draw Lot All button (positive/green)
                        local lotAllClicked = button.DrawPrim('tpLotAll', lotAllX, btnY, textBtnWidth, btnHeight, {
                            colors = button.COLORS_POSITIVE,
                            tooltip = 'Lot on all items',
                        });
                        if lotAllClicked then
                            actions.LotAll();
                        end

                        -- Draw Lot All label
                        local lotTextW, lotTextH = imtext.Measure('Lot All', fontSize);
                        lotTextW = lotTextW or (fontSize * 2);
                        lotTextH = lotTextH or fontSize;
                        imtext.Draw(uiDrawList, 'Lot All', lotAllX + (textBtnWidth - lotTextW) / 2, btnY + (btnHeight - lotTextH) / 2, 0xFFFFFFFF, fontSize);
                    else
                        button.HidePrim('tpLotAll');
                    end
                else
                    button.HidePrim('tpLotAll');
                    button.HidePrim('tpPassAll');
                end

            else
                -- History tab: hide Pool-specific buttons but keep minimize and toggle
                button.HidePrim('tpLotAll');
                button.HidePrim('tpPassAll');

                local toggleX = startX + windowWidth - padding - toggleSize;
                local minimizeX = toggleX - toggleSize - btnSpacing;

                -- Draw minimize button on History tab
                local minimizeClicked = button.DrawMinimizePrim('tpMinimize', minimizeX, btnY, toggleSize, isMinimized, {
                    colors = button.COLORS_NEUTRAL,
                    tooltip = isMinimized and 'Maximize window' or 'Minimize to header only',
                }, GetUIDrawList());
                if minimizeClicked then
                    gConfig.treasurePoolMinimized = not gConfig.treasurePoolMinimized;
                    SaveSettingsToDisk();
                end

                -- Draw expand/collapse arrow button on History tab
                local arrowDirection = isExpanded and 'up' or 'down';
                local toggleClicked = button.DrawArrowPrim('tpToggle', toggleX, btnY, toggleSize, arrowDirection, {
                    colors = button.COLORS_NEUTRAL,
                    tooltip = isMinimized
                        and (isExpanded and 'Maximize and collapse' or 'Maximize and expand')
                        or (isExpanded and 'Collapse' or 'Expand'),
                }, GetUIDrawList());
                if toggleClicked then
                    if isMinimized then
                        gConfig.treasurePoolMinimized = false;
                    end
                    gConfig.treasurePoolExpanded = not gConfig.treasurePoolExpanded;
                    SaveSettingsToDisk();
                end
            end

            y = y + headerHeight + 4;
        else
            button.HidePrim('tpTabPool');
            button.HidePrim('tpTabHistory');
            button.HidePrim('tpMinimize');
            button.HidePrim('tpToggle');
        end

        -- Render content based on selected tab (skip when minimized)
        if isMinimized then
            -- When minimized, hide content buttons only
            for slot = 0, data.MAX_POOL_SLOTS - 1 do
                button.HidePrim(string.format('tpLotItem%d', slot));
                button.HidePrim(string.format('tpPassItem%d', slot));
            end
        elseif selectedTab == 1 then
            -- ============================================
            -- POOL TAB: Show treasure pool items
            -- ============================================

            if not hasPoolItems then
                -- Show "No items" message
                imtext.SetConfigFromSettings(settings.title_font_settings);
                imtext.Draw(uiDrawList, 'No items in pool', startX + padding, y, 0xFF888888, fontSize);
                imtext.SetConfigFromSettings(settings.font_settings);

                for slot = 0, data.MAX_POOL_SLOTS - 1 do
                    button.HidePrim(string.format('tpLotItem%d', slot));
                    button.HidePrim(string.format('tpPassItem%d', slot));
                end
            else

            local usedSlots = {};
            local currentY = y;

            local itemAreaTop = y;
            local itemAreaBottom = y + visibleContentHeight;

            -- Helper to check if a Y position is within visible scroll area
            local function isAreaVisible(areaY, areaH)
                if not needsScroll then return true; end
                local areaBottom = areaY + (areaH or fontSize);
                return areaBottom > itemAreaTop and areaY < itemAreaBottom;
            end

            -- Push clip rect for scrollable area
            if needsScroll then
                drawList:PushClipRect(
                    {startX, itemAreaTop},
                    {startX + windowWidth, itemAreaBottom},
                    true
                );
                uiDrawList:PushClipRect(
                    {startX, itemAreaTop},
                    {startX + windowWidth, itemAreaBottom},
                    true
                );
            end

            -- Draw each item row
            for i, item in ipairs(poolItems) do
                local slot = item.slot;
                usedSlots[slot] = true;

                local rowHeight = itemRowHeights[i];

                local rowY = currentY;
                if needsScroll then
                    rowY = currentY - scrollOffset;
                end

                local itemTop = rowY;
                local itemBottom = rowY + rowHeight;
                local hasAnyOverlap = not needsScroll or (itemBottom > itemAreaTop and itemTop < itemAreaBottom);

                local remaining = data.GetTimeRemaining(slot);
                local progress = remaining / data.POOL_TIMEOUT_SECONDS;

                currentY = currentY + rowHeight + rowSpacing;

                if not hasAnyOverlap then
                    button.HidePrim(string.format('tpLotItem%d', slot));
                    button.HidePrim(string.format('tpPassItem%d', slot));
                else
                    -- Draw border around item row in expanded view
                    local itemPadding = 0;
                    if isExpanded then
                        itemPadding = math.floor(EXPANDED_ITEM_PADDING * scaleY);
                        local borderX1 = startX + padding;
                        local borderY1 = rowY;
                        local borderX2 = startX + windowWidth - padding;
                        local borderY2 = rowY + rowHeight;
                        local borderColor = imgui.GetColorU32({1.0, 1.0, 1.0, 0.2});
                        drawList:AddRect({borderX1, borderY1}, {borderX2, borderY2}, borderColor, 4.0, ImDrawCornerFlags_All, 1.0);
                    end

                    -- 1. Draw item icon
                    local iconTexture = TextureManager.getItemIcon(item.itemId);
                    local iconPtr = TextureManager.getTexturePtr(iconTexture);
                    local iconX = startX + padding + itemPadding;
                    local iconY = rowY + 2 + itemPadding;

                    if iconPtr then
                        drawList:AddImage(iconPtr, {iconX, iconY}, {iconX + iconSize, iconY + iconSize});
                    end

                    local textStartX = iconX + iconSize + iconTextGap;
                    local textY = rowY + 2 + itemPadding;

                    -- 2. Draw item name
                    local itemCanLot, itemValidationError = data.ValidateLotItem(slot);
                    local itemStatus = data.GetPlayerLotStatus(slot);
                    local hasValidationIssue = (not itemCanLot and itemStatus ~= 'lotted' and itemStatus ~= 'passed');

                    local displayName = item.itemName or 'Unknown';
                    if hasValidationIssue then
                        displayName = '[!] ' .. displayName;
                    end
                    local nameColor = hasValidationIssue and 0xFFFFAA44 or 0xFFFFFFFF;
                    imtext.Draw(uiDrawList, displayName, textStartX, textY, nameColor, fontSize);

                    -- Draw tooltip for item name area showing validation error
                    if hasValidationIssue and itemValidationError then
                        local nameWidth, nameHeight = imtext.Measure(displayName, fontSize);
                        nameWidth = nameWidth or 100;
                        nameHeight = nameHeight or fontSize;
                        local mouseX, mouseY = imgui.GetMousePos();
                        if mouseX >= textStartX and mouseX <= textStartX + nameWidth and
                           mouseY >= textY and mouseY <= textY + nameHeight then
                            imgui.SetTooltip(itemValidationError);
                        end
                    end

                    -- 3. Draw timer text
                    local timerText = data.FormatTime(remaining);
                    if showTimerText then
                        local timerW, _ = imtext.Measure(timerText, fontSize);
                        timerW = timerW or 0;
                        local timerColor = getTimerColor(remaining);
                        imtext.Draw(uiDrawList, timerText, startX + windowWidth - padding - itemPadding - timerW, textY, timerColor, fontSize);
                    end

                    -- 4. Draw per-item Lot/Pass buttons (expanded view or explicitly enabled)
                    local showButtons = isExpanded or gConfig.treasurePoolShowButtonsInCollapsed;
                    if showButtons then
                        local itemBtnHeight = fontSize + 4;
                        local itemBtnWidth = fontSize * 2.5;
                        local itemBtnSpacing = 4;
                        local itemBtnY = textY - 1;

                        local btnVisible = isAreaVisible(itemBtnY, itemBtnHeight);

                        local timerWidth = 0;
                        if showTimerText then
                            timerWidth, _ = imtext.Measure(timerText, fontSize);
                            timerWidth = timerWidth or (fontSize * 3);
                        end

                        local passBtnX = startX + windowWidth - padding - itemPadding - timerWidth - itemBtnSpacing - itemBtnWidth;
                        local lotBtnX = passBtnX - itemBtnSpacing - itemBtnWidth;

                        local playerStatus = data.GetPlayerLotStatus(slot);
                        local canLot, validationError = data.ValidateLotItem(slot);
                        local lotDisabled = (playerStatus == 'lotted' or playerStatus == 'passed' or not canLot);
                        local passDisabled = (playerStatus == 'passed');

                        local COLOR_DISABLED_TEXT = 0xFF666666;
                        local COLOR_ENABLED_TEXT = 0xFFFFFFFF;

                        if btnVisible then
                            local lotTooltip = 'Lot on this item';
                            if playerStatus == 'lotted' then
                                lotTooltip = 'Already lotted';
                            elseif playerStatus == 'passed' then
                                lotTooltip = 'Already passed';
                            elseif validationError then
                                lotTooltip = validationError;
                            end

                            -- Draw Lot button
                            local lotBtnId = string.format('tpLotItem%d', slot);
                            local lotItemClicked = button.DrawPrim(lotBtnId, lotBtnX, itemBtnY, itemBtnWidth, itemBtnHeight, {
                                colors = button.COLORS_POSITIVE,
                                tooltip = lotTooltip,
                                disabled = lotDisabled,
                            });
                            if lotItemClicked and not lotDisabled then
                                actions.LotItem(slot);
                            end

                            -- Draw Lot label
                            local lotTextW, lotTextH = imtext.Measure('Lot', fontSize - 1);
                            lotTextW = lotTextW or (fontSize * 1.5);
                            lotTextH = lotTextH or fontSize;
                            local lotTextColor = lotDisabled and COLOR_DISABLED_TEXT or COLOR_ENABLED_TEXT;
                            imtext.Draw(uiDrawList, 'Lot', lotBtnX + (itemBtnWidth - lotTextW) / 2, itemBtnY + (itemBtnHeight - lotTextH) / 2, lotTextColor, fontSize - 1);

                            local passTooltip = 'Pass on this item';
                            if playerStatus == 'passed' then
                                passTooltip = 'Already passed';
                            elseif playerStatus == 'lotted' then
                                passTooltip = 'Pass (withdraw lot)';
                            end

                            -- Draw Pass button
                            local passBtnId = string.format('tpPassItem%d', slot);
                            local passItemClicked = button.DrawPrim(passBtnId, passBtnX, itemBtnY, itemBtnWidth, itemBtnHeight, {
                                colors = button.COLORS_NEGATIVE,
                                tooltip = passTooltip,
                                disabled = passDisabled,
                            });
                            if passItemClicked and not passDisabled then
                                actions.PassItem(slot);
                            end

                            -- Draw Pass label
                            local passTextW, passTextH = imtext.Measure('Pass', fontSize - 1);
                            passTextW = passTextW or (fontSize * 2);
                            passTextH = passTextH or fontSize;
                            local passTextColor = passDisabled and COLOR_DISABLED_TEXT or COLOR_ENABLED_TEXT;
                            imtext.Draw(uiDrawList, 'Pass', passBtnX + (itemBtnWidth - passTextW) / 2, itemBtnY + (itemBtnHeight - passTextH) / 2, passTextColor, fontSize - 1);
                        else
                            button.HidePrim(string.format('tpLotItem%d', slot));
                            button.HidePrim(string.format('tpPassItem%d', slot));
                        end
                    else
                        button.HidePrim(string.format('tpLotItem%d', slot));
                        button.HidePrim(string.format('tpPassItem%d', slot));
                    end

                    -- 5. Draw lot info (collapsed: inline; expanded: member list)
                    if not isExpanded then
                        if showLots and item.winningLot and item.winningLot > 0 then
                            local lotterName = item.winningLotterName or '?';
                            if #lotterName > 10 then
                                lotterName = lotterName:sub(1, 8) .. '..';
                            end
                            local lotText = string.format('%s: %d', lotterName, item.winningLot);

                            local nameWidth, _ = imtext.Measure(displayName, fontSize);
                            nameWidth = nameWidth or 0;
                            local lotX = textStartX + nameWidth + math.floor(10 * scaleX);
                            imtext.Draw(uiDrawList, lotText, lotX, textY, 0xFF88FF88, fontSize - 1);
                        end
                    else
                        -- Expanded view: show member list with lot status
                        local partyData = itemMemberData[slot] or { partyA = {}, partyB = {}, partyC = {} };

                        local activeParties = {};
                        if data.PartyHasMembers(partyData.partyA) then table.insert(activeParties, partyData.partyA); end
                        if data.PartyHasMembers(partyData.partyB) then table.insert(activeParties, partyData.partyB); end
                        if data.PartyHasMembers(partyData.partyC) then table.insert(activeParties, partyData.partyC); end

                        local memberFontSize = fontSize - 2;
                        local numCols = #activeParties;
                        if numCols < 1 then numCols = 1; end
                        local colWidth = math.floor((windowWidth - padding * 2 - itemPadding * 2) / numCols);
                        local memberRowHeightPx = math.floor(EXPANDED_MEMBER_ROW_HEIGHT * scaleY);
                        local headerRowHeight = math.floor(EXPANDED_ITEM_HEADER_HEIGHT * scaleY);
                        local contentRowHeight = math.max(headerRowHeight, iconSize + 4);
                        local memberStartY = rowY + itemPadding + contentRowHeight;
                        local memberStartX = startX + padding + itemPadding;
                        local maxMemberRows = partyData.maxMemberRows or 6;
                        if maxMemberRows < 1 then maxMemberRows = 1; end

                        local dotCycle = math.floor(os.clock() * 2) % 3;
                        local pendingDots = string.rep('.', dotCycle + 1);

                        local COLOR_WINNER = 0xFF88FF88;
                        local COLOR_LOTTED = 0xFFFFFFFF;
                        local COLOR_PENDING = 0xFFFFFF88;
                        local COLOR_PASSED = 0xFFAAAAAA;

                        local winningLot = item.winningLot or 0;

                        for col, partyMembers in ipairs(activeParties) do
                            local colX = memberStartX + (col - 1) * colWidth;

                            for row = 1, maxMemberRows do
                                local member = partyMembers[row];
                                local memberY = memberStartY + (row - 1) * memberRowHeightPx;

                                if member then
                                    local memberDisplayText;
                                    local displayColor;

                                    if member.status == 'lotted' and member.lot then
                                        memberDisplayText = string.format('%s: %d', member.name, member.lot);
                                        if member.lot == winningLot and winningLot > 0 then
                                            displayColor = COLOR_WINNER;
                                        else
                                            displayColor = COLOR_LOTTED;
                                        end
                                    elseif member.status == 'pending' then
                                        memberDisplayText = member.name .. pendingDots;
                                        displayColor = COLOR_PENDING;
                                    else
                                        memberDisplayText = member.name .. ': Passed';
                                        displayColor = COLOR_PASSED;
                                    end
                                    imtext.Draw(uiDrawList, memberDisplayText, colX, memberY, displayColor, memberFontSize);
                                end
                            end
                        end
                    end

                    -- 6. Draw progress bar
                    if showTimerBar then
                        local barY = rowY + rowHeight - barHeight - itemPadding;
                        local barStartX = startX + padding + itemPadding;
                        local barWidth = windowWidth - padding * 2 - itemPadding * 2;

                        local timerGradient = getTimerGradient(remaining);

                        progressbar.ProgressBar(
                            {{math.max(0, math.min(1, progress)), timerGradient}},
                            {barWidth, barHeight},
                            {
                                decorate = false,
                                absolutePosition = {barStartX, barY},
                                drawList = drawList,
                            }
                        );
                    end
                end  -- end hasAnyOverlap check
            end

            -- Pop clip rect after drawing items
            if needsScroll then
                drawList:PopClipRect();
                uiDrawList:PopClipRect();

                -- Draw scroll indicator
                local scrollBarWidth = 4;
                local scrollBarX = startX + windowWidth - padding - scrollBarWidth;
                local scrollBarHeight = visibleContentHeight;
                local scrollThumbHeight = math.max(20, scrollBarHeight * (visibleContentHeight / totalContentHeight));
                local scrollThumbY = itemAreaTop;
                if maxScrollOffset > 0 then
                    scrollThumbY = itemAreaTop + (scrollOffset / maxScrollOffset) * (scrollBarHeight - scrollThumbHeight);
                end

                local trackColor = imgui.GetColorU32({0.2, 0.2, 0.2, 0.5});
                drawList:AddRectFilled({scrollBarX, itemAreaTop}, {scrollBarX + scrollBarWidth, itemAreaBottom}, trackColor, 2.0);

                local thumbColor = imgui.GetColorU32({0.6, 0.6, 0.6, 0.8});
                drawList:AddRectFilled({scrollBarX, scrollThumbY}, {scrollBarX + scrollBarWidth, scrollThumbY + scrollThumbHeight}, thumbColor, 2.0);
            end

            -- Hide buttons for unused slots
            for slot = 0, data.MAX_POOL_SLOTS - 1 do
                if not usedSlots[slot] then
                    button.HidePrim(string.format('tpLotItem%d', slot));
                    button.HidePrim(string.format('tpPassItem%d', slot));
                end
            end

            end  -- end hasPoolItems else block

        else
            -- ============================================
            -- HISTORY TAB: Show recent winners
            -- ============================================

            -- Hide pool buttons when on History tab
            for slot = 0, data.MAX_POOL_SLOTS - 1 do
                button.HidePrim(string.format('tpLotItem%d', slot));
                button.HidePrim(string.format('tpPassItem%d', slot));
            end

            local historyItems = data.GetWonHistory();
            local historyCount = #historyItems;

            if historyCount == 0 then
                -- Show "No history" message
                imtext.SetConfigFromSettings(settings.title_font_settings);
                imtext.Draw(uiDrawList, 'No recent winners', startX + padding, y, 0xFF888888, fontSize);
                imtext.SetConfigFromSettings(settings.font_settings);
            else
                local historyRowHeight = math.floor(HISTORY_ROW_HEIGHT * scaleY);
                local historyIconSize = math.floor(ICON_SIZE * scaleY);

                local historyAreaTop = y;
                local historyAreaBottom = y + visibleContentHeight;

                -- Handle scroll input
                if imgui.IsWindowHovered() and historyMaxScrollOffset > 0 then
                    local wheelY = imgui.GetIO().MouseWheel;
                    if wheelY ~= 0 then
                        local scrollSpeed = historyRowHeight * 2;
                        historyScrollOffset = historyScrollOffset - (wheelY * scrollSpeed);
                        if historyScrollOffset < 0 then historyScrollOffset = 0; end
                        if historyScrollOffset > historyMaxScrollOffset then historyScrollOffset = historyMaxScrollOffset; end
                    end
                end

                local historyNeedsScroll = historyCount > HISTORY_MAX_VISIBLE;
                if historyNeedsScroll then
                    drawList:PushClipRect(
                        {startX, historyAreaTop},
                        {startX + windowWidth, historyAreaBottom},
                        true
                    );
                    uiDrawList:PushClipRect(
                        {startX, historyAreaTop},
                        {startX + windowWidth, historyAreaBottom},
                        true
                    );
                end

                local currentY = y;
                for i, histItem in ipairs(historyItems) do
                    if i > data.MAX_HISTORY_ITEMS then break; end

                    local rowY = currentY;
                    if historyNeedsScroll then
                        rowY = currentY - historyScrollOffset;
                    end

                    local itemTop = rowY;
                    local itemBottom = rowY + historyRowHeight;
                    local isVisible = not historyNeedsScroll or (itemBottom > historyAreaTop and itemTop < historyAreaBottom);

                    currentY = currentY + historyRowHeight + rowSpacing;

                    if isVisible then
                        -- Draw item icon
                        local iconTexture = TextureManager.getItemIcon(histItem.itemId);
                        local iconPtr = TextureManager.getTexturePtr(iconTexture);
                        local iconX = startX + padding;
                        local iconY = rowY + (historyRowHeight - historyIconSize) / 2;

                        if iconPtr then
                            drawList:AddImage(iconPtr, {iconX, iconY}, {iconX + historyIconSize, iconY + historyIconSize});
                        end

                        -- Draw item name
                        local textX = iconX + historyIconSize + iconTextGap;
                        local textY = rowY + 2;

                        imtext.Draw(uiDrawList, histItem.itemName or 'Unknown', textX, textY, 0xFFFFFFFF, fontSize);

                        -- Draw winner info (right-aligned)
                        local winnerText = string.format('%s: %d', histItem.winnerName or '?', histItem.winnerLot or 0);
                        local winnerW, _ = imtext.Measure(winnerText, fontSize);
                        winnerW = winnerW or (fontSize * 6);
                        local scrollbarPadding = historyNeedsScroll and 10 or 0;
                        imtext.Draw(uiDrawList, winnerText, startX + windowWidth - padding - winnerW - scrollbarPadding, textY, 0xFF88FF88, fontSize);
                    end
                end

                if historyNeedsScroll then
                    drawList:PopClipRect();
                    uiDrawList:PopClipRect();

                    local historyTotalContentHeight = (historyCount * historyRowHeight) + ((historyCount - 1) * rowSpacing);

                    local scrollBarWidth = 4;
                    local scrollBarX = startX + windowWidth - padding - scrollBarWidth;
                    local scrollBarHeight = visibleContentHeight;
                    local scrollThumbHeight = math.max(20, scrollBarHeight * (visibleContentHeight / historyTotalContentHeight));
                    local scrollThumbY = historyAreaTop;
                    if historyMaxScrollOffset > 0 then
                        scrollThumbY = historyAreaTop + (historyScrollOffset / historyMaxScrollOffset) * (scrollBarHeight - scrollThumbHeight);
                    end

                    local trackColor = imgui.GetColorU32({0.2, 0.2, 0.2, 0.5});
                    drawList:AddRectFilled({scrollBarX, historyAreaTop}, {scrollBarX + scrollBarWidth, historyAreaBottom}, trackColor, 2.0);

                    local thumbColor = imgui.GetColorU32({0.6, 0.6, 0.6, 0.8});
                    drawList:AddRectFilled({scrollBarX, scrollThumbY}, {scrollBarX + scrollBarWidth, scrollThumbY + scrollThumbHeight}, thumbColor, 2.0);
                end
            end
        end
    end
    imgui.End();
end

function M.HideWindow()
    if not M._wasHidden then
        debugLog('HideWindow called (transitioning to hidden)');
        M._wasHidden = true;
    end

    -- Hide primitive buttons
    button.HidePrim('tpToggle');
    button.HidePrim('tpMinimize');
    button.HidePrim('tpLotAll');
    button.HidePrim('tpPassAll');
    button.HidePrim('tpTabPool');
    button.HidePrim('tpTabHistory');

    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        button.HidePrim(string.format('tpLotItem%d', slot));
        button.HidePrim(string.format('tpPassItem%d', slot));
    end

    if bgPrimHandle then
        windowBg.hide(bgPrimHandle);
    end
end

-- ============================================
-- Lifecycle
-- ============================================

function M.Initialize(settings)
    local bgTheme = gConfig.treasurePoolBackgroundTheme or 'Plain';
    local bgScale = gConfig.treasurePoolBgScale or 1.0;
    local borderScale = gConfig.treasurePoolBorderScale or 1.0;
    loadedBgTheme = bgTheme;

    local primData = {
        visible = false,
        can_focus = false,
        locked = true,
        width = 100,
        height = 100,
    };
    bgPrimHandle = windowBg.create(primData, bgTheme, bgScale, borderScale);
end

function M.UpdateVisuals(settings)
    local bgTheme = gConfig.treasurePoolBackgroundTheme or 'Plain';
    local bgScale = gConfig.treasurePoolBgScale or 1.0;
    local borderScale = gConfig.treasurePoolBorderScale or 1.0;
    if loadedBgTheme ~= bgTheme and bgPrimHandle then
        loadedBgTheme = bgTheme;
        windowBg.setTheme(bgPrimHandle, bgTheme, bgScale, borderScale);
    end
end

function M.SetHidden(hidden)
    if hidden then
        M.HideWindow();
    end
end

function M.Cleanup()
    if bgPrimHandle then
        windowBg.destroy(bgPrimHandle);
        bgPrimHandle = nil;
    end

    button.DestroyPrim('tpToggle');
    button.DestroyPrim('tpMinimize');
    button.DestroyPrim('tpLotAll');
    button.DestroyPrim('tpPassAll');
    button.DestroyPrim('tpTabPool');
    button.DestroyPrim('tpTabHistory');

    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        button.DestroyPrim(string.format('tpLotItem%d', slot));
        button.DestroyPrim(string.format('tpPassItem%d', slot));
    end

    loadedBgTheme = nil;
end

M.ResetPositions = function()
    forcePositionReset = true;
    hasAppliedSavedPosition = false;
end

return M;
