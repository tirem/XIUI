--[[
* XIUI Treasure Pool - Display Module
* Handles rendering of the treasure pool window
* Supports collapsed (compact) and expanded (detailed) views
* Fonts are created by init.lua and stored in data module
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
local ffi = require('ffi');
local d3d8 = require('d3d8');
local windowBg = require('libs.windowbackground');
local progressbar = require('libs.progressbar');
local button = require('libs.button');
local data = require('modules.treasurepool.data');
local actions = require('modules.treasurepool.actions');

local M = {};

-- ============================================
-- Constants
-- ============================================

local ICON_SIZE = 24;
local ROW_HEIGHT = 32;  -- Icon (24) + top offset (2) + gap (4) + bar (3) - 1
local PADDING = 8;
local ICON_TEXT_GAP = 6;
local ROW_SPACING = 4;
local BAR_HEIGHT = 3;

-- ============================================
-- State
-- ============================================

-- Background primitive handle
local bgPrimHandle = nil;

-- Theme tracking (for detecting changes like petbar)
local loadedBgTheme = nil;

-- Item icon cache (itemId -> texture table with .image)
local iconCache = {};

-- Tab state: 1 = Pool view, 2 = History view
local selectedTab = 1;

-- ============================================
-- Item Icon Loading
-- ============================================

-- Load item icon from game resources
local function loadItemIcon(itemId)
    if itemId == nil or itemId == 0 or itemId == -1 or itemId == 65535 then
        return nil;
    end

    if iconCache[itemId] then
        return iconCache[itemId];
    end

    local success, result = pcall(function()
        local device = GetD3D8Device();
        if device == nil then return nil; end

        local item = AshitaCore:GetResourceManager():GetItemById(itemId);
        if item == nil then return nil; end

        if item.Bitmap == nil or item.ImageSize == nil or item.ImageSize <= 0 then
            return nil;
        end

        local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileInMemoryEx(
            device, item.Bitmap, item.ImageSize,
            0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
            0xFF000000, nil, nil, dx_texture_ptr
        ) == ffi.C.S_OK then
            return {
                image = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]))
            };
        end
        return nil;
    end);

    if success and result then
        iconCache[itemId] = result;
    end

    return iconCache[itemId];
end

local function getIconPtr(texture)
    if texture and texture.image then
        return tonumber(ffi.cast("uint32_t", texture.image));
    end
    return nil;
end

-- ============================================
-- Helper Functions
-- ============================================

-- Timer gradient colors based on remaining time
local TIMER_GRADIENTS = {
    critical = { '#ff4444', '#ff6666' },  -- < 60s - red
    warning = { '#ffaa44', '#ffcc66' },   -- < 120s - orange/yellow
    normal = { '#4488ff', '#66aaff' },    -- >= 120s - blue
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

local HISTORY_ROW_HEIGHT = 24;  -- Height per history item row
local HISTORY_MAX_VISIBLE = 10; -- Max visible history items before scrolling
local historyScrollOffset = 0;
local historyMaxScrollOffset = 0;

-- ============================================
-- Treasure Pool Window
-- ============================================

-- Constants for expanded view
local EXPANDED_ITEM_HEADER_HEIGHT = 20;  -- Item name + timer row
local EXPANDED_MEMBER_ROW_HEIGHT = 12;   -- Height per member row
local EXPANDED_DETAIL_FONT_SIZE = 9;
local EXPANDED_ITEM_PADDING = 8;         -- Internal padding for expanded items
local EXPANDED_MAX_VISIBLE_ITEMS = 3;    -- Max items visible before scrolling

-- Scroll state for expanded view
local scrollOffset = 0;
local maxScrollOffset = 0;

-- Helper to build a comma-separated list of names with lots
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
        totalLen = totalLen + #entry + 2;  -- +2 for ", "
    end
    return table.concat(parts, ', ');
end

-- Helper to build a comma-separated list of names
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

    -- Show window if either pool has items OR history has items (depending on tab)
    local hasPoolItems = #poolItems > 0;
    local hasHistoryItems = #historyItems > 0;

    -- If no content for either tab, hide window
    if not hasPoolItems and not hasHistoryItems then
        M.HideWindow();
        return;
    end

    -- If on Pool tab with no items, switch to History tab (if history exists)
    if selectedTab == 1 and not hasPoolItems and hasHistoryItems then
        selectedTab = 2;
    end
    -- If on History tab with no items, switch to Pool tab (if pool exists)
    if selectedTab == 2 and not hasHistoryItems and hasPoolItems then
        selectedTab = 1;
    end

    -- Get settings with validation
    local scaleX = gConfig.treasurePoolScaleX;
    if scaleX == nil or scaleX < 0.5 then scaleX = 1.0; end

    local scaleY = gConfig.treasurePoolScaleY;
    if scaleY == nil or scaleY < 0.5 then scaleY = 1.0; end

    local fontSize = gConfig.treasurePoolFontSize;
    if fontSize == nil or fontSize < 8 then fontSize = 10; end

    local showTitle = true;  -- Always show title
    local showTimerBar = gConfig.treasurePoolShowTimerBar ~= false;
    local showTimerText = gConfig.treasurePoolShowTimerText ~= false;
    local showLots = gConfig.treasurePoolShowLots ~= false;
    -- Split background/border settings
    local bgScale = gConfig.treasurePoolBgScale or 1.0;
    local borderScale = gConfig.treasurePoolBorderScale or 1.0;
    local bgOpacity = gConfig.treasurePoolBackgroundOpacity or 0.87;
    local borderOpacity = gConfig.treasurePoolBorderOpacity or 1.0;
    local bgTheme = gConfig.treasurePoolBackgroundTheme or 'Plain';
    local isExpanded = gConfig.treasurePoolExpanded == true;
    local isMinimized = gConfig.treasurePoolMinimized == true;

    -- Calculate dimensions (different for expanded vs collapsed)
    local iconSize = math.floor(ICON_SIZE * scaleY);
    local padding = PADDING;
    local iconTextGap = math.floor(ICON_TEXT_GAP * scaleX);
    local rowSpacing = math.floor(ROW_SPACING * scaleY);
    local barHeight = math.floor(BAR_HEIGHT * scaleY);

    -- Fixed width for both expanded and collapsed views
    local contentBaseWidth = math.floor(320 * scaleX);
    local windowWidth = contentBaseWidth + (padding * 2);

    -- Pre-calculate row heights and member data for expanded view (always needed for Pool tab)
    local itemRowHeights = {};
    local itemMemberData = {};  -- Cache member data to avoid recalculating
    local totalContentHeight = 0;
    local visibleContentHeight = 0;
    local needsScroll = false;

    -- Always calculate pool item heights (needed when switching back to Pool tab)
    if hasPoolItems then
        for i, item in ipairs(poolItems) do
            local slot = item.slot;
            if isExpanded then
                -- Get party members organized by party (A, B, C columns)
                local partyData = data.GetMembersByParty(slot);
                -- Cache max member count for rendering
                partyData.maxMemberRows = data.GetMaxMemberCount(partyData);
                itemMemberData[slot] = partyData;

                -- Count active parties to determine column count
                local numParties = 0;
                if data.PartyHasMembers(partyData.partyA) then numParties = numParties + 1; end
                if data.PartyHasMembers(partyData.partyB) then numParties = numParties + 1; end
                if data.PartyHasMembers(partyData.partyC) then numParties = numParties + 1; end
                if numParties < 1 then numParties = 1; end

                -- Dynamic row count based on max members across all parties
                local memberRows = data.GetMaxMemberCount(partyData);
                if memberRows < 1 then memberRows = 1; end  -- Minimum 1 row

                -- Height = header + member rows + padding + progress bar
                local memberRowHeight = math.floor(EXPANDED_MEMBER_ROW_HEIGHT * scaleY);
                local itemPadding = math.floor(EXPANDED_ITEM_PADDING * scaleY);
                local headerRowHeight = math.floor(EXPANDED_ITEM_HEADER_HEIGHT * scaleY);
                -- Content row must fit icon (24px) + small offset, use max of header or icon height
                local contentRowHeight = math.max(headerRowHeight, iconSize + 4);
                local memberBarGap = 4;  -- Gap between member list and progress bar

                itemRowHeights[i] = itemPadding + contentRowHeight + (memberRows * memberRowHeight) + memberBarGap + itemPadding + barHeight;
            else
                itemRowHeights[i] = math.floor(ROW_HEIGHT * scaleY);
            end
        end
    end

    if selectedTab == 1 then
        -- Pool tab: calculate content height based on pool items
        for i = 1, #poolItems do
            totalContentHeight = totalContentHeight + itemRowHeights[i];
            if i < #poolItems then
                totalContentHeight = totalContentHeight + rowSpacing;
            end
        end

        -- Calculate visible content height (limited in expanded view)
        visibleContentHeight = totalContentHeight;

        if isExpanded and #poolItems > EXPANDED_MAX_VISIBLE_ITEMS then
            -- Calculate height for first N items only
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
    else
        -- History tab: calculate based on history items
        local historyRowHeight = math.floor(HISTORY_ROW_HEIGHT * scaleY);
        local historyCount = #historyItems;

        if historyCount == 0 then
            -- "No recent winners" message height
            totalContentHeight = fontSize + 4;
            visibleContentHeight = fontSize + 4;
            historyScrollOffset = 0;
            historyMaxScrollOffset = 0;
        else
            totalContentHeight = (historyCount * historyRowHeight) + ((historyCount - 1) * rowSpacing);

            if historyCount > HISTORY_MAX_VISIBLE then
                -- Limit visible height to max visible items
                visibleContentHeight = (HISTORY_MAX_VISIBLE * historyRowHeight) + ((HISTORY_MAX_VISIBLE - 1) * rowSpacing);
                needsScroll = true;
                historyMaxScrollOffset = totalContentHeight - visibleContentHeight;
                -- Clamp scroll offset
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

    local headerItemGap = showTitle and 4 or 0;  -- Gap between header and items
    -- When minimized, only show header bar
    local totalHeight;
    if isMinimized then
        totalHeight = padding + headerHeight + padding;
    else
        totalHeight = padding + headerHeight + headerItemGap + visibleContentHeight + padding;
    end

    -- Build window flags
    local windowFlags = GetBaseWindowFlags(gConfig.lockPositions);

    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);

    if imgui.Begin('TreasurePool', true, windowFlags) then
        local startX, startY = imgui.GetCursorScreenPos();
        local drawList = imgui.GetBackgroundDrawList();

        -- Safety check for draw list
        if not drawList then
            imgui.End();
            return;
        end

        imgui.Dummy({windowWidth, totalHeight});

        -- Handle scroll input when hovering over window
        if needsScroll and imgui.IsWindowHovered() then
            local wheel = imgui.GetIO().MouseWheel;
            if wheel ~= 0 then
                local scrollSpeed = 30;  -- Pixels per scroll tick
                scrollOffset = scrollOffset - (wheel * scrollSpeed);
                -- Clamp scroll offset
                if scrollOffset < 0 then scrollOffset = 0; end
                if scrollOffset > maxScrollOffset then scrollOffset = maxScrollOffset; end
            end
        end

        -- Calculate content area
        local contentWidth = windowWidth - (padding * 2);
        local contentHeightTotal;
        if isMinimized then
            contentHeightTotal = headerHeight;
        else
            contentHeightTotal = headerHeight + headerItemGap + visibleContentHeight;
        end

        -- Update background (with safety checks)
        if bgPrimHandle then
            -- Check if theme changed
            if loadedBgTheme ~= bgTheme then
                loadedBgTheme = bgTheme;
                pcall(function()
                    windowBg.setTheme(bgPrimHandle, bgTheme, bgScale, borderScale);
                end);
            end

            pcall(function()
                -- For themed backgrounds (Window1-8), use white so texture shows through
                -- For Plain backgrounds, use dark color with opacity
                local bgColor = 0xFFFFFFFF;  -- White (no tint) for themed backgrounds
                if bgTheme == 'Plain' then
                    bgColor = 0xFF1A1A1A;  -- Dark gray for plain background
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
            -- Button sizing (uses fontSize from config)
            local btnHeight = fontSize + 6;
            local btnY = y - 1;
            local btnSpacing = 4;
            local tabBtnWidth = fontSize * 4;  -- Tab button width
            local textBtnWidth = fontSize * 4;  -- Wider for "Lot All" / "Pass All" text
            local toggleSize = btnHeight;  -- Square for arrow

            -- Tab colors
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

            -- Draw Pool tab
            local poolTabX = startX + padding;
            local poolTabColors = (selectedTab == 1) and TAB_COLORS_SELECTED or TAB_COLORS_UNSELECTED;
            local poolTabClicked = button.DrawPrim('tpTabPool', poolTabX, btnY, tabBtnWidth, btnHeight, {
                colors = poolTabColors,
                tooltip = 'Treasure Pool',
            });
            if poolTabClicked then
                selectedTab = 1;
            end

            -- Draw Pool tab label
            if data.tabPoolFont then
                data.tabPoolFont:set_font_height(fontSize);
                data.tabPoolFont:set_text('Pool');
                local poolTextW, poolTextH = data.tabPoolFont:get_text_size();
                poolTextW = poolTextW or (fontSize * 2);
                poolTextH = poolTextH or fontSize;
                data.tabPoolFont:set_position_x(poolTabX + (tabBtnWidth - poolTextW) / 2);
                data.tabPoolFont:set_position_y(btnY + (btnHeight - poolTextH) / 2);
                data.tabPoolFont:set_visible(true);
                local poolTextColor = (selectedTab == 1) and 0xFFFFFFFF or 0xFFAAAAAA;
                if data.lastColors.tabPool ~= poolTextColor then
                    data.tabPoolFont:set_font_color(poolTextColor);
                    data.lastColors.tabPool = poolTextColor;
                end
            end

            -- Draw History tab
            local historyTabX = poolTabX + tabBtnWidth + btnSpacing;
            local historyTabColors = (selectedTab == 2) and TAB_COLORS_SELECTED or TAB_COLORS_UNSELECTED;
            local historyTabClicked = button.DrawPrim('tpTabHistory', historyTabX, btnY, tabBtnWidth, btnHeight, {
                colors = historyTabColors,
                tooltip = 'Recent Winners',
            });
            if historyTabClicked then
                selectedTab = 2;
            end

            -- Draw History tab label
            if data.tabHistoryFont then
                data.tabHistoryFont:set_font_height(fontSize);
                data.tabHistoryFont:set_text('History');
                local histTextW, histTextH = data.tabHistoryFont:get_text_size();
                histTextW = histTextW or (fontSize * 3);
                histTextH = histTextH or fontSize;
                data.tabHistoryFont:set_position_x(historyTabX + (tabBtnWidth - histTextW) / 2);
                data.tabHistoryFont:set_position_y(btnY + (btnHeight - histTextH) / 2);
                data.tabHistoryFont:set_visible(true);
                local histTextColor = (selectedTab == 2) and 0xFFFFFFFF or 0xFFAAAAAA;
                if data.lastColors.tabHistory ~= histTextColor then
                    data.tabHistoryFont:set_font_color(histTextColor);
                    data.lastColors.tabHistory = histTextColor;
                end
            end

            -- Hide the old header font (replaced by tabs)
            if data.headerFont then
                data.headerFont:set_visible(false);
            end

            -- Pool tab: show Lot All, Pass All, Minimize, Toggle buttons
            if selectedTab == 1 then
                -- Position: [Pool] [History] [Lot All] [Pass All] ... [Minimize] [Toggle]
                local afterTabsX = historyTabX + tabBtnWidth + btnSpacing;
                local lotAllX = afterTabsX;
                local passAllX = lotAllX + textBtnWidth + btnSpacing;
                local toggleX = startX + windowWidth - padding - toggleSize;
                local minimizeX = toggleX - toggleSize - btnSpacing;

                -- Draw minimize/maximize button using primitive
                local minimizeClicked = button.DrawMinimizePrim('tpMinimize', minimizeX, btnY, toggleSize, isMinimized, {
                    colors = button.COLORS_NEUTRAL,
                    tooltip = isMinimized and 'Maximize window' or 'Minimize to header only',
                }, imgui.GetForegroundDrawList());
                if minimizeClicked then
                    gConfig.treasurePoolMinimized = not gConfig.treasurePoolMinimized;
                    SaveSettingsToDisk();
                end

                -- Draw expand/collapse arrow button using primitive
                local arrowDirection = isExpanded and 'up' or 'down';
                local toggleClicked = button.DrawArrowPrim('tpToggle', toggleX, btnY, toggleSize, arrowDirection, {
                    colors = button.COLORS_NEUTRAL,
                    tooltip = isMinimized
                        and (isExpanded and 'Maximize and collapse' or 'Maximize and expand')
                        or (isExpanded and 'Collapse' or 'Expand'),
                }, imgui.GetForegroundDrawList());
                if toggleClicked then
                    -- If minimized, maximize first then apply expand/collapse
                    if isMinimized then
                        gConfig.treasurePoolMinimized = false;
                    end
                    gConfig.treasurePoolExpanded = not gConfig.treasurePoolExpanded;
                    scrollOffset = 0;  -- Reset scroll when toggling
                    SaveSettingsToDisk();
                end

                -- Draw Pass All button (Always enabled)
                local passAllClicked = button.DrawPrim('tpPassAll', passAllX, btnY, textBtnWidth, btnHeight, {
                    colors = button.COLORS_NEGATIVE,
                    tooltip = 'Pass on all items',
                });
                if passAllClicked then
                    actions.PassAll();
                end

                -- Draw Pass All label (GDI font renders on top of primitive)
                if data.passAllFont then
                    data.passAllFont:set_font_height(fontSize);
                    data.passAllFont:set_text('Pass All');
                    local passTextW, passTextH = data.passAllFont:get_text_size();
                    passTextW = passTextW or (fontSize * 2.5);
                    passTextH = passTextH or fontSize;
                    data.passAllFont:set_position_x(passAllX + (textBtnWidth - passTextW) / 2);
                    data.passAllFont:set_position_y(btnY + (btnHeight - passTextH) / 2);
                    data.passAllFont:set_visible(true);
                    if data.lastColors.passAll ~= 0xFFFFFFFF then
                        data.passAllFont:set_font_color(0xFFFFFFFF);
                        data.lastColors.passAll = 0xFFFFFFFF;
                    end
                end

                -- Draw Lot All button (disabled in HzLimitedMode)
                if (not HzLimitedMode) then
                    -- Draw Lot All button (positive/green) using primitive
                    local lotAllClicked = button.DrawPrim('tpLotAll', lotAllX, btnY, textBtnWidth, btnHeight, {
                        colors = button.COLORS_POSITIVE,
                        tooltip = 'Lot on all items',
                    });
                    if lotAllClicked then
                        actions.LotAll();
                    end

                    -- Draw Lot All label (GDI font renders on top of primitive)
                    if data.lotAllFont then
                        data.lotAllFont:set_font_height(fontSize);
                        data.lotAllFont:set_text('Lot All');
                        local lotTextW, lotTextH = data.lotAllFont:get_text_size();
                        lotTextW = lotTextW or (fontSize * 2);
                        lotTextH = lotTextH or fontSize;
                        data.lotAllFont:set_position_x(lotAllX + (textBtnWidth - lotTextW) / 2);
                        data.lotAllFont:set_position_y(btnY + (btnHeight - lotTextH) / 2);
                        data.lotAllFont:set_visible(true);
                        if data.lastColors.lotAll ~= 0xFFFFFFFF then
                            data.lotAllFont:set_font_color(0xFFFFFFFF);
                            data.lastColors.lotAll = 0xFFFFFFFF;
                        end
                    end
                else
                    -- Hide Lot All in HzLimitedMode
                    button.HidePrim('tpLotAll');
                    if data.lotAllFont then data.lotAllFont:set_visible(false); end
                end

                -- Hide toggle font (not needed, using arrow button)
                if data.toggleFont then data.toggleFont:set_visible(false); end

            else
                -- History tab: hide Pool-specific buttons but keep minimize and toggle
                button.HidePrim('tpLotAll');
                button.HidePrim('tpPassAll');
                if data.toggleFont then data.toggleFont:set_visible(false); end
                if data.lotAllFont then data.lotAllFont:set_visible(false); end
                if data.passAllFont then data.passAllFont:set_visible(false); end

                -- Position buttons (right-aligned)
                local toggleX = startX + windowWidth - padding - toggleSize;
                local minimizeX = toggleX - toggleSize - btnSpacing;

                -- Draw minimize button on History tab
                local minimizeClicked = button.DrawMinimizePrim('tpMinimize', minimizeX, btnY, toggleSize, isMinimized, {
                    colors = button.COLORS_NEUTRAL,
                    tooltip = isMinimized and 'Maximize window' or 'Minimize to header only',
                }, imgui.GetForegroundDrawList());
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
                }, imgui.GetForegroundDrawList());
                if toggleClicked then
                    -- If minimized, maximize first then apply expand/collapse
                    if isMinimized then
                        gConfig.treasurePoolMinimized = false;
                    end
                    gConfig.treasurePoolExpanded = not gConfig.treasurePoolExpanded;
                    SaveSettingsToDisk();
                end
            end

            y = y + headerHeight + 4;  -- Add padding between header and items
        else
            -- Hide header fonts when title not shown
            if data.headerFont then data.headerFont:set_visible(false); end
            if data.toggleFont then data.toggleFont:set_visible(false); end
            if data.lotAllFont then data.lotAllFont:set_visible(false); end
            if data.passAllFont then data.passAllFont:set_visible(false); end
            if data.tabPoolFont then data.tabPoolFont:set_visible(false); end
            if data.tabHistoryFont then data.tabHistoryFont:set_visible(false); end
            button.HidePrim('tpTabPool');
            button.HidePrim('tpTabHistory');
            button.HidePrim('tpMinimize');
            button.HidePrim('tpToggle');
        end

        -- Render content based on selected tab (skip when minimized)
        if isMinimized then
            -- When minimized, hide all content fonts and buttons
            for slot = 0, data.MAX_POOL_SLOTS - 1 do
                if data.itemNameFonts[slot] then data.itemNameFonts[slot]:set_visible(false); end
                if data.timerFonts[slot] then data.timerFonts[slot]:set_visible(false); end
                if data.lotFonts[slot] then data.lotFonts[slot]:set_visible(false); end
                if data.lottersFonts[slot] then data.lottersFonts[slot]:set_visible(false); end
                if data.passersFonts[slot] then data.passersFonts[slot]:set_visible(false); end
                if data.pendingFonts[slot] then data.pendingFonts[slot]:set_visible(false); end
                if data.lotItemFonts[slot] then data.lotItemFonts[slot]:set_visible(false); end
                if data.passItemFonts[slot] then data.passItemFonts[slot]:set_visible(false); end
                if data.memberFonts[slot] then
                    for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                        if data.memberFonts[slot][memberIdx] then
                            data.memberFonts[slot][memberIdx]:set_visible(false);
                        end
                    end
                end
                button.HidePrim(string.format('tpLotItem%d', slot));
                button.HidePrim(string.format('tpPassItem%d', slot));
            end
            -- Hide history fonts
            for i = 0, data.MAX_HISTORY_ITEMS - 1 do
                if data.historyItemFonts[i] then data.historyItemFonts[i]:set_visible(false); end
                if data.historyWinnerFonts[i] then data.historyWinnerFonts[i]:set_visible(false); end
            end
        elseif selectedTab == 1 then
            -- ============================================
            -- POOL TAB: Show treasure pool items
            -- ============================================

            local usedSlots = {};
            local currentY = y;  -- Track cumulative Y position (before scroll)

            -- Calculate visible region for clipping (in expanded scroll mode)
        -- clipTop starts exactly where items begin (after header)
        -- clipBottom is exactly the height of visible items below clipTop
        local itemAreaTop = y;
        local itemAreaBottom = y + visibleContentHeight;

        -- Push clip rect for scrollable area (only affects ImGui draw list, not GDI fonts)
        if needsScroll then
            drawList:PushClipRect(
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

            -- Apply scroll offset in expanded mode
            local rowY = currentY;
            if needsScroll then
                rowY = currentY - scrollOffset;
            end

            -- Check if item overlaps visible region at all (for ImGui elements which clip properly)
            local itemTop = rowY;
            local itemBottom = rowY + rowHeight;
            local hasAnyOverlap = not needsScroll or (itemBottom > itemAreaTop and itemTop < itemAreaBottom);

            local remaining = data.GetTimeRemaining(slot);
            local progress = remaining / data.POOL_TIMEOUT_SECONDS;

            -- Update currentY for next item (before any visibility checks)
            currentY = currentY + rowHeight + rowSpacing;

            -- Skip rendering if item has no overlap with visible region at all
            if not hasAnyOverlap then
                -- Hide fonts and buttons for this slot
                if data.itemNameFonts[slot] then data.itemNameFonts[slot]:set_visible(false); end
                if data.timerFonts[slot] then data.timerFonts[slot]:set_visible(false); end
                if data.lotFonts[slot] then data.lotFonts[slot]:set_visible(false); end
                if data.lotItemFonts[slot] then data.lotItemFonts[slot]:set_visible(false); end
                if data.passItemFonts[slot] then data.passItemFonts[slot]:set_visible(false); end
                if data.memberFonts[slot] then
                    for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                        if data.memberFonts[slot][memberIdx] then
                            data.memberFonts[slot][memberIdx]:set_visible(false);
                        end
                    end
                end
                button.HidePrim(string.format('tpLotItem%d', slot));
                button.HidePrim(string.format('tpPassItem%d', slot));
            else
                -- Item has some overlap with visible region, render it
                -- ImGui elements will be clipped automatically by the clip rect
                -- GDI fonts need per-element visibility checks based on their Y position

            -- Draw border around item row in expanded view
            local itemPadding = 0;  -- Internal padding for content within border
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
            local iconTexture = loadItemIcon(item.itemId);
            local iconPtr = getIconPtr(iconTexture);
            local iconX = startX + padding + itemPadding;
            local iconY = rowY + 2 + itemPadding;  -- Align to top of row with padding

            if iconPtr then
                drawList:AddImage(iconPtr, {iconX, iconY}, {iconX + iconSize, iconY + iconSize});
            end

            local textStartX = iconX + iconSize + iconTextGap;
            local textY = rowY + 2 + itemPadding;

            -- Helper to check if a font at Y position is within visible area
            local function isFontVisible(fontY, fontHeight)
                if not needsScroll then return true; end
                local fontBottom = fontY + (fontHeight or fontSize);
                return fontBottom > itemAreaTop and fontY < itemAreaBottom;
            end

            -- 2. Draw item name (with validation status indicator)
            -- Check validation for visual feedback (only in expanded view where buttons are shown)
            local itemCanLot, itemValidationError = data.ValidateLotItem(slot);
            local itemStatus = data.GetPlayerLotStatus(slot);
            local hasValidationIssue = (not itemCanLot and itemStatus ~= 'lotted' and itemStatus ~= 'passed');

            local nameFont = data.itemNameFonts[slot];
            if nameFont then
                local nameVisible = isFontVisible(textY, fontSize);
                nameFont:set_font_height(fontSize);
                -- Add warning indicator to name if validation fails
                local displayName = item.itemName or 'Unknown';
                if hasValidationIssue then
                    displayName = '[!] ' .. displayName;
                end
                nameFont:set_text(displayName);
                nameFont:set_position_x(textStartX);
                nameFont:set_position_y(textY);
                nameFont:set_visible(nameVisible);

                -- Color: orange/yellow if validation issue, white otherwise
                local nameColor = 0xFFFFFFFF;  -- Default white
                if hasValidationIssue then
                    nameColor = 0xFFFFAA44;  -- Orange/yellow for warning
                end

                if nameVisible and data.lastColors.itemNames[slot] ~= nameColor then
                    nameFont:set_font_color(nameColor);
                    data.lastColors.itemNames[slot] = nameColor;
                end
            end

            -- Draw tooltip for item name area showing validation error
            if hasValidationIssue and itemValidationError then
                local nameWidth, nameHeight = 0, fontSize;
                if nameFont then
                    nameWidth, nameHeight = nameFont:get_text_size();
                    nameWidth = nameWidth or 100;
                    nameHeight = nameHeight or fontSize;
                end
                -- Check if mouse is hovering over item name area
                local mouseX, mouseY = imgui.GetMousePos();
                if mouseX >= textStartX and mouseX <= textStartX + nameWidth and
                   mouseY >= textY and mouseY <= textY + nameHeight then
                    imgui.SetTooltip(itemValidationError);
                end
            end

            -- 3. Draw timer text
            if showTimerText then
                local timerFont = data.timerFonts[slot];
                if timerFont then
                    local timerVisible = isFontVisible(textY, fontSize);
                    local timerText = data.FormatTime(remaining);
                    timerFont:set_font_height(fontSize);
                    timerFont:set_text(timerText);

                    local timerWidth, _ = timerFont:get_text_size();
                    timerWidth = timerWidth or 0;
                    timerFont:set_position_x(startX + windowWidth - padding - itemPadding - timerWidth);
                    timerFont:set_position_y(textY);
                    timerFont:set_visible(timerVisible);

                    if timerVisible then
                        local timerColor = getTimerColor(remaining);
                        if data.lastColors.timers[slot] ~= timerColor then
                            timerFont:set_font_color(timerColor);
                            data.lastColors.timers[slot] = timerColor;
                        end
                    end
                end
            else
                if data.timerFonts[slot] then
                    data.timerFonts[slot]:set_visible(false);
                end
            end

            -- 4. Draw per-item Lot/Pass buttons (expanded view only)
            if isExpanded then
                local itemBtnHeight = fontSize + 4;
                local itemBtnWidth = fontSize * 2.5;
                local itemBtnSpacing = 4;
                local itemBtnY = textY - 1;

                -- Check if button area is visible
                local btnVisible = isFontVisible(itemBtnY, itemBtnHeight);

                -- Position buttons to the left of the timer
                local timerWidth = 0;
                if showTimerText and data.timerFonts[slot] then
                    timerWidth, _ = data.timerFonts[slot]:get_text_size();
                    timerWidth = timerWidth or (fontSize * 3);
                end

                local passBtnX = startX + windowWidth - padding - itemPadding - timerWidth - itemBtnSpacing - itemBtnWidth;
                local lotBtnX = passBtnX - itemBtnSpacing - itemBtnWidth;

                -- Get player's lot status for this item
                local playerStatus = data.GetPlayerLotStatus(slot);

                -- Check validation status for Lot button
                local canLot, validationError = data.ValidateLotItem(slot);

                -- Lot button disabled if already lotted, passed, or validation fails
                local lotDisabled = (playerStatus == 'lotted' or playerStatus == 'passed' or not canLot);
                -- Pass button disabled only if already passed
                local passDisabled = (playerStatus == 'passed');

                -- Colors for disabled state
                local COLOR_DISABLED_TEXT = 0xFF666666;
                local COLOR_ENABLED_TEXT = 0xFFFFFFFF;

                if btnVisible then
                    -- Determine Lot button tooltip based on status and validation
                    local lotTooltip = 'Lot on this item';
                    if playerStatus == 'lotted' then
                        lotTooltip = 'Already lotted';
                    elseif playerStatus == 'passed' then
                        lotTooltip = 'Already passed';
                    elseif validationError then
                        lotTooltip = validationError;  -- Show validation error (e.g., "Already have X (Rare)")
                    end

                    -- Draw Lot button for this item
                    local lotBtnId = string.format('tpLotItem%d', slot);
                    local lotItemClicked = button.DrawPrim(lotBtnId, lotBtnX, itemBtnY, itemBtnWidth, itemBtnHeight, {
                        colors = button.COLORS_POSITIVE,
                        tooltip = lotTooltip,
                        disabled = lotDisabled,
                    });
                    if lotItemClicked and not lotDisabled then
                        actions.LotItem(slot);
                    end

                    -- Draw Lot button label
                    if data.lotItemFonts[slot] then
                        data.lotItemFonts[slot]:set_font_height(fontSize - 1);
                        data.lotItemFonts[slot]:set_text('Lot');
                        local lotTextW, lotTextH = data.lotItemFonts[slot]:get_text_size();
                        lotTextW = lotTextW or (fontSize * 1.5);
                        lotTextH = lotTextH or fontSize;
                        data.lotItemFonts[slot]:set_position_x(lotBtnX + (itemBtnWidth - lotTextW) / 2);
                        data.lotItemFonts[slot]:set_position_y(itemBtnY + (itemBtnHeight - lotTextH) / 2);
                        data.lotItemFonts[slot]:set_visible(true);
                        local lotTextColor = lotDisabled and COLOR_DISABLED_TEXT or COLOR_ENABLED_TEXT;
                        if data.lastColors.lotItems[slot] ~= lotTextColor then
                            data.lotItemFonts[slot]:set_font_color(lotTextColor);
                            data.lastColors.lotItems[slot] = lotTextColor;
                        end
                    end

                    -- Determine Pass button tooltip based on status
                    local passTooltip = 'Pass on this item';
                    if playerStatus == 'passed' then
                        passTooltip = 'Already passed';
                    elseif playerStatus == 'lotted' then
                        passTooltip = 'Pass (withdraw lot)';
                    end

                    -- Draw Pass button for this item
                    local passBtnId = string.format('tpPassItem%d', slot);
                    local passItemClicked = button.DrawPrim(passBtnId, passBtnX, itemBtnY, itemBtnWidth, itemBtnHeight, {
                        colors = button.COLORS_NEGATIVE,
                        tooltip = passTooltip,
                        disabled = passDisabled,
                    });
                    if passItemClicked and not passDisabled then
                        actions.PassItem(slot);
                    end

                    -- Draw Pass button label
                    if data.passItemFonts[slot] then
                        data.passItemFonts[slot]:set_font_height(fontSize - 1);
                        data.passItemFonts[slot]:set_text('Pass');
                        local passTextW, passTextH = data.passItemFonts[slot]:get_text_size();
                        passTextW = passTextW or (fontSize * 2);
                        passTextH = passTextH or fontSize;
                        data.passItemFonts[slot]:set_position_x(passBtnX + (itemBtnWidth - passTextW) / 2);
                        data.passItemFonts[slot]:set_position_y(itemBtnY + (itemBtnHeight - passTextH) / 2);
                        data.passItemFonts[slot]:set_visible(true);
                        local passTextColor = passDisabled and COLOR_DISABLED_TEXT or COLOR_ENABLED_TEXT;
                        if data.lastColors.passItems[slot] ~= passTextColor then
                            data.passItemFonts[slot]:set_font_color(passTextColor);
                            data.lastColors.passItems[slot] = passTextColor;
                        end
                    end
                else
                    -- Hide buttons when outside visible area
                    button.HidePrim(string.format('tpLotItem%d', slot));
                    button.HidePrim(string.format('tpPassItem%d', slot));
                    if data.lotItemFonts[slot] then data.lotItemFonts[slot]:set_visible(false); end
                    if data.passItemFonts[slot] then data.passItemFonts[slot]:set_visible(false); end
                end
            else
                -- Hide per-item button primitives when collapsed
                button.HidePrim(string.format('tpLotItem%d', slot));
                button.HidePrim(string.format('tpPassItem%d', slot));
            end

            -- 5. Draw lot info (collapsed: inline; expanded: hidden)
            if not isExpanded then
                -- Collapsed view: show winning lot inline with name
                if showLots and item.winningLot and item.winningLot > 0 and nameFont then
                    local lotFont = data.lotFonts[slot];
                    if lotFont then
                        local lotterName = item.winningLotterName or '?';
                        if #lotterName > 10 then
                            lotterName = lotterName:sub(1, 8) .. '..';
                        end
                        local lotText = string.format('%s: %d', lotterName, item.winningLot);

                        lotFont:set_font_height(fontSize - 1);
                        lotFont:set_text(lotText);

                        local nameWidth, _ = nameFont:get_text_size();
                        nameWidth = nameWidth or 0;
                        local lotX = textStartX + nameWidth + math.floor(10 * scaleX);
                        lotFont:set_position_x(lotX);
                        lotFont:set_position_y(textY);
                        lotFont:set_visible(true);

                        if data.lastColors.lots[slot] ~= 0xFF88FF88 then
                            lotFont:set_font_color(0xFF88FF88);
                            data.lastColors.lots[slot] = 0xFF88FF88;
                        end
                    end
                else
                    if data.lotFonts[slot] then
                        data.lotFonts[slot]:set_visible(false);
                    end
                end

                -- Hide expanded view fonts when collapsed
                if data.lottersFonts[slot] then data.lottersFonts[slot]:set_visible(false); end
                if data.passersFonts[slot] then data.passersFonts[slot]:set_visible(false); end
                if data.pendingFonts[slot] then data.pendingFonts[slot]:set_visible(false); end
                if data.lotItemFonts[slot] then data.lotItemFonts[slot]:set_visible(false); end
                if data.passItemFonts[slot] then data.passItemFonts[slot]:set_visible(false); end
                -- Hide member fonts when collapsed
                if data.memberFonts[slot] then
                    for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                        if data.memberFonts[slot][memberIdx] then
                            data.memberFonts[slot][memberIdx]:set_visible(false);
                        end
                    end
                end
            else
                -- Expanded view: show member list with lot status
                -- Hide unused fonts (lotItemFonts/passItemFonts are shown via button section above)
                if data.lotFonts[slot] then data.lotFonts[slot]:set_visible(false); end
                if data.lottersFonts[slot] then data.lottersFonts[slot]:set_visible(false); end
                if data.passersFonts[slot] then data.passersFonts[slot]:set_visible(false); end
                if data.pendingFonts[slot] then data.pendingFonts[slot]:set_visible(false); end

                -- Use cached party data (organized by party A/B/C)
                local partyData = itemMemberData[slot] or { partyA = {}, partyB = {}, partyC = {} };

                -- Determine which parties have members
                local activeParties = {};
                if data.PartyHasMembers(partyData.partyA) then table.insert(activeParties, partyData.partyA); end
                if data.PartyHasMembers(partyData.partyB) then table.insert(activeParties, partyData.partyB); end
                if data.PartyHasMembers(partyData.partyC) then table.insert(activeParties, partyData.partyC); end

                -- Draw members: each party is a column, rows = max members across parties
                local memberFontSize = fontSize - 2;
                local numCols = #activeParties;
                if numCols < 1 then numCols = 1; end
                local colWidth = math.floor((windowWidth - padding * 2 - itemPadding * 2) / numCols);
                local memberRowHeightPx = math.floor(EXPANDED_MEMBER_ROW_HEIGHT * scaleY);
                local headerRowHeight = math.floor(EXPANDED_ITEM_HEADER_HEIGHT * scaleY);
                -- Content row must fit icon + small offset, use max of header or icon height
                local contentRowHeight = math.max(headerRowHeight, iconSize + 4);
                local memberStartY = rowY + itemPadding + contentRowHeight;
                local memberStartX = startX + padding + itemPadding;
                -- Get dynamic row count from cached data
                local maxMemberRows = partyData.maxMemberRows or 6;
                if maxMemberRows < 1 then maxMemberRows = 1; end

                -- Animate pending dots (cycles every 0.5s)
                local dotCycle = math.floor(os.clock() * 2) % 3;
                local pendingDots = string.rep('.', dotCycle + 1);

                -- Initialize color cache for this slot if needed
                if not data.lastColors.members[slot] then
                    data.lastColors.members[slot] = {};
                end

                -- Status colors
                local COLOR_WINNER = 0xFF88FF88;   -- Green for winner (highest lot)
                local COLOR_LOTTED = 0xFFFFFFFF;   -- White for other lotters
                local COLOR_PENDING = 0xFFFFFF88;  -- Yellow for pending
                local COLOR_PASSED = 0xFFAAAAAA;   -- Grey for passed

                -- Get winning lot for this item to identify winner
                local winningLot = item.winningLot or 0;

                -- Track font index for allocation
                local fontIdx = 0;

                -- Draw each party as a column
                for col, partyMembers in ipairs(activeParties) do
                    local colX = memberStartX + (col - 1) * colWidth;

                    -- Draw rows based on max members across parties
                    for row = 1, maxMemberRows do
                        local member = partyMembers[row];
                        local memberY = memberStartY + (row - 1) * memberRowHeightPx;

                        local memberFont = data.memberFonts[slot] and data.memberFonts[slot][fontIdx];
                        if memberFont then
                            if member then
                                -- Check if this member font is within visible scroll area
                                local memberVisible = isFontVisible(memberY, memberFontSize);

                                -- Format based on status
                                local displayText;
                                local displayColor;

                                if member.status == 'lotted' and member.lot then
                                    displayText = string.format('%s: %d', member.name, member.lot);
                                    -- Only winner gets green, others get white
                                    if member.lot == winningLot and winningLot > 0 then
                                        displayColor = COLOR_WINNER;
                                    else
                                        displayColor = COLOR_LOTTED;
                                    end
                                elseif member.status == 'pending' then
                                    displayText = member.name .. pendingDots;
                                    displayColor = COLOR_PENDING;
                                else  -- passed
                                    displayText = member.name .. ': Passed';
                                    displayColor = COLOR_PASSED;
                                end

                                memberFont:set_font_height(memberFontSize);
                                memberFont:set_text(displayText);
                                memberFont:set_position_x(colX);
                                memberFont:set_position_y(memberY);
                                memberFont:set_visible(memberVisible);

                                -- Update color only if visible (always update for pending due to animation)
                                if memberVisible and (data.lastColors.members[slot][fontIdx] ~= displayColor or member.status == 'pending') then
                                    memberFont:set_font_color(displayColor);
                                    data.lastColors.members[slot][fontIdx] = displayColor;
                                end
                            else
                                -- Empty slot in party - hide font
                                memberFont:set_visible(false);
                            end
                        end
                        fontIdx = fontIdx + 1;
                    end
                end

                -- Hide remaining unused member fonts for this slot
                for hideIdx = fontIdx, data.MAX_MEMBERS_PER_ITEM - 1 do
                    local memberFont = data.memberFonts[slot] and data.memberFonts[slot][hideIdx];
                    if memberFont then
                        memberFont:set_visible(false);
                    end
                end
            end

            -- 5. Draw progress bar
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
            end  -- end isVisible check
        end

        -- Pop clip rect after drawing items
        if needsScroll then
            drawList:PopClipRect();

            -- Draw scroll indicator (shows position in list)
            local scrollBarWidth = 4;
            local scrollBarX = startX + windowWidth - padding - scrollBarWidth;
            local scrollBarHeight = visibleContentHeight;
            local scrollThumbHeight = math.max(20, scrollBarHeight * (visibleContentHeight / totalContentHeight));
            local scrollThumbY = itemAreaTop;
            if maxScrollOffset > 0 then
                scrollThumbY = itemAreaTop + (scrollOffset / maxScrollOffset) * (scrollBarHeight - scrollThumbHeight);
            end

            -- Draw scroll track (dark)
            local trackColor = imgui.GetColorU32({0.2, 0.2, 0.2, 0.5});
            drawList:AddRectFilled({scrollBarX, itemAreaTop}, {scrollBarX + scrollBarWidth, itemAreaBottom}, trackColor, 2.0);

            -- Draw scroll thumb (light)
            local thumbColor = imgui.GetColorU32({0.6, 0.6, 0.6, 0.8});
            drawList:AddRectFilled({scrollBarX, scrollThumbY}, {scrollBarX + scrollBarWidth, scrollThumbY + scrollThumbHeight}, thumbColor, 2.0);
        end

            -- Hide fonts and buttons for unused slots
            for slot = 0, data.MAX_POOL_SLOTS - 1 do
                if not usedSlots[slot] then
                    if data.itemNameFonts[slot] then data.itemNameFonts[slot]:set_visible(false); end
                    if data.timerFonts[slot] then data.timerFonts[slot]:set_visible(false); end
                    if data.lotFonts[slot] then data.lotFonts[slot]:set_visible(false); end
                    -- Expanded view fonts
                    if data.lottersFonts[slot] then data.lottersFonts[slot]:set_visible(false); end
                    if data.passersFonts[slot] then data.passersFonts[slot]:set_visible(false); end
                    if data.pendingFonts[slot] then data.pendingFonts[slot]:set_visible(false); end
                    if data.lotItemFonts[slot] then data.lotItemFonts[slot]:set_visible(false); end
                    if data.passItemFonts[slot] then data.passItemFonts[slot]:set_visible(false); end
                    -- Member fonts
                    if data.memberFonts[slot] then
                        for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                            if data.memberFonts[slot][memberIdx] then
                                data.memberFonts[slot][memberIdx]:set_visible(false);
                            end
                        end
                    end
                    -- Per-item button primitives
                    button.HidePrim(string.format('tpLotItem%d', slot));
                    button.HidePrim(string.format('tpPassItem%d', slot));
                end
            end

            -- Hide history fonts when on Pool tab
            for i = 0, data.MAX_HISTORY_ITEMS - 1 do
                if data.historyItemFonts[i] then data.historyItemFonts[i]:set_visible(false); end
                if data.historyWinnerFonts[i] then data.historyWinnerFonts[i]:set_visible(false); end
            end

        else
            -- ============================================
            -- HISTORY TAB: Show recent winners
            -- ============================================

            -- Hide all pool fonts when on History tab
            for slot = 0, data.MAX_POOL_SLOTS - 1 do
                if data.itemNameFonts[slot] then data.itemNameFonts[slot]:set_visible(false); end
                if data.timerFonts[slot] then data.timerFonts[slot]:set_visible(false); end
                if data.lotFonts[slot] then data.lotFonts[slot]:set_visible(false); end
                if data.lottersFonts[slot] then data.lottersFonts[slot]:set_visible(false); end
                if data.passersFonts[slot] then data.passersFonts[slot]:set_visible(false); end
                if data.pendingFonts[slot] then data.pendingFonts[slot]:set_visible(false); end
                if data.lotItemFonts[slot] then data.lotItemFonts[slot]:set_visible(false); end
                if data.passItemFonts[slot] then data.passItemFonts[slot]:set_visible(false); end
                if data.memberFonts[slot] then
                    for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                        if data.memberFonts[slot][memberIdx] then
                            data.memberFonts[slot][memberIdx]:set_visible(false);
                        end
                    end
                end
                button.HidePrim(string.format('tpLotItem%d', slot));
                button.HidePrim(string.format('tpPassItem%d', slot));
            end

            -- Get history items
            local historyItems = data.GetWonHistory();
            local historyCount = #historyItems;

            if historyCount == 0 then
                -- Show "No history" message using header font
                if data.headerFont then
                    data.headerFont:set_font_height(fontSize);
                    data.headerFont:set_text('No recent winners');
                    data.headerFont:set_position_x(startX + padding);
                    data.headerFont:set_position_y(y);
                    data.headerFont:set_visible(true);
                    if data.lastColors.header ~= 0xFF888888 then
                        data.headerFont:set_font_color(0xFF888888);
                        data.lastColors.header = 0xFF888888;
                    end
                end

                -- Hide all history fonts
                for i = 0, data.MAX_HISTORY_ITEMS - 1 do
                    if data.historyItemFonts[i] then data.historyItemFonts[i]:set_visible(false); end
                    if data.historyWinnerFonts[i] then data.historyWinnerFonts[i]:set_visible(false); end
                end
            else
                -- Hide the "No history" message font
                if data.headerFont then data.headerFont:set_visible(false); end

                -- Scale history row height
                local historyRowHeight = math.floor(HISTORY_ROW_HEIGHT * scaleY);
                local historyIconSize = math.floor(ICON_SIZE * scaleY);

                -- Calculate visible region for clipping
                local historyAreaTop = y;
                local historyAreaBottom = y + visibleContentHeight;

                -- Handle scroll input (mouse wheel) when hovering over window
                if imgui.IsWindowHovered() and historyMaxScrollOffset > 0 then
                    local wheelY = imgui.GetIO().MouseWheel;
                    if wheelY ~= 0 then
                        local scrollSpeed = historyRowHeight * 2;
                        historyScrollOffset = historyScrollOffset - (wheelY * scrollSpeed);
                        -- Clamp scroll offset
                        if historyScrollOffset < 0 then historyScrollOffset = 0; end
                        if historyScrollOffset > historyMaxScrollOffset then historyScrollOffset = historyMaxScrollOffset; end
                    end
                end

                -- Push clip rect for scrollable area
                local historyNeedsScroll = historyCount > HISTORY_MAX_VISIBLE;
                if historyNeedsScroll then
                    drawList:PushClipRect(
                        {startX, historyAreaTop},
                        {startX + windowWidth, historyAreaBottom},
                        true
                    );
                end

                -- Track which history slots are used
                local usedHistorySlots = {};

                -- Render each history item
                local currentY = y;
                for i, histItem in ipairs(historyItems) do
                    if i > data.MAX_HISTORY_ITEMS then break; end
                    local idx = i - 1;  -- 0-based for font arrays
                    usedHistorySlots[idx] = true;

                    -- Apply scroll offset
                    local rowY = currentY;
                    if historyNeedsScroll then
                        rowY = currentY - historyScrollOffset;
                    end

                    -- Check if item is visible
                    local itemTop = rowY;
                    local itemBottom = rowY + historyRowHeight;
                    local isVisible = not historyNeedsScroll or (itemBottom > historyAreaTop and itemTop < historyAreaBottom);

                    -- Update currentY for next item
                    currentY = currentY + historyRowHeight + rowSpacing;

                    if not isVisible then
                        -- Hide fonts for this item
                        if data.historyItemFonts[idx] then data.historyItemFonts[idx]:set_visible(false); end
                        if data.historyWinnerFonts[idx] then data.historyWinnerFonts[idx]:set_visible(false); end
                    else
                        -- Draw item icon
                        local iconTexture = loadItemIcon(histItem.itemId);
                        local iconPtr = getIconPtr(iconTexture);
                        local iconX = startX + padding;
                        local iconY = rowY + (historyRowHeight - historyIconSize) / 2;

                        if iconPtr then
                            drawList:AddImage(iconPtr, {iconX, iconY}, {iconX + historyIconSize, iconY + historyIconSize});
                        end

                        -- Draw item name
                        local textX = iconX + historyIconSize + iconTextGap;
                        local textY = rowY + 2;

                        if data.historyItemFonts[idx] then
                            local itemFont = data.historyItemFonts[idx];
                            itemFont:set_font_height(fontSize);
                            itemFont:set_text(histItem.itemName or 'Unknown');
                            itemFont:set_position_x(textX);
                            itemFont:set_position_y(textY);
                            itemFont:set_visible(true);
                            if data.lastColors.historyItems[idx] ~= 0xFFFFFFFF then
                                itemFont:set_font_color(0xFFFFFFFF);
                                data.lastColors.historyItems[idx] = 0xFFFFFFFF;
                            end
                        end

                        -- Draw winner info (right-aligned, with scrollbar accommodation)
                        local winnerText = string.format('%s: %d', histItem.winnerName or '?', histItem.winnerLot or 0);
                        if data.historyWinnerFonts[idx] then
                            local winnerFont = data.historyWinnerFonts[idx];
                            winnerFont:set_font_height(fontSize);
                            winnerFont:set_text(winnerText);
                            local winnerW, _ = winnerFont:get_text_size();
                            winnerW = winnerW or (fontSize * 6);
                            -- Add extra padding when scrollbar is visible (scrollbar width + gap)
                            local scrollbarPadding = historyNeedsScroll and 10 or 0;
                            winnerFont:set_position_x(startX + windowWidth - padding - winnerW - scrollbarPadding);
                            winnerFont:set_position_y(textY);
                            winnerFont:set_visible(true);
                            if data.lastColors.historyWinners[idx] ~= 0xFF88FF88 then
                                winnerFont:set_font_color(0xFF88FF88);
                                data.lastColors.historyWinners[idx] = 0xFF88FF88;
                            end
                        end
                    end
                end

                -- Pop clip rect if needed
                if historyNeedsScroll then
                    drawList:PopClipRect();

                    -- Calculate total history content height
                    local historyTotalContentHeight = (historyCount * historyRowHeight) + ((historyCount - 1) * rowSpacing);

                    -- Draw scroll bar (matches Pool tab style)
                    local scrollBarWidth = 4;
                    local scrollBarX = startX + windowWidth - padding - scrollBarWidth;
                    local scrollBarHeight = visibleContentHeight;
                    local scrollThumbHeight = math.max(20, scrollBarHeight * (visibleContentHeight / historyTotalContentHeight));
                    local scrollThumbY = historyAreaTop;
                    if historyMaxScrollOffset > 0 then
                        scrollThumbY = historyAreaTop + (historyScrollOffset / historyMaxScrollOffset) * (scrollBarHeight - scrollThumbHeight);
                    end

                    -- Draw scroll track (dark)
                    local trackColor = imgui.GetColorU32({0.2, 0.2, 0.2, 0.5});
                    drawList:AddRectFilled({scrollBarX, historyAreaTop}, {scrollBarX + scrollBarWidth, historyAreaBottom}, trackColor, 2.0);

                    -- Draw scroll thumb (light)
                    local thumbColor = imgui.GetColorU32({0.6, 0.6, 0.6, 0.8});
                    drawList:AddRectFilled({scrollBarX, scrollThumbY}, {scrollBarX + scrollBarWidth, scrollThumbY + scrollThumbHeight}, thumbColor, 2.0);
                end

                -- Hide unused history fonts
                for i = historyCount, data.MAX_HISTORY_ITEMS - 1 do
                    if data.historyItemFonts[i] then data.historyItemFonts[i]:set_visible(false); end
                    if data.historyWinnerFonts[i] then data.historyWinnerFonts[i]:set_visible(false); end
                end
            end
        end
    end
    imgui.End();
end

function M.HideWindow()
    -- Hide header fonts
    if data.headerFont then data.headerFont:set_visible(false); end
    if data.toggleFont then data.toggleFont:set_visible(false); end
    if data.lotAllFont then data.lotAllFont:set_visible(false); end
    if data.passAllFont then data.passAllFont:set_visible(false); end

    -- Hide tab fonts
    if data.tabPoolFont then data.tabPoolFont:set_visible(false); end
    if data.tabHistoryFont then data.tabHistoryFont:set_visible(false); end

    -- Hide history fonts
    for i = 0, data.MAX_HISTORY_ITEMS - 1 do
        if data.historyItemFonts[i] then data.historyItemFonts[i]:set_visible(false); end
        if data.historyWinnerFonts[i] then data.historyWinnerFonts[i]:set_visible(false); end
    end

    -- Hide per-slot fonts
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        if data.itemNameFonts[slot] then data.itemNameFonts[slot]:set_visible(false); end
        if data.timerFonts[slot] then data.timerFonts[slot]:set_visible(false); end
        if data.lotFonts[slot] then data.lotFonts[slot]:set_visible(false); end
        -- Expanded view fonts
        if data.lottersFonts[slot] then data.lottersFonts[slot]:set_visible(false); end
        if data.passersFonts[slot] then data.passersFonts[slot]:set_visible(false); end
        if data.pendingFonts[slot] then data.pendingFonts[slot]:set_visible(false); end
        if data.lotItemFonts[slot] then data.lotItemFonts[slot]:set_visible(false); end
        if data.passItemFonts[slot] then data.passItemFonts[slot]:set_visible(false); end
        -- Member fonts
        if data.memberFonts[slot] then
            for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                if data.memberFonts[slot][memberIdx] then
                    data.memberFonts[slot][memberIdx]:set_visible(false);
                end
            end
        end
    end

    -- Hide primitive buttons
    button.HidePrim('tpToggle');
    button.HidePrim('tpMinimize');
    button.HidePrim('tpLotAll');
    button.HidePrim('tpPassAll');
    button.HidePrim('tpTabPool');
    button.HidePrim('tpTabHistory');

    -- Hide per-item button primitives
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
    -- Get background theme and scales from config (with defaults)
    local bgTheme = gConfig.treasurePoolBackgroundTheme or 'Plain';
    local bgScale = gConfig.treasurePoolBgScale or 1.0;
    local borderScale = gConfig.treasurePoolBorderScale or 1.0;
    loadedBgTheme = bgTheme;

    -- Create background primitive (fonts created by init.lua)
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
    -- Check if theme changed
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

    -- Destroy primitive buttons
    button.DestroyPrim('tpToggle');
    button.DestroyPrim('tpMinimize');
    button.DestroyPrim('tpLotAll');
    button.DestroyPrim('tpPassAll');
    button.DestroyPrim('tpTabPool');
    button.DestroyPrim('tpTabHistory');

    -- Destroy per-item button primitives
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        button.DestroyPrim(string.format('tpLotItem%d', slot));
        button.DestroyPrim(string.format('tpPassItem%d', slot));
    end

    loadedBgTheme = nil;
    iconCache = {};
end

return M;
