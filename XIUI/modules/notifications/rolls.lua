--[[
* XIUI Rolls Window Module
* Displays detailed treasure pool information with all rolls/passes
* Toggled via /xiui rolls command
]]--

require('common');
require('handlers.helpers');
local imgui = require('imgui');
local ffi = require('ffi');
local gdi = require('submodules.gdifonts.include');
local primitives = require('primitives');
local windowBg = require('libs.windowbackground');
local notificationData = require('modules.notifications.data');
local textures = require('libs.textures');
local d3d8 = require('d3d8');

local M = {};

-- ============================================
-- Module State
-- ============================================

-- Window visibility (toggled by /xiui rolls command)
M.isVisible = false;

-- Collapsed state (minimized to title bar only)
M.isCollapsed = false;

-- Constants
local MAX_POOL_ITEMS = 10;
local MAX_HISTORY_ITEMS = 10;
local MAX_LOTS_PER_ITEM = 18;  -- Full alliance
local PARTY_SIZE = 6;
local NUM_PARTIES = 3;

-- Font objects
local fonts = {
    title = nil,            -- "Treasure Pool" title
    header = nil,           -- "Recent History" header
    passButton = nil,       -- "Pass All" button text
    lotButton = nil,        -- "Lot All" button text
    itemNames = {},         -- Item name fonts (indexed by display slot)
    timers = {},            -- Timer fonts
    partyHeaders = {},      -- "Party A", "Party B", "Party C" headers
    lotters = {},           -- Lotter name/value fonts (3D: [itemSlot][partyIdx][memberIdx])
    historyItems = {},      -- History item name fonts
    historyWinners = {},    -- History winner fonts
    itemLotButtons = {},    -- Individual item "Lot" button fonts
    itemPassButtons = {},   -- Individual item "Pass" button fonts
};
local allFonts = {};

-- Background primitives
local bgPrims = {
    main = nil,             -- Main window background
    passButton = nil,       -- Pass All button background
    lotButton = nil,        -- Lot All button background
    itemLotButtons = {},    -- Individual item Lot button backgrounds
    itemPassButtons = {},   -- Individual item Pass button backgrounds
};

-- Cached colors
local lastTitleColor = nil;
local lastHeaderColor = nil;
local lastPassButtonColor = nil;
local lastLotButtonColor = nil;
local lastItemLotButtonColors = {};
local lastItemPassButtonColors = {};
local lastItemNameColors = {};
local lastTimerColors = {};
local lastPartyHeaderColors = {};
local lastLotterColors = {};
local lastHistoryItemColors = {};
local lastHistoryWinnerColors = {};

-- Icon cache (reuse from notifications display pattern)
local iconCache = {};

-- ============================================
-- Icon Loading (same pattern as notifications/display.lua)
-- ============================================

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

-- ============================================
-- Window Flags
-- ============================================

local baseWindowFlags = nil;

local function getWindowFlags()
    if baseWindowFlags == nil then
        baseWindowFlags = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav,
            ImGuiWindowFlags_NoBackground,
            ImGuiWindowFlags_NoBringToFrontOnFocus,
            ImGuiWindowFlags_NoDocking
        );
    end

    local flags = baseWindowFlags;
    if gConfig.lockPositions then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove);
    end
    return flags;
end

-- ============================================
-- Helper Functions
-- ============================================

-- Sort lots by lot value (highest first), passes last, pending at end
-- Returns array with party index (1-3) assigned based on order
local function sortAndAssignParties(lots)
    local sorted = {};
    for playerId, lotInfo in pairs(lots) do
        table.insert(sorted, {
            playerId = playerId,
            name = lotInfo.name,
            lot = lotInfo.lot,
            passed = lotInfo.passed,
            pending = lotInfo.pending or (lotInfo.lot == nil and not lotInfo.passed),
        });
    end

    -- Sort: lotted (highest first) > passed > pending
    table.sort(sorted, function(a, b)
        -- Pending always last
        if a.pending and not b.pending then return false; end
        if not a.pending and b.pending then return true; end
        -- Passes before pending but after lots
        if a.passed and not b.passed then return false; end
        if not a.passed and b.passed then return true; end
        return (a.lot or 0) > (b.lot or 0);
    end);

    -- Assign to parties based on position (simulating alliance order)
    -- In real usage, we'd use actual party membership
    local parties = {{}, {}, {}};
    for i, lotInfo in ipairs(sorted) do
        local partyIdx = math.ceil(i / PARTY_SIZE);
        if partyIdx > NUM_PARTIES then partyIdx = NUM_PARTIES; end
        table.insert(parties[partyIdx], lotInfo);
    end

    return parties;
end

-- ============================================
-- Lifecycle Functions
-- ============================================

function M.Initialize(settings)
    local fontSettings = settings and settings.font_settings or {};
    local titleFontSettings = settings and settings.title_font_settings or {};

    -- Title font ("Treasure Pool")
    fonts.title = FontManager.create({
        font_alignment = gdi.Alignment.Left,
        font_family = titleFontSettings.font_family or 'Consolas',
        font_height = 14,
        font_color = 0xFFFFFFFF,
        font_flags = gdi.FontFlags.Bold,
        outline_color = 0xFF000000,
        outline_width = 2,
    });
    table.insert(allFonts, fonts.title);

    -- Header font ("Recent History")
    fonts.header = FontManager.create({
        font_alignment = gdi.Alignment.Left,
        font_family = titleFontSettings.font_family or 'Consolas',
        font_height = 14,
        font_color = 0xFFFFFFFF,
        font_flags = gdi.FontFlags.Bold,
        outline_color = 0xFF000000,
        outline_width = 2,
    });
    table.insert(allFonts, fonts.header);

    -- Pass button font
    fonts.passButton = FontManager.create({
        font_alignment = gdi.Alignment.Left,
        font_family = fontSettings.font_family or 'Consolas',
        font_height = 10,
        font_color = 0xFFAAAAAA,
        font_flags = fontSettings.font_flags or gdi.FontFlags.None,
        outline_color = 0xFF000000,
        outline_width = 2,
    });
    table.insert(allFonts, fonts.passButton);

    -- Lot button font
    fonts.lotButton = FontManager.create({
        font_alignment = gdi.Alignment.Left,
        font_family = fontSettings.font_family or 'Consolas',
        font_height = 10,
        font_color = 0xFF66CC66,
        font_flags = fontSettings.font_flags or gdi.FontFlags.None,
        outline_color = 0xFF000000,
        outline_width = 2,
    });
    table.insert(allFonts, fonts.lotButton);

    -- Party header fonts
    for p = 1, NUM_PARTIES do
        fonts.partyHeaders[p] = FontManager.create({
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 10,
            font_color = 0xFFAAAAFF,
            font_flags = gdi.FontFlags.Bold,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
        table.insert(allFonts, fonts.partyHeaders[p]);
    end

    -- Create fonts for pool items (up to MAX_POOL_ITEMS)
    for i = 1, MAX_POOL_ITEMS do
        -- Item name font
        fonts.itemNames[i] = FontManager.create({
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 12,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.Bold,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
        table.insert(allFonts, fonts.itemNames[i]);

        -- Timer font
        fonts.timers[i] = FontManager.create({
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 10,
            font_color = 0xFFFFFF4D,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
        table.insert(allFonts, fonts.timers[i]);

        -- Lotter fonts organized by party (3 parties x 6 members each)
        fonts.lotters[i] = {};
        for p = 1, NUM_PARTIES do
            fonts.lotters[i][p] = {};
            for m = 1, PARTY_SIZE do
                fonts.lotters[i][p][m] = FontManager.create({
                    font_alignment = gdi.Alignment.Left,
                    font_family = fontSettings.font_family or 'Consolas',
                    font_height = 10,
                    font_color = 0xFFCCCCCC,
                    font_flags = gdi.FontFlags.None,
                    outline_color = 0xFF000000,
                    outline_width = 2,
                });
                table.insert(allFonts, fonts.lotters[i][p][m]);
            end
        end

        -- Individual item Lot button font
        fonts.itemLotButtons[i] = FontManager.create({
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 9,
            font_color = 0xFF66CC66,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
        table.insert(allFonts, fonts.itemLotButtons[i]);

        -- Individual item Pass button font
        fonts.itemPassButtons[i] = FontManager.create({
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 9,
            font_color = 0xFFCC6666,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
        table.insert(allFonts, fonts.itemPassButtons[i]);
    end

    -- Create fonts for history items
    for i = 1, MAX_HISTORY_ITEMS do
        fonts.historyItems[i] = FontManager.create({
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 11,
            font_color = 0xFFCCCCCC,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
        table.insert(allFonts, fonts.historyItems[i]);

        fonts.historyWinners[i] = FontManager.create({
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 11,
            font_color = 0xFF4DFF4D,
            font_flags = gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
        table.insert(allFonts, fonts.historyWinners[i]);
    end

    -- Create background primitive
    local primData = {
        visible = false,
        can_focus = false,
        locked = true,
    };
    bgPrims.main = windowBg.create(primData, 'Plain', 1.0);

    -- Create pass button background primitive
    local btnPrim = primitives:new(primData);
    btnPrim.visible = false;
    btnPrim.can_focus = false;
    btnPrim.texture = string.format('%s/assets/backgrounds/Plain-bg.png', addon.path);
    btnPrim.color = 0xFF333333;
    bgPrims.passButton = btnPrim;

    -- Create lot button background primitive
    local lotBtnPrim = primitives:new(primData);
    lotBtnPrim.visible = false;
    lotBtnPrim.can_focus = false;
    lotBtnPrim.texture = string.format('%s/assets/backgrounds/Plain-bg.png', addon.path);
    lotBtnPrim.color = 0xFF333333;
    bgPrims.lotButton = lotBtnPrim;

    -- Create individual item button primitives
    for i = 1, MAX_POOL_ITEMS do
        local itemLotPrim = primitives:new(primData);
        itemLotPrim.visible = false;
        itemLotPrim.can_focus = false;
        itemLotPrim.texture = string.format('%s/assets/backgrounds/Plain-bg.png', addon.path);
        itemLotPrim.color = 0xFF333333;
        bgPrims.itemLotButtons[i] = itemLotPrim;

        local itemPassPrim = primitives:new(primData);
        itemPassPrim.visible = false;
        itemPassPrim.can_focus = false;
        itemPassPrim.texture = string.format('%s/assets/backgrounds/Plain-bg.png', addon.path);
        itemPassPrim.color = 0xFF333333;
        bgPrims.itemPassButtons[i] = itemPassPrim;
    end
end

function M.UpdateVisuals(settings)
    local fontSettings = settings and settings.font_settings or {};
    local titleFontSettings = settings and settings.title_font_settings or {};

    -- Recreate title font
    if fonts.title then
        fonts.title = FontManager.recreate(fonts.title, {
            font_alignment = gdi.Alignment.Left,
            font_family = titleFontSettings.font_family or 'Consolas',
            font_height = 14,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.Bold,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
    end

    -- Recreate header font
    if fonts.header then
        fonts.header = FontManager.recreate(fonts.header, {
            font_alignment = gdi.Alignment.Left,
            font_family = titleFontSettings.font_family or 'Consolas',
            font_height = 14,
            font_color = 0xFFFFFFFF,
            font_flags = gdi.FontFlags.Bold,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
    end

    -- Recreate pass button font
    if fonts.passButton then
        fonts.passButton = FontManager.recreate(fonts.passButton, {
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 10,
            font_color = 0xFFAAAAAA,
            font_flags = fontSettings.font_flags or gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
    end

    -- Recreate lot button font
    if fonts.lotButton then
        fonts.lotButton = FontManager.recreate(fonts.lotButton, {
            font_alignment = gdi.Alignment.Left,
            font_family = fontSettings.font_family or 'Consolas',
            font_height = 10,
            font_color = 0xFF66CC66,
            font_flags = fontSettings.font_flags or gdi.FontFlags.None,
            outline_color = 0xFF000000,
            outline_width = 2,
        });
    end

    -- Recreate party header fonts
    for p = 1, NUM_PARTIES do
        if fonts.partyHeaders[p] then
            fonts.partyHeaders[p] = FontManager.recreate(fonts.partyHeaders[p], {
                font_alignment = gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = 10,
                font_color = 0xFFAAAAFF,
                font_flags = gdi.FontFlags.Bold,
                outline_color = 0xFF000000,
                outline_width = 2,
            });
        end
    end

    -- Recreate pool item fonts
    for i = 1, MAX_POOL_ITEMS do
        if fonts.itemNames[i] then
            fonts.itemNames[i] = FontManager.recreate(fonts.itemNames[i], {
                font_alignment = gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = 12,
                font_color = 0xFFFFFFFF,
                font_flags = gdi.FontFlags.Bold,
                outline_color = 0xFF000000,
                outline_width = 2,
            });
        end

        if fonts.timers[i] then
            fonts.timers[i] = FontManager.recreate(fonts.timers[i], {
                font_alignment = gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = 10,
                font_color = 0xFFFFFF4D,
                font_flags = gdi.FontFlags.None,
                outline_color = 0xFF000000,
                outline_width = 2,
            });
        end

        if fonts.lotters[i] then
            for p = 1, NUM_PARTIES do
                if fonts.lotters[i][p] then
                    for m = 1, PARTY_SIZE do
                        if fonts.lotters[i][p][m] then
                            fonts.lotters[i][p][m] = FontManager.recreate(fonts.lotters[i][p][m], {
                                font_alignment = gdi.Alignment.Left,
                                font_family = fontSettings.font_family or 'Consolas',
                                font_height = 10,
                                font_color = 0xFFCCCCCC,
                                font_flags = gdi.FontFlags.None,
                                outline_color = 0xFF000000,
                                outline_width = 2,
                            });
                        end
                    end
                end
            end
        end

        if fonts.itemLotButtons[i] then
            fonts.itemLotButtons[i] = FontManager.recreate(fonts.itemLotButtons[i], {
                font_alignment = gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = 9,
                font_color = 0xFF66CC66,
                font_flags = gdi.FontFlags.None,
                outline_color = 0xFF000000,
                outline_width = 2,
            });
        end

        if fonts.itemPassButtons[i] then
            fonts.itemPassButtons[i] = FontManager.recreate(fonts.itemPassButtons[i], {
                font_alignment = gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = 9,
                font_color = 0xFFCC6666,
                font_flags = gdi.FontFlags.None,
                outline_color = 0xFF000000,
                outline_width = 2,
            });
        end
    end

    -- Recreate history fonts
    for i = 1, MAX_HISTORY_ITEMS do
        if fonts.historyItems[i] then
            fonts.historyItems[i] = FontManager.recreate(fonts.historyItems[i], {
                font_alignment = gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = 11,
                font_color = 0xFFCCCCCC,
                font_flags = gdi.FontFlags.None,
                outline_color = 0xFF000000,
                outline_width = 2,
            });
        end

        if fonts.historyWinners[i] then
            fonts.historyWinners[i] = FontManager.recreate(fonts.historyWinners[i], {
                font_alignment = gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = 11,
                font_color = 0xFF4DFF4D,
                font_flags = gdi.FontFlags.None,
                outline_color = 0xFF000000,
                outline_width = 2,
            });
        end
    end

    -- Rebuild allFonts list
    allFonts = {};
    if fonts.title then table.insert(allFonts, fonts.title); end
    if fonts.header then table.insert(allFonts, fonts.header); end
    if fonts.passButton then table.insert(allFonts, fonts.passButton); end
    if fonts.lotButton then table.insert(allFonts, fonts.lotButton); end
    for p = 1, NUM_PARTIES do
        if fonts.partyHeaders[p] then table.insert(allFonts, fonts.partyHeaders[p]); end
    end
    for i = 1, MAX_POOL_ITEMS do
        if fonts.itemNames[i] then table.insert(allFonts, fonts.itemNames[i]); end
        if fonts.timers[i] then table.insert(allFonts, fonts.timers[i]); end
        if fonts.lotters[i] then
            for p = 1, NUM_PARTIES do
                if fonts.lotters[i][p] then
                    for m = 1, PARTY_SIZE do
                        if fonts.lotters[i][p][m] then table.insert(allFonts, fonts.lotters[i][p][m]); end
                    end
                end
            end
        end
        if fonts.itemLotButtons[i] then table.insert(allFonts, fonts.itemLotButtons[i]); end
        if fonts.itemPassButtons[i] then table.insert(allFonts, fonts.itemPassButtons[i]); end
    end
    for i = 1, MAX_HISTORY_ITEMS do
        if fonts.historyItems[i] then table.insert(allFonts, fonts.historyItems[i]); end
        if fonts.historyWinners[i] then table.insert(allFonts, fonts.historyWinners[i]); end
    end

    -- Clear cached colors
    lastTitleColor = nil;
    lastHeaderColor = nil;
    lastPassButtonColor = nil;
    lastLotButtonColor = nil;
    lastItemLotButtonColors = {};
    lastItemPassButtonColors = {};
    lastItemNameColors = {};
    lastTimerColors = {};
    lastPartyHeaderColors = {};
    lastLotterColors = {};
    lastHistoryItemColors = {};
    lastHistoryWinnerColors = {};
end

function M.DrawWindow(settings)
    -- Hide all fonts first
    SetFontsVisible(allFonts, false);

    -- Hide background
    if bgPrims.main then
        windowBg.hide(bgPrims.main);
    end

    -- Hide button primitives
    if bgPrims.passButton then
        bgPrims.passButton.visible = false;
    end
    if bgPrims.lotButton then
        bgPrims.lotButton.visible = false;
    end
    for i = 1, MAX_POOL_ITEMS do
        if bgPrims.itemLotButtons[i] then
            bgPrims.itemLotButtons[i].visible = false;
        end
        if bgPrims.itemPassButtons[i] then
            bgPrims.itemPassButtons[i].visible = false;
        end
    end

    -- Early exit if not visible or player not valid
    if not M.isVisible then return; end

    local player = GetPlayerSafe();
    if not player or player.isZoning then return; end

    -- Get treasure pool and history data
    local poolItems = notificationData.GetSortedTreasurePool();
    local history = notificationData.GetAwardedHistory();

    local poolCount = poolItems and #poolItems or 0;
    local historyCount = history and #history or 0;

    -- If nothing to show, hide the window
    if poolCount == 0 and historyCount == 0 then
        return;
    end

    -- Layout constants
    local padding = 12;
    local iconSize = 20;
    local itemSpacing = 6;
    local sectionSpacing = 16;
    local columnWidth = 120;
    local columnGap = 8;
    local lotterLineHeight = 13;
    local titleHeight = 18;
    local headerHeight = 16;
    local itemNameHeight = 16;
    local historyLineHeight = 16;
    local collapsedBarHeight = padding + titleHeight + 4;  -- Match title row with small bottom padding

    -- Calculate window width (3 columns + gaps + padding)
    local contentWidth = (columnWidth * 3) + (columnGap * 2);
    local windowWidth = contentWidth + (padding * 2);

    -- Calculate heights
    local poolSectionHeight = 0;
    if poolCount > 0 then
        poolSectionHeight = titleHeight + itemSpacing;  -- "Treasure Pool" title
        for idx, item in ipairs(poolItems) do
            if idx > MAX_POOL_ITEMS then break; end
            local parties = sortAndAssignParties(item.lots or {});
            local maxPartySize = 0;
            for p = 1, NUM_PARTIES do
                maxPartySize = math.max(maxPartySize, #parties[p]);
            end
            -- Item row + lotter rows + border padding
            local itemBoxPaddingY = 8;
            poolSectionHeight = poolSectionHeight + itemBoxPaddingY;  -- Top padding
            poolSectionHeight = poolSectionHeight + itemNameHeight + itemSpacing;
            poolSectionHeight = poolSectionHeight + (maxPartySize * lotterLineHeight);
            poolSectionHeight = poolSectionHeight + itemBoxPaddingY + itemSpacing;  -- Bottom padding + spacing
        end
    end

    local historySectionHeight = 0;
    if historyCount > 0 then
        if poolCount > 0 then
            historySectionHeight = sectionSpacing;
        end
        historySectionHeight = historySectionHeight + headerHeight + itemSpacing;
        historySectionHeight = historySectionHeight + (math.min(historyCount, MAX_HISTORY_ITEMS) * historyLineHeight);
    end

    local totalContentHeight = poolSectionHeight + historySectionHeight;

    -- When collapsed, use minimal height
    local displayHeight = M.isCollapsed and collapsedBarHeight or (totalContentHeight + (padding * 2));

    -- Create ImGui window
    local windowFlags = getWindowFlags();

    if imgui.Begin('RollsWindow', true, windowFlags) then
        local success, err = pcall(function()
            local windowPosX, windowPosY = imgui.GetWindowPos();
            local drawList = imgui.GetWindowDrawList();

            -- Create dummy for draggable area
            imgui.Dummy({windowWidth, displayHeight});

            -- Update background with correct dimensions
            if bgPrims.main then
                windowBg.update(bgPrims.main, windowPosX, windowPosY,
                    windowWidth, displayHeight, {
                    theme = 'Plain',
                    padding = 0,
                    bgOpacity = 0.92,
                    bgColor = 0xFF1A1A1A,
                });
            end

            local contentX = windowPosX + padding;
            local contentY = windowPosY + padding - 4;
            local currentY = contentY;

            -- Check if mouse is hovering (for button interactions)
            local mouseX, mouseY = imgui.GetMousePos();

            -- Draw close button (X) in top right
            local closeBtnSize = 16;
            local closeBtnX = windowPosX + windowWidth - padding - closeBtnSize + 4;
            local closeBtnY = windowPosY + 6;

            -- Draw collapse button (left of X)
            local collapseBtnSize = 16;
            local collapseBtnX = closeBtnX - collapseBtnSize - 4;
            local collapseBtnY = closeBtnY;

            -- Collapse button colors
            local collapseColor = 0xFF888888;
            local collapseHoverColor = 0xFFFFFFFF;

            -- Check if mouse is hovering over collapse button
            local isCollapseHovering = mouseX >= collapseBtnX and mouseX <= collapseBtnX + collapseBtnSize
                                   and mouseY >= collapseBtnY and mouseY <= collapseBtnY + collapseBtnSize;

            if isCollapseHovering then
                collapseColor = collapseHoverColor;
                if imgui.IsMouseClicked(0) then
                    M.isCollapsed = not M.isCollapsed;
                end
            end

            -- Draw collapse button (down arrow when expanded, up arrow when collapsed)
            if drawList then
                local arrowCenterX = collapseBtnX + collapseBtnSize / 2;
                local arrowCenterY = collapseBtnY + collapseBtnSize / 2;
                local arrowWidth = 4;
                local arrowHeight = 3;

                if M.isCollapsed then
                    -- Draw up arrow (chevron pointing up)
                    drawList:AddLine(
                        {arrowCenterX - arrowWidth, arrowCenterY + arrowHeight},
                        {arrowCenterX, arrowCenterY - arrowHeight},
                        collapseColor, 2
                    );
                    drawList:AddLine(
                        {arrowCenterX, arrowCenterY - arrowHeight},
                        {arrowCenterX + arrowWidth, arrowCenterY + arrowHeight},
                        collapseColor, 2
                    );
                else
                    -- Draw down arrow (chevron pointing down)
                    drawList:AddLine(
                        {arrowCenterX - arrowWidth, arrowCenterY - arrowHeight},
                        {arrowCenterX, arrowCenterY + arrowHeight},
                        collapseColor, 2
                    );
                    drawList:AddLine(
                        {arrowCenterX, arrowCenterY + arrowHeight},
                        {arrowCenterX + arrowWidth, arrowCenterY - arrowHeight},
                        collapseColor, 2
                    );
                end
            end

            -- Draw X (close button)
            local xColor = 0xFF888888;
            local xHoverColor = 0xFFFFFFFF;

            local isHovering = mouseX >= closeBtnX and mouseX <= closeBtnX + closeBtnSize
                           and mouseY >= closeBtnY and mouseY <= closeBtnY + closeBtnSize;

            if isHovering then
                xColor = xHoverColor;
                if imgui.IsMouseClicked(0) then
                    M.isVisible = false;
                end
            end

            if drawList then
                local x1, y1 = closeBtnX + 3, closeBtnY + 3;
                local x2, y2 = closeBtnX + closeBtnSize - 3, closeBtnY + closeBtnSize - 3;
                drawList:AddLine({x1, y1}, {x2, y2}, xColor, 2);
                drawList:AddLine({x2, y1}, {x1, y2}, xColor, 2);
            end

            -- ========================================
            -- Collapsed State - Show only title bar
            -- ========================================
            if M.isCollapsed then
                -- Draw "Treasure Pool" title with item count
                -- Use same positioning as expanded state (contentY = windowPosY + padding)
                local titleTextWidth = 0;
                if fonts.title then
                    local collapsedTitle = string.format('Treasure Pool (%d)', poolCount);
                    fonts.title:set_font_height(14);
                    fonts.title:set_position_x(contentX);
                    fonts.title:set_position_y(contentY);
                    fonts.title:set_text(collapsedTitle);
                    titleTextWidth = fonts.title:get_text_size();
                    if lastTitleColor ~= 0xFFFFFFFF then
                        fonts.title:set_font_color(0xFFFFFFFF);
                        lastTitleColor = 0xFFFFFFFF;
                    end
                    fonts.title:set_visible(true);
                end

                -- Draw "Lot All" and "Pass All" buttons next to title (only if there are items)
                if poolCount > 0 then
                    local btnPadX = 6;
                    local btnPadY = 2;
                    local btnGap = 6;

                    -- Lot All button
                    local lotBtnTextWidth = 0;
                    local lotBtnTextHeight = 10;
                    if fonts.lotButton then
                        fonts.lotButton:set_font_height(10);
                        fonts.lotButton:set_text('Lot All');
                        lotBtnTextWidth, lotBtnTextHeight = fonts.lotButton:get_text_size();
                    end

                    local lotBtnWidth = lotBtnTextWidth + (btnPadX * 2);
                    local lotBtnHeight = lotBtnTextHeight + (btnPadY * 2);
                    local lotBtnX = contentX + titleTextWidth + 10;
                    local lotBtnY = contentY + (titleHeight - lotBtnHeight) / 2;

                    local lotBtnBgColor = 0xFF333333;
                    local lotBtnTextColor = 0xFF66CC66;
                    local lotBtnHoverBgColor = 0xFF224422;
                    local lotBtnHoverTextColor = 0xFF66FF66;

                    local isLotHovering = mouseX >= lotBtnX and mouseX <= lotBtnX + lotBtnWidth
                                      and mouseY >= lotBtnY and mouseY <= lotBtnY + lotBtnHeight;

                    if isLotHovering then
                        lotBtnBgColor = lotBtnHoverBgColor;
                        lotBtnTextColor = lotBtnHoverTextColor;
                        if imgui.IsMouseClicked(0) then
                            M.LotAllUnlotted();
                        end
                    end

                    if bgPrims.lotButton then
                        bgPrims.lotButton.position_x = lotBtnX;
                        bgPrims.lotButton.position_y = lotBtnY;
                        bgPrims.lotButton.width = lotBtnWidth;
                        bgPrims.lotButton.height = lotBtnHeight;
                        bgPrims.lotButton.color = lotBtnBgColor;
                        bgPrims.lotButton.visible = true;
                    end

                    if fonts.lotButton then
                        fonts.lotButton:set_position_x(lotBtnX + btnPadX);
                        fonts.lotButton:set_position_y(lotBtnY + btnPadY);
                        if lastLotButtonColor ~= lotBtnTextColor then
                            fonts.lotButton:set_font_color(lotBtnTextColor);
                            lastLotButtonColor = lotBtnTextColor;
                        end
                        fonts.lotButton:set_visible(true);
                    end

                    -- Pass All button
                    local passBtnTextWidth = 0;
                    local passBtnTextHeight = 10;
                    if fonts.passButton then
                        fonts.passButton:set_font_height(10);
                        fonts.passButton:set_text('Pass All');
                        passBtnTextWidth, passBtnTextHeight = fonts.passButton:get_text_size();
                    end

                    local passBtnWidth = passBtnTextWidth + (btnPadX * 2);
                    local passBtnHeight = passBtnTextHeight + (btnPadY * 2);
                    local passBtnX = lotBtnX + lotBtnWidth + btnGap;
                    local passBtnY = contentY + (titleHeight - passBtnHeight) / 2;

                    local passBtnBgColor = 0xFF333333;
                    local passBtnTextColor = 0xFFCC6666;
                    local passBtnHoverBgColor = 0xFF442222;
                    local passBtnHoverTextColor = 0xFFFF6666;

                    local isPassHovering = mouseX >= passBtnX and mouseX <= passBtnX + passBtnWidth
                                       and mouseY >= passBtnY and mouseY <= passBtnY + passBtnHeight;

                    if isPassHovering then
                        passBtnBgColor = passBtnHoverBgColor;
                        passBtnTextColor = passBtnHoverTextColor;
                        if imgui.IsMouseClicked(0) then
                            M.PassAllUnlotted();
                        end
                    end

                    if bgPrims.passButton then
                        bgPrims.passButton.position_x = passBtnX;
                        bgPrims.passButton.position_y = passBtnY;
                        bgPrims.passButton.width = passBtnWidth;
                        bgPrims.passButton.height = passBtnHeight;
                        bgPrims.passButton.color = passBtnBgColor;
                        bgPrims.passButton.visible = true;
                    end

                    if fonts.passButton then
                        fonts.passButton:set_position_x(passBtnX + btnPadX);
                        fonts.passButton:set_position_y(passBtnY + btnPadY);
                        if lastPassButtonColor ~= passBtnTextColor then
                            fonts.passButton:set_font_color(passBtnTextColor);
                            lastPassButtonColor = passBtnTextColor;
                        end
                        fonts.passButton:set_visible(true);
                    end
                end

                -- Skip rest of rendering when collapsed
                return;
            end

            -- ========================================
            -- Draw Treasure Pool Section
            -- ========================================
            if poolCount > 0 then
                -- Title: "Treasure Pool"
                local titleTextWidth = 0;
                if fonts.title then
                    fonts.title:set_font_height(14);
                    fonts.title:set_position_x(contentX);
                    fonts.title:set_position_y(currentY);
                    fonts.title:set_text('Treasure Pool');
                    titleTextWidth = fonts.title:get_text_size();
                    if lastTitleColor ~= 0xFFFFFFFF then
                        fonts.title:set_font_color(0xFFFFFFFF);
                        lastTitleColor = 0xFFFFFFFF;
                    end
                    fonts.title:set_visible(true);
                end

                -- Draw "Lot All" and "Pass All" buttons next to title
                local btnPadX = 6;
                local btnPadY = 2;
                local btnGap = 6;

                -- Lot All button
                local lotBtnTextWidth = 0;
                local lotBtnTextHeight = 10;
                if fonts.lotButton then
                    fonts.lotButton:set_font_height(10);
                    fonts.lotButton:set_text('Lot All');
                    lotBtnTextWidth, lotBtnTextHeight = fonts.lotButton:get_text_size();
                end

                local lotBtnWidth = lotBtnTextWidth + (btnPadX * 2);
                local lotBtnHeight = lotBtnTextHeight + (btnPadY * 2);
                local lotBtnX = contentX + titleTextWidth + 10;
                local lotBtnY = currentY + (titleHeight - lotBtnHeight) / 2;

                local lotBtnBgColor = 0xFF333333;
                local lotBtnTextColor = 0xFF66CC66;
                local lotBtnHoverBgColor = 0xFF224422;
                local lotBtnHoverTextColor = 0xFF66FF66;

                local isLotHovering = mouseX >= lotBtnX and mouseX <= lotBtnX + lotBtnWidth
                                  and mouseY >= lotBtnY and mouseY <= lotBtnY + lotBtnHeight;

                if isLotHovering then
                    lotBtnBgColor = lotBtnHoverBgColor;
                    lotBtnTextColor = lotBtnHoverTextColor;
                    if imgui.IsMouseClicked(0) then
                        M.LotAllUnlotted();
                    end
                end

                if bgPrims.lotButton then
                    bgPrims.lotButton.position_x = lotBtnX;
                    bgPrims.lotButton.position_y = lotBtnY;
                    bgPrims.lotButton.width = lotBtnWidth;
                    bgPrims.lotButton.height = lotBtnHeight;
                    bgPrims.lotButton.color = lotBtnBgColor;
                    bgPrims.lotButton.visible = true;
                end

                if fonts.lotButton then
                    fonts.lotButton:set_position_x(lotBtnX + btnPadX);
                    fonts.lotButton:set_position_y(lotBtnY + btnPadY);
                    if lastLotButtonColor ~= lotBtnTextColor then
                        fonts.lotButton:set_font_color(lotBtnTextColor);
                        lastLotButtonColor = lotBtnTextColor;
                    end
                    fonts.lotButton:set_visible(true);
                end

                -- Pass All button
                local passBtnTextWidth = 0;
                local passBtnTextHeight = 10;
                if fonts.passButton then
                    fonts.passButton:set_font_height(10);
                    fonts.passButton:set_text('Pass All');
                    passBtnTextWidth, passBtnTextHeight = fonts.passButton:get_text_size();
                end

                local passBtnWidth = passBtnTextWidth + (btnPadX * 2);
                local passBtnHeight = passBtnTextHeight + (btnPadY * 2);
                local passBtnX = lotBtnX + lotBtnWidth + btnGap;
                local passBtnY = currentY + (titleHeight - passBtnHeight) / 2;

                local passBtnBgColor = 0xFF333333;
                local passBtnTextColor = 0xFFCC6666;
                local passBtnHoverBgColor = 0xFF442222;
                local passBtnHoverTextColor = 0xFFFF6666;

                local isPassHovering = mouseX >= passBtnX and mouseX <= passBtnX + passBtnWidth
                                   and mouseY >= passBtnY and mouseY <= passBtnY + passBtnHeight;

                if isPassHovering then
                    passBtnBgColor = passBtnHoverBgColor;
                    passBtnTextColor = passBtnHoverTextColor;
                    if imgui.IsMouseClicked(0) then
                        M.PassAllUnlotted();
                    end
                end

                if bgPrims.passButton then
                    bgPrims.passButton.position_x = passBtnX;
                    bgPrims.passButton.position_y = passBtnY;
                    bgPrims.passButton.width = passBtnWidth;
                    bgPrims.passButton.height = passBtnHeight;
                    bgPrims.passButton.color = passBtnBgColor;
                    bgPrims.passButton.visible = true;
                end

                if fonts.passButton then
                    fonts.passButton:set_position_x(passBtnX + btnPadX);
                    fonts.passButton:set_position_y(passBtnY + btnPadY);
                    if lastPassButtonColor ~= passBtnTextColor then
                        fonts.passButton:set_font_color(passBtnTextColor);
                        lastPassButtonColor = passBtnTextColor;
                    end
                    fonts.passButton:set_visible(true);
                end

                currentY = currentY + titleHeight + itemSpacing;

                -- Draw each pool item
                for idx, item in ipairs(poolItems) do
                    if idx > MAX_POOL_ITEMS then break; end

                    -- Calculate item box dimensions first
                    local parties = sortAndAssignParties(item.lots or {});
                    local maxPartySize = 0;
                    for p = 1, NUM_PARTIES do
                        maxPartySize = math.max(maxPartySize, #parties[p]);
                    end

                    local itemBoxPaddingY = 8;
                    local itemBoxPaddingX = 8;
                    local itemBoxHeight = itemBoxPaddingY + itemNameHeight + itemSpacing + (maxPartySize * lotterLineHeight) + itemBoxPaddingY;

                    -- Draw item container border
                    if drawList then
                        drawList:AddRect(
                            {contentX - 2, currentY},
                            {contentX + contentWidth + 2, currentY + itemBoxHeight},
                            0xFF444444, 4, 0, 1
                        );
                    end

                    currentY = currentY + itemBoxPaddingY;
                    local itemX = contentX + itemBoxPaddingX;
                    local itemY = currentY;
                    local itemContentWidth = contentWidth - (itemBoxPaddingX * 2);

                    -- Draw item icon
                    local icon = loadItemIcon(item.itemId);
                    if icon and icon.image and drawList then
                        pcall(function()
                            drawList:AddImage(
                                tonumber(ffi.cast("uint32_t", icon.image)),
                                {itemX, itemY},
                                {itemX + iconSize, itemY + iconSize},
                                {0, 0}, {1, 1},
                                0xFFFFFFFF
                            );
                        end);
                    end

                    -- Draw item name
                    local nameFont = fonts.itemNames[idx];
                    if nameFont then
                        nameFont:set_font_height(12);
                        nameFont:set_position_x(itemX + iconSize + 6);
                        nameFont:set_position_y(itemY + 2);
                        nameFont:set_text(item.itemName or 'Unknown Item');
                        if lastItemNameColors[idx] ~= 0xFFFFFFFF then
                            nameFont:set_font_color(0xFFFFFFFF);
                            lastItemNameColors[idx] = 0xFFFFFFFF;
                        end
                        nameFont:set_visible(true);
                    end

                    -- Draw timer on right side
                    local remaining = notificationData.GetTreasurePoolTimeRemaining(item.slot);
                    local timerText = notificationData.FormatPoolTimer(remaining);
                    local timerColor;
                    if remaining > 60 then
                        timerColor = 0xFFFFFF4D;
                    elseif remaining > 30 then
                        timerColor = 0xFFFF9933;
                    else
                        timerColor = 0xFFFF4D4D;
                    end

                    local timerFont = fonts.timers[idx];
                    local timerWidth = 0;
                    if timerFont then
                        timerFont:set_font_height(10);
                        timerFont:set_text(timerText);
                        timerWidth, _ = timerFont:get_text_size();
                        timerFont:set_position_x(itemX + itemContentWidth - timerWidth);
                        timerFont:set_position_y(itemY + 3);
                        if lastTimerColors[idx] ~= timerColor then
                            timerFont:set_font_color(timerColor);
                            lastTimerColors[idx] = timerColor;
                        end
                        timerFont:set_visible(true);
                    end

                    -- Draw individual Lot and Pass buttons (to left of timer)
                    local itemBtnPadX = 4;
                    local itemBtnPadY = 1;
                    local itemBtnGap = 4;
                    local itemBtnY = itemY + 2;

                    -- Pass button (rightmost, left of timer)
                    local itemPassTextWidth = 0;
                    local itemPassTextHeight = 9;
                    if fonts.itemPassButtons[idx] then
                        fonts.itemPassButtons[idx]:set_font_height(9);
                        fonts.itemPassButtons[idx]:set_text('Pass');
                        itemPassTextWidth, itemPassTextHeight = fonts.itemPassButtons[idx]:get_text_size();
                    end

                    local itemPassBtnWidth = itemPassTextWidth + (itemBtnPadX * 2);
                    local itemPassBtnHeight = itemPassTextHeight + (itemBtnPadY * 2);
                    local itemPassBtnX = itemX + itemContentWidth - timerWidth - itemBtnGap - itemPassBtnWidth;

                    local itemPassBgColor = 0xFF333333;
                    local itemPassTextColor = 0xFFCC6666;

                    local isItemPassHovering = mouseX >= itemPassBtnX and mouseX <= itemPassBtnX + itemPassBtnWidth
                                           and mouseY >= itemBtnY and mouseY <= itemBtnY + itemPassBtnHeight;

                    if isItemPassHovering then
                        itemPassBgColor = 0xFF442222;
                        itemPassTextColor = 0xFFFF6666;
                        if imgui.IsMouseClicked(0) then
                            M.PassItem(item.slot);
                        end
                    end

                    if bgPrims.itemPassButtons[idx] then
                        bgPrims.itemPassButtons[idx].position_x = itemPassBtnX;
                        bgPrims.itemPassButtons[idx].position_y = itemBtnY;
                        bgPrims.itemPassButtons[idx].width = itemPassBtnWidth;
                        bgPrims.itemPassButtons[idx].height = itemPassBtnHeight;
                        bgPrims.itemPassButtons[idx].color = itemPassBgColor;
                        bgPrims.itemPassButtons[idx].visible = true;
                    end

                    if fonts.itemPassButtons[idx] then
                        fonts.itemPassButtons[idx]:set_position_x(itemPassBtnX + itemBtnPadX);
                        fonts.itemPassButtons[idx]:set_position_y(itemBtnY + itemBtnPadY);
                        if lastItemPassButtonColors[idx] ~= itemPassTextColor then
                            fonts.itemPassButtons[idx]:set_font_color(itemPassTextColor);
                            lastItemPassButtonColors[idx] = itemPassTextColor;
                        end
                        fonts.itemPassButtons[idx]:set_visible(true);
                    end

                    -- Lot button (left of Pass button)
                    local itemLotTextWidth = 0;
                    local itemLotTextHeight = 9;
                    if fonts.itemLotButtons[idx] then
                        fonts.itemLotButtons[idx]:set_font_height(9);
                        fonts.itemLotButtons[idx]:set_text('Lot');
                        itemLotTextWidth, itemLotTextHeight = fonts.itemLotButtons[idx]:get_text_size();
                    end

                    local itemLotBtnWidth = itemLotTextWidth + (itemBtnPadX * 2);
                    local itemLotBtnHeight = itemLotTextHeight + (itemBtnPadY * 2);
                    local itemLotBtnX = itemPassBtnX - itemBtnGap - itemLotBtnWidth;

                    local itemLotBgColor = 0xFF333333;
                    local itemLotTextColor = 0xFF66CC66;

                    local isItemLotHovering = mouseX >= itemLotBtnX and mouseX <= itemLotBtnX + itemLotBtnWidth
                                          and mouseY >= itemBtnY and mouseY <= itemBtnY + itemLotBtnHeight;

                    if isItemLotHovering then
                        itemLotBgColor = 0xFF224422;
                        itemLotTextColor = 0xFF66FF66;
                        if imgui.IsMouseClicked(0) then
                            M.LotItem(item.slot);
                        end
                    end

                    if bgPrims.itemLotButtons[idx] then
                        bgPrims.itemLotButtons[idx].position_x = itemLotBtnX;
                        bgPrims.itemLotButtons[idx].position_y = itemBtnY;
                        bgPrims.itemLotButtons[idx].width = itemLotBtnWidth;
                        bgPrims.itemLotButtons[idx].height = itemLotBtnHeight;
                        bgPrims.itemLotButtons[idx].color = itemLotBgColor;
                        bgPrims.itemLotButtons[idx].visible = true;
                    end

                    if fonts.itemLotButtons[idx] then
                        fonts.itemLotButtons[idx]:set_position_x(itemLotBtnX + itemBtnPadX);
                        fonts.itemLotButtons[idx]:set_position_y(itemBtnY + itemBtnPadY);
                        if lastItemLotButtonColors[idx] ~= itemLotTextColor then
                            fonts.itemLotButtons[idx]:set_font_color(itemLotTextColor);
                            lastItemLotButtonColors[idx] = itemLotTextColor;
                        end
                        fonts.itemLotButtons[idx]:set_visible(true);
                    end

                    currentY = currentY + itemNameHeight + itemSpacing;

                    -- Draw lot entries for each party (parties already calculated above)
                    local colWidthAdjusted = (itemContentWidth - (columnGap * 2)) / 3;
                    for row = 1, maxPartySize do
                        for p = 1, NUM_PARTIES do
                            local colX = itemX + ((p - 1) * (colWidthAdjusted + columnGap));
                            local lotInfo = parties[p][row];

                            if lotInfo then
                                local lotterFont = fonts.lotters[idx] and fonts.lotters[idx][p] and fonts.lotters[idx][p][row];
                                if lotterFont then
                                    local lotText;
                                    local lotColor;

                                    -- Truncate name if needed
                                    local displayName = lotInfo.name;
                                    if #displayName > 10 then
                                        displayName = displayName:sub(1, 9) .. '.';
                                    end

                                    if lotInfo.pending then
                                        lotText = string.format('%s - ...', displayName);
                                        lotColor = 0xFFE5B84D;  -- Light yellow/orange for pending
                                    elseif lotInfo.passed then
                                        lotText = string.format('%s - Pass', displayName);
                                        lotColor = 0xFF888888;
                                    else
                                        lotText = string.format('%s - %d', displayName, lotInfo.lot or 0);
                                        if lotInfo.lot == item.highestLot then
                                            lotColor = 0xFF4DFF4D;  -- Green for highest
                                        else
                                            lotColor = 0xFFCCCCCC;
                                        end
                                    end

                                    lotterFont:set_font_height(10);
                                    lotterFont:set_position_x(colX);
                                    lotterFont:set_position_y(currentY + ((row - 1) * lotterLineHeight));
                                    lotterFont:set_text(lotText);

                                    local colorKey = idx * 1000 + p * 100 + row;
                                    if lastLotterColors[colorKey] ~= lotColor then
                                        lotterFont:set_font_color(lotColor);
                                        lastLotterColors[colorKey] = lotColor;
                                    end
                                    lotterFont:set_visible(true);
                                end
                            end
                        end
                    end

                    currentY = currentY + (maxPartySize * lotterLineHeight) + itemBoxPaddingY + itemSpacing;
                end
            end

            -- ========================================
            -- Draw Recent History Section
            -- ========================================
            if historyCount > 0 then
                if poolCount > 0 then
                    currentY = currentY + sectionSpacing;

                    -- Draw separator line
                    if drawList then
                        local lineY = currentY - (sectionSpacing / 2);
                        drawList:AddLine(
                            {contentX, lineY},
                            {contentX + contentWidth, lineY},
                            0xFF444444, 1
                        );
                    end
                end

                -- Header: "Recent History"
                if fonts.header then
                    fonts.header:set_font_height(14);
                    fonts.header:set_position_x(contentX);
                    fonts.header:set_position_y(currentY);
                    fonts.header:set_text('Recent History');
                    if lastHeaderColor ~= 0xFFFFFFFF then
                        fonts.header:set_font_color(0xFFFFFFFF);
                        lastHeaderColor = 0xFFFFFFFF;
                    end
                    fonts.header:set_visible(true);
                end
                currentY = currentY + headerHeight + itemSpacing;

                -- Draw history items
                for idx, historyItem in ipairs(history) do
                    if idx > MAX_HISTORY_ITEMS then break; end

                    local histX = contentX;
                    local histY = currentY;

                    -- Draw item icon
                    local icon = loadItemIcon(historyItem.itemId);
                    if icon and icon.image and drawList then
                        pcall(function()
                            drawList:AddImage(
                                tonumber(ffi.cast("uint32_t", icon.image)),
                                {histX, histY},
                                {histX + 16, histY + 16},
                                {0, 0}, {1, 1},
                                0xFFFFFFFF
                            );
                        end);
                    end

                    -- Draw item name
                    local itemFont = fonts.historyItems[idx];
                    if itemFont then
                        itemFont:set_font_height(11);
                        itemFont:set_position_x(histX + 20);
                        itemFont:set_position_y(histY + 2);
                        itemFont:set_text(historyItem.itemName or 'Unknown Item');
                        if lastHistoryItemColors[idx] ~= 0xFFCCCCCC then
                            itemFont:set_font_color(0xFFCCCCCC);
                            lastHistoryItemColors[idx] = 0xFFCCCCCC;
                        end
                        itemFont:set_visible(true);
                    end

                    -- Draw winner name on right
                    local winnerFont = fonts.historyWinners[idx];
                    if winnerFont then
                        local winnerText = historyItem.winnerName or 'No Winner';
                        local winnerColor = historyItem.winnerName and 0xFF4DFF4D or 0xFF888888;

                        winnerFont:set_font_height(11);
                        winnerFont:set_text(winnerText);
                        local winnerWidth, _ = winnerFont:get_text_size();
                        winnerFont:set_position_x(contentX + contentWidth - winnerWidth);
                        winnerFont:set_position_y(histY + 2);
                        if lastHistoryWinnerColors[idx] ~= winnerColor then
                            winnerFont:set_font_color(winnerColor);
                            lastHistoryWinnerColors[idx] = winnerColor;
                        end
                        winnerFont:set_visible(true);
                    end

                    currentY = currentY + historyLineHeight;
                end
            end
        end);

        if not success and err then
            print('[XIUI RollsWindow] Render error: ' .. tostring(err));
        end
    end
    imgui.End();
end

function M.SetHidden(hidden)
    if hidden then
        SetFontsVisible(allFonts, false);
        if bgPrims.main then
            windowBg.hide(bgPrims.main);
        end
        if bgPrims.passButton then
            bgPrims.passButton.visible = false;
        end
        if bgPrims.lotButton then
            bgPrims.lotButton.visible = false;
        end
        for i = 1, MAX_POOL_ITEMS do
            if bgPrims.itemLotButtons[i] then
                bgPrims.itemLotButtons[i].visible = false;
            end
            if bgPrims.itemPassButtons[i] then
                bgPrims.itemPassButtons[i].visible = false;
            end
        end
    end
end

function M.Cleanup()
    -- Destroy all fonts
    if fonts.title then
        fonts.title = FontManager.destroy(fonts.title);
    end
    if fonts.header then
        fonts.header = FontManager.destroy(fonts.header);
    end
    if fonts.passButton then
        fonts.passButton = FontManager.destroy(fonts.passButton);
    end
    if fonts.lotButton then
        fonts.lotButton = FontManager.destroy(fonts.lotButton);
    end

    for p = 1, NUM_PARTIES do
        if fonts.partyHeaders[p] then
            fonts.partyHeaders[p] = FontManager.destroy(fonts.partyHeaders[p]);
        end
    end

    for i = 1, MAX_POOL_ITEMS do
        if fonts.itemNames[i] then
            fonts.itemNames[i] = FontManager.destroy(fonts.itemNames[i]);
        end
        if fonts.timers[i] then
            fonts.timers[i] = FontManager.destroy(fonts.timers[i]);
        end
        if fonts.lotters[i] then
            for p = 1, NUM_PARTIES do
                if fonts.lotters[i][p] then
                    for m = 1, PARTY_SIZE do
                        if fonts.lotters[i][p][m] then
                            fonts.lotters[i][p][m] = FontManager.destroy(fonts.lotters[i][p][m]);
                        end
                    end
                end
            end
        end
        if fonts.itemLotButtons[i] then
            fonts.itemLotButtons[i] = FontManager.destroy(fonts.itemLotButtons[i]);
        end
        if fonts.itemPassButtons[i] then
            fonts.itemPassButtons[i] = FontManager.destroy(fonts.itemPassButtons[i]);
        end
    end

    for i = 1, MAX_HISTORY_ITEMS do
        if fonts.historyItems[i] then
            fonts.historyItems[i] = FontManager.destroy(fonts.historyItems[i]);
        end
        if fonts.historyWinners[i] then
            fonts.historyWinners[i] = FontManager.destroy(fonts.historyWinners[i]);
        end
    end

    allFonts = {};
    fonts = {
        title = nil,
        header = nil,
        passButton = nil,
        lotButton = nil,
        itemNames = {},
        timers = {},
        partyHeaders = {},
        lotters = {},
        historyItems = {},
        historyWinners = {},
        itemLotButtons = {},
        itemPassButtons = {},
    };

    -- Destroy background
    if bgPrims.main then
        windowBg.destroy(bgPrims.main);
        bgPrims.main = nil;
    end

    -- Destroy button primitives
    if bgPrims.passButton then
        bgPrims.passButton:destroy();
        bgPrims.passButton = nil;
    end
    if bgPrims.lotButton then
        bgPrims.lotButton:destroy();
        bgPrims.lotButton = nil;
    end
    for i = 1, MAX_POOL_ITEMS do
        if bgPrims.itemLotButtons[i] then
            bgPrims.itemLotButtons[i]:destroy();
            bgPrims.itemLotButtons[i] = nil;
        end
        if bgPrims.itemPassButtons[i] then
            bgPrims.itemPassButtons[i]:destroy();
            bgPrims.itemPassButtons[i] = nil;
        end
    end
    bgPrims.itemLotButtons = {};
    bgPrims.itemPassButtons = {};

    -- Clear icon cache
    iconCache = {};

    -- Clear cached colors
    lastTitleColor = nil;
    lastHeaderColor = nil;
    lastPassButtonColor = nil;
    lastLotButtonColor = nil;
    lastItemLotButtonColors = {};
    lastItemPassButtonColors = {};
    lastItemNameColors = {};
    lastTimerColors = {};
    lastPartyHeaderColors = {};
    lastLotterColors = {};
    lastHistoryItemColors = {};
    lastHistoryWinnerColors = {};
end

-- ============================================
-- Toggle Function (called by command handler)
-- ============================================

function M.Toggle()
    M.isVisible = not M.isVisible;
    return M.isVisible;
end

function M.Show()
    M.isVisible = true;
end

function M.Hide()
    M.isVisible = false;
end

function M.ToggleCollapse()
    M.isCollapsed = not M.isCollapsed;
    return M.isCollapsed;
end

function M.Collapse()
    M.isCollapsed = true;
end

function M.Expand()
    M.isCollapsed = false;
end

-- ============================================
-- Pass All Unlotted Function
-- ============================================

-- Pass on all treasure pool items that player has NOT already lotted on
-- Skips items where player's lot is 1-999 (already lotted)
-- Passes on items where lot is 0, nil, or 65535 (not lotted/pending)
function M.PassAllUnlotted()
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then
        print('[XIUI] Cannot access inventory');
        return;
    end

    local packetManager = AshitaCore:GetPacketManager();
    if not packetManager then
        print('[XIUI] Cannot access packet manager');
        return;
    end

    -- Count items to pass (skip already lotted)
    local passedCount = 0;
    for slot = 0, 9 do
        local item = inventory:GetTreasurePoolItem(slot);
        if item and item.ItemId and item.ItemId ~= 0 then
            local lot = item.Lot;
            -- Skip if already lotted (1-999)
            if lot == nil or lot == 0 or lot >= 65535 then
                -- Send Pass Item packet (0x042)
                -- Packet structure from XITools: { 0x00, 0x00, 0x00, 0x00, slot }
                packetManager:AddOutgoingPacket(0x042, { 0x00, 0x00, 0x00, 0x00, slot });
                passedCount = passedCount + 1;
            end
        end
    end

    if passedCount > 0 then
        print('[XIUI] Passed on ' .. passedCount .. ' item(s)');
    else
        print('[XIUI] No items to pass on (all already lotted or pool empty)');
    end
end

-- ============================================
-- Lot All Unlotted Function
-- ============================================

-- Lot on all treasure pool items that player has NOT already lotted on
-- Skips items where player's lot is 1-999 (already lotted)
-- Lots on items where lot is 0, nil, or 65535 (not lotted/pending)
function M.LotAllUnlotted()
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if not inventory then
        print('[XIUI] Cannot access inventory');
        return;
    end

    local packetManager = AshitaCore:GetPacketManager();
    if not packetManager then
        print('[XIUI] Cannot access packet manager');
        return;
    end

    -- Count items to lot (skip already lotted)
    local lottedCount = 0;
    for slot = 0, 9 do
        local item = inventory:GetTreasurePoolItem(slot);
        if item and item.ItemId and item.ItemId ~= 0 then
            local lot = item.Lot;
            -- Skip if already lotted (1-999)
            if lot == nil or lot == 0 or lot >= 65535 then
                -- Send Lot Item packet (0x041)
                packetManager:AddOutgoingPacket(0x041, { 0x00, 0x00, 0x00, 0x00, slot });
                lottedCount = lottedCount + 1;
            end
        end
    end

    if lottedCount > 0 then
        print('[XIUI] Lotted on ' .. lottedCount .. ' item(s)');
    else
        print('[XIUI] No items to lot on (all already lotted or pool empty)');
    end
end

-- ============================================
-- Individual Item Functions
-- ============================================

-- Lot on a specific treasure pool item by slot
function M.LotItem(slot)
    local packetManager = AshitaCore:GetPacketManager();
    if not packetManager then
        print('[XIUI] Cannot access packet manager');
        return;
    end

    -- Send Lot Item packet (0x041)
    packetManager:AddOutgoingPacket(0x041, { 0x00, 0x00, 0x00, 0x00, slot });
end

-- Pass on a specific treasure pool item by slot
function M.PassItem(slot)
    local packetManager = AshitaCore:GetPacketManager();
    if not packetManager then
        print('[XIUI] Cannot access packet manager');
        return;
    end

    -- Send Pass Item packet (0x042)
    packetManager:AddOutgoingPacket(0x042, { 0x00, 0x00, 0x00, 0x00, slot });
end

return M;
