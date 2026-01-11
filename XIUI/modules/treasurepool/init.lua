--[[
* XIUI Treasure Pool Module
* Provides dedicated treasure pool tracking UI separate from toast notifications
* Features:
*   - Collapsed view: compact display with item icons, timers, and highest lot
*   - Expanded view: detailed view with all lotters, passers, and lot/pass buttons
*   - Memory-based state: reads directly from Ashita memory API
*   - Packet tracking: tracks all party members' lot/pass actions via 0x00D3
*   - Notification integration: triggers toast notifications for new items
]]--

require('common');
require('handlers.helpers');
local gdi = require('submodules.gdifonts.include');
local windowBg = require('libs.windowbackground');

local data = require('modules.treasurepool.data');
local display = require('modules.treasurepool.display');
local actions = require('modules.treasurepool.actions');

local M = {};

-- Debug logging (set to true to enable)
local DEBUG_ENABLED = false;
local function debugLog(msg, ...)
    if DEBUG_ENABLED then
        local formatted = string.format('[TP Debug] ' .. msg, ...);
        print(formatted);
    end
end

-- ============================================
-- Module State
-- ============================================

M.initialized = false;
M.visible = true;
M.forceShow = false;  -- When true, show window even if no content

-- ============================================
-- Module Lifecycle
-- ============================================

-- Initialize the treasure pool module
function M.Initialize(settings)
    if M.initialized then return; end

    -- Ensure treasure pool settings have defaults BEFORE creating fonts
    if gConfig then
        -- Clear any stale preview state
        gConfig.treasurePoolPreview = false;

        -- Set defaults for new settings
        if gConfig.treasurePoolEnabled == nil then gConfig.treasurePoolEnabled = true; end
        if gConfig.treasurePoolShowTimerBar == nil then gConfig.treasurePoolShowTimerBar = true; end
        if gConfig.treasurePoolShowTimerText == nil then gConfig.treasurePoolShowTimerText = true; end
        if gConfig.treasurePoolShowLots == nil then gConfig.treasurePoolShowLots = true; end
        if gConfig.treasurePoolFontSize == nil or gConfig.treasurePoolFontSize < 8 then
            gConfig.treasurePoolFontSize = 10;
        end
        if gConfig.treasurePoolScaleX == nil or gConfig.treasurePoolScaleX < 0.5 then
            gConfig.treasurePoolScaleX = 1.0;
        end
        if gConfig.treasurePoolScaleY == nil or gConfig.treasurePoolScaleY < 0.5 then
            gConfig.treasurePoolScaleY = 1.0;
        end
        -- Split background/border settings (like petbar)
        if gConfig.treasurePoolBgScale == nil or gConfig.treasurePoolBgScale < 0.1 then
            gConfig.treasurePoolBgScale = 1.0;
        end
        if gConfig.treasurePoolBorderScale == nil or gConfig.treasurePoolBorderScale < 0.1 then
            gConfig.treasurePoolBorderScale = 1.0;
        end
        -- Migrate old treasurePoolOpacity to new split settings
        if gConfig.treasurePoolBackgroundOpacity == nil then
            if gConfig.treasurePoolOpacity ~= nil then
                gConfig.treasurePoolBackgroundOpacity = gConfig.treasurePoolOpacity;
                gConfig.treasurePoolOpacity = nil;  -- Clean up old setting
            else
                gConfig.treasurePoolBackgroundOpacity = 0.87;
            end
        end
        if gConfig.treasurePoolBorderOpacity == nil then gConfig.treasurePoolBorderOpacity = 1.0; end
        if gConfig.treasurePoolBackgroundTheme == nil then gConfig.treasurePoolBackgroundTheme = 'Plain'; end
        if gConfig.treasurePoolExpanded == nil then gConfig.treasurePoolExpanded = false; end
        if gConfig.treasurePoolMinimized == nil then gConfig.treasurePoolMinimized = false; end
        if gConfig.treasurePoolShowButtonsInCollapsed == nil then gConfig.treasurePoolShowButtonsInCollapsed = true; end
        if gConfig.treasurePoolAutoHideWhenEmpty == nil then gConfig.treasurePoolAutoHideWhenEmpty = true; end
    end

    -- Initialize data layer first
    data.Initialize();

    -- Create fonts using settings from gAdjustedSettings.treasurePoolSettings
    -- (passed in as 'settings' parameter by module registry)
    -- Settings include global font family/weight applied via updater.lua
    local fontSettings = settings and settings.font_settings;
    local titleFontSettings = settings and settings.title_font_settings;

    -- Validate font settings exist before creating fonts
    if not fontSettings or not titleFontSettings then
        print('[XIUI TreasurePool] Warning: Invalid font settings, skipping font creation');
        M.initialized = true;
        return;
    end

    -- Create header font
    data.headerFont = FontManager.create(titleFontSettings);

    -- Create fonts for each pool slot (0-9)
    -- Only create basic fonts initially to reduce font count
    data.itemNameFonts = {};
    data.timerFonts = {};
    data.lotFonts = {};
    data.lottersFonts = {};
    data.passersFonts = {};
    data.pendingFonts = {};
    data.lotItemFonts = {};
    data.passItemFonts = {};

    -- Use pcall for safety during font creation
    local function safeCreateFont(settings)
        local success, result = pcall(function()
            return FontManager.create(settings);
        end);
        if success then
            return result;
        end
        print('[XIUI TreasurePool] Warning: Font creation failed');
        return nil;
    end

    -- Initialize member fonts table
    data.memberFonts = {};

    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        data.itemNameFonts[slot] = safeCreateFont(fontSettings);
        data.timerFonts[slot] = safeCreateFont(fontSettings);
        data.lotFonts[slot] = safeCreateFont(fontSettings);
        -- Expanded view detail fonts (disabled - not currently used)
        data.lottersFonts[slot] = nil;
        data.passersFonts[slot] = nil;
        data.pendingFonts[slot] = nil;
        -- Per-item button label fonts
        data.lotItemFonts[slot] = safeCreateFont(fontSettings);
        data.passItemFonts[slot] = safeCreateFont(fontSettings);

        -- Member fonts for expanded view (18 per slot for alliance support)
        data.memberFonts[slot] = {};
        for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
            data.memberFonts[slot][memberIdx] = safeCreateFont(fontSettings);
        end
    end

    -- Button label fonts (header)
    data.lotAllFont = safeCreateFont(fontSettings);
    data.passAllFont = safeCreateFont(fontSettings);
    data.toggleFont = safeCreateFont(fontSettings);

    -- Tab fonts
    data.tabPoolFont = safeCreateFont(fontSettings);
    data.tabHistoryFont = safeCreateFont(fontSettings);

    -- History fonts (for recent history tab)
    data.historyItemFonts = {};
    data.historyWinnerFonts = {};
    for i = 0, data.MAX_HISTORY_ITEMS - 1 do
        data.historyItemFonts[i] = safeCreateFont(fontSettings);
        data.historyWinnerFonts[i] = safeCreateFont(fontSettings);
    end

    -- Build allFonts list for batch visibility control
    data.allFonts = {data.headerFont, data.lotAllFont, data.passAllFont, data.toggleFont,
                     data.tabPoolFont, data.tabHistoryFont};
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        table.insert(data.allFonts, data.itemNameFonts[slot]);
        table.insert(data.allFonts, data.timerFonts[slot]);
        table.insert(data.allFonts, data.lotFonts[slot]);
        table.insert(data.allFonts, data.lottersFonts[slot]);
        table.insert(data.allFonts, data.passersFonts[slot]);
        table.insert(data.allFonts, data.pendingFonts[slot]);
        table.insert(data.allFonts, data.lotItemFonts[slot]);
        table.insert(data.allFonts, data.passItemFonts[slot]);
        -- Member fonts
        if data.memberFonts[slot] then
            for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                table.insert(data.allFonts, data.memberFonts[slot][memberIdx]);
            end
        end
    end
    -- History fonts
    for i = 0, data.MAX_HISTORY_ITEMS - 1 do
        table.insert(data.allFonts, data.historyItemFonts[i]);
        table.insert(data.allFonts, data.historyWinnerFonts[i]);
    end

    -- Hide all fonts initially
    data.SetAllFontsVisible(false);

    -- Initialize display layer (creates background primitive)
    display.Initialize(settings);

    M.initialized = true;
end

-- Update visual elements (fonts, themes) when settings change
function M.UpdateVisuals(settings)
    if not M.initialized then return; end

    -- Validate settings
    if not settings or not settings.font_settings or not settings.title_font_settings then
        return;
    end

    -- Settings include global font family/weight applied via updater.lua
    local fontSettings = settings.font_settings;
    local titleFontSettings = settings.title_font_settings;

    -- Recreate header font
    if data.headerFont then
        data.headerFont = FontManager.recreate(data.headerFont, titleFontSettings);
    end

    -- Recreate slot fonts (only if they exist)
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        if data.itemNameFonts[slot] then
            data.itemNameFonts[slot] = FontManager.recreate(data.itemNameFonts[slot], fontSettings);
        end
        if data.timerFonts[slot] then
            data.timerFonts[slot] = FontManager.recreate(data.timerFonts[slot], fontSettings);
        end
        if data.lotFonts[slot] then
            data.lotFonts[slot] = FontManager.recreate(data.lotFonts[slot], fontSettings);
        end
        -- Expanded view detail fonts (only recreate if they exist)
        if data.lottersFonts[slot] then
            data.lottersFonts[slot] = FontManager.recreate(data.lottersFonts[slot], fontSettings);
        end
        if data.passersFonts[slot] then
            data.passersFonts[slot] = FontManager.recreate(data.passersFonts[slot], fontSettings);
        end
        if data.pendingFonts[slot] then
            data.pendingFonts[slot] = FontManager.recreate(data.pendingFonts[slot], fontSettings);
        end
        -- Per-item button fonts (only recreate if they exist)
        if data.lotItemFonts[slot] then
            data.lotItemFonts[slot] = FontManager.recreate(data.lotItemFonts[slot], fontSettings);
        end
        if data.passItemFonts[slot] then
            data.passItemFonts[slot] = FontManager.recreate(data.passItemFonts[slot], fontSettings);
        end
        -- Member fonts
        if data.memberFonts[slot] then
            for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                if data.memberFonts[slot][memberIdx] then
                    data.memberFonts[slot][memberIdx] = FontManager.recreate(data.memberFonts[slot][memberIdx], fontSettings);
                end
            end
        end
    end

    -- Button label fonts (only recreate if they exist)
    if data.lotAllFont then
        data.lotAllFont = FontManager.recreate(data.lotAllFont, fontSettings);
    end
    if data.passAllFont then
        data.passAllFont = FontManager.recreate(data.passAllFont, fontSettings);
    end
    if data.toggleFont then
        data.toggleFont = FontManager.recreate(data.toggleFont, fontSettings);
    end

    -- Tab fonts
    if data.tabPoolFont then
        data.tabPoolFont = FontManager.recreate(data.tabPoolFont, fontSettings);
    end
    if data.tabHistoryFont then
        data.tabHistoryFont = FontManager.recreate(data.tabHistoryFont, fontSettings);
    end

    -- History fonts
    for i = 0, data.MAX_HISTORY_ITEMS - 1 do
        if data.historyItemFonts[i] then
            data.historyItemFonts[i] = FontManager.recreate(data.historyItemFonts[i], fontSettings);
        end
        if data.historyWinnerFonts[i] then
            data.historyWinnerFonts[i] = FontManager.recreate(data.historyWinnerFonts[i], fontSettings);
        end
    end

    -- Rebuild allFonts list
    data.allFonts = {data.headerFont, data.lotAllFont, data.passAllFont, data.toggleFont,
                     data.tabPoolFont, data.tabHistoryFont};
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        table.insert(data.allFonts, data.itemNameFonts[slot]);
        table.insert(data.allFonts, data.timerFonts[slot]);
        table.insert(data.allFonts, data.lotFonts[slot]);
        table.insert(data.allFonts, data.lottersFonts[slot]);
        table.insert(data.allFonts, data.passersFonts[slot]);
        table.insert(data.allFonts, data.pendingFonts[slot]);
        table.insert(data.allFonts, data.lotItemFonts[slot]);
        table.insert(data.allFonts, data.passItemFonts[slot]);
        -- Member fonts
        if data.memberFonts[slot] then
            for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                table.insert(data.allFonts, data.memberFonts[slot][memberIdx]);
            end
        end
    end
    -- History fonts
    for i = 0, data.MAX_HISTORY_ITEMS - 1 do
        table.insert(data.allFonts, data.historyItemFonts[i]);
        table.insert(data.allFonts, data.historyWinnerFonts[i]);
    end

    -- Clear color cache
    data.ClearColorCache();

    -- Update display layer
    display.UpdateVisuals(settings);
end

-- Main render function - called every frame
function M.DrawWindow(settings)
    if not M.initialized then return; end
    if not M.visible then return; end

    -- Read pool state from memory (skip in preview mode)
    if not data.IsPreviewActive() then
        data.ReadFromMemory();
    end

    -- Check for real items (from memory, not preview) or history items
    local hasRealItems = data.HasRealItems();
    local hasHistory = data.HasWonHistory();
    local historyCount = data.GetWonHistoryCount();
    local poolCount = data.GetPoolCount();

    -- Draw treasure pool if enabled and has content to show
    local enabled = gConfig.treasurePoolEnabled;
    local autoHide = gConfig.treasurePoolAutoHideWhenEmpty ~= false; -- Default to true if not set
    local showWindow;
    if autoHide then
        -- Auto-hide enabled: only show if pool has items (or preview/force show)
        showWindow = (hasRealItems or data.previewEnabled or M.forceShow) and enabled;
    else
        -- Auto-hide disabled: show if pool has items OR has history
        showWindow = (hasRealItems or hasHistory or data.previewEnabled or M.forceShow) and enabled;
    end

    -- Debug: Log state changes (throttled to avoid spam)
    local stateKey = string.format('%s_%s_%s_%s_%d_%d',
        tostring(hasRealItems), tostring(hasHistory), tostring(showWindow), tostring(M.forceShow), poolCount, historyCount);
    if M._lastStateKey ~= stateKey then
        debugLog('State: pool=%d history=%d hasReal=%s hasHist=%s show=%s preview=%s force=%s',
            poolCount, historyCount, tostring(hasRealItems), tostring(hasHistory),
            tostring(showWindow), tostring(data.previewEnabled), tostring(M.forceShow));
        M._lastStateKey = stateKey;
    end

    if showWindow then
        display.DrawWindow(settings);
    else
        display.HideWindow();
    end
end

-- Set module visibility
function M.SetHidden(hidden)
    M.visible = not hidden;
    if hidden then
        data.SetAllFontsVisible(false);
    end
    display.SetHidden(hidden);
end

-- Cleanup on addon unload
function M.Cleanup()
    if not M.initialized then return; end

    -- Destroy header and button fonts
    data.headerFont = FontManager.destroy(data.headerFont);
    data.lotAllFont = FontManager.destroy(data.lotAllFont);
    data.passAllFont = FontManager.destroy(data.passAllFont);
    data.toggleFont = FontManager.destroy(data.toggleFont);

    -- Destroy tab fonts
    data.tabPoolFont = FontManager.destroy(data.tabPoolFont);
    data.tabHistoryFont = FontManager.destroy(data.tabHistoryFont);

    -- Destroy history fonts
    for i = 0, data.MAX_HISTORY_ITEMS - 1 do
        if data.historyItemFonts[i] then
            data.historyItemFonts[i] = FontManager.destroy(data.historyItemFonts[i]);
        end
        if data.historyWinnerFonts[i] then
            data.historyWinnerFonts[i] = FontManager.destroy(data.historyWinnerFonts[i]);
        end
    end

    -- Destroy per-slot fonts
    for slot = 0, data.MAX_POOL_SLOTS - 1 do
        if data.itemNameFonts[slot] then
            data.itemNameFonts[slot] = FontManager.destroy(data.itemNameFonts[slot]);
        end
        if data.timerFonts[slot] then
            data.timerFonts[slot] = FontManager.destroy(data.timerFonts[slot]);
        end
        if data.lotFonts[slot] then
            data.lotFonts[slot] = FontManager.destroy(data.lotFonts[slot]);
        end
        -- Expanded view fonts
        if data.lottersFonts[slot] then
            data.lottersFonts[slot] = FontManager.destroy(data.lottersFonts[slot]);
        end
        if data.passersFonts[slot] then
            data.passersFonts[slot] = FontManager.destroy(data.passersFonts[slot]);
        end
        if data.pendingFonts[slot] then
            data.pendingFonts[slot] = FontManager.destroy(data.pendingFonts[slot]);
        end
        if data.lotItemFonts[slot] then
            data.lotItemFonts[slot] = FontManager.destroy(data.lotItemFonts[slot]);
        end
        if data.passItemFonts[slot] then
            data.passItemFonts[slot] = FontManager.destroy(data.passItemFonts[slot]);
        end
        -- Member fonts
        if data.memberFonts[slot] then
            for memberIdx = 0, data.MAX_MEMBERS_PER_ITEM - 1 do
                if data.memberFonts[slot][memberIdx] then
                    data.memberFonts[slot][memberIdx] = FontManager.destroy(data.memberFonts[slot][memberIdx]);
                end
            end
        end
    end

    -- Clear font tables
    data.allFonts = nil;
    data.itemNameFonts = {};
    data.timerFonts = {};
    data.lotFonts = {};
    data.lottersFonts = {};
    data.passersFonts = {};
    data.pendingFonts = {};
    data.lotItemFonts = {};
    data.passItemFonts = {};
    data.memberFonts = {};
    data.historyItemFonts = {};
    data.historyWinnerFonts = {};

    -- Cleanup display and data layers
    display.Cleanup();
    data.Cleanup();

    M.initialized = false;
end

-- ============================================
-- Zone Change Handler
-- ============================================

function M.HandleZonePacket()
    data.Clear();
end

-- ============================================
-- Packet Handler
-- ============================================

-- Handle 0x00D3 lot packet (called from XIUI.lua)
function M.HandleLotPacket(slot, entryServerId, entryName, entryFlg, entryLot,
                           winnerServerId, winnerName, winnerLot, judgeFlg)
    data.HandleLotPacket(slot, entryServerId, entryName, entryFlg, entryLot,
                         winnerServerId, winnerName, winnerLot, judgeFlg);
end

-- ============================================
-- Command Interface
-- ============================================

function M.LotAll()
    return actions.LotAll();
end

function M.PassAll()
    return actions.PassAll();
end

function M.LotItem(slot)
    return actions.LotItem(slot);
end

function M.PassItem(slot)
    return actions.PassItem(slot);
end

-- ============================================
-- Query Interface
-- ============================================

function M.GetPoolCount()
    return data.GetPoolCount();
end

function M.HasItems()
    return data.HasItems();
end

function M.GetPoolItems()
    return data.GetPoolItems();
end

-- ============================================
-- Preview Mode
-- ============================================

function M.SetPreview(enabled)
    data.SetPreview(enabled);
end

function M.IsPreviewActive()
    return data.IsPreviewActive();
end

function M.ClearPreview()
    data.ClearPreview();
end

-- ============================================
-- ResetPositions
-- ============================================

function M.ResetPositions()
    display.ResetPositions();
end

-- Force show the window (even if empty)
function M.ToggleForceShow()
    M.forceShow = not M.forceShow;
    local state = M.forceShow and 'shown' or 'hidden';
    print('[XIUI] Treasure pool window ' .. state);
end

function M.IsForceShowActive()
    return M.forceShow;
end

return M;
