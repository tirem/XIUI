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
local imtext = require('libs.imtext');
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
M.forceShow = false;

-- ============================================
-- Module Lifecycle
-- ============================================

function M.Initialize(settings)
    if M.initialized then return; end

    if gConfig then
        gConfig.treasurePoolPreview = false;

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
        if gConfig.treasurePoolBgScale == nil or gConfig.treasurePoolBgScale < 0.1 then
            gConfig.treasurePoolBgScale = 1.0;
        end
        if gConfig.treasurePoolBorderScale == nil or gConfig.treasurePoolBorderScale < 0.1 then
            gConfig.treasurePoolBorderScale = 1.0;
        end
        if gConfig.treasurePoolBackgroundOpacity == nil then
            if gConfig.treasurePoolOpacity ~= nil then
                gConfig.treasurePoolBackgroundOpacity = gConfig.treasurePoolOpacity;
                gConfig.treasurePoolOpacity = nil;
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

    data.Initialize();

    display.Initialize(settings);

    M.initialized = true;
end

function M.UpdateVisuals(settings)
    if not M.initialized then return; end

    imtext.Reset();
    data.ClearColorCache();
    display.UpdateVisuals(settings);
end

function M.DrawWindow(settings)
    if not M.initialized then return; end
    if not M.visible then return; end

    if not data.IsPreviewActive() then
        data.ReadFromMemory();
    end

    local hasRealItems = data.HasRealItems();
    local hasHistory = data.HasWonHistory();
    local historyCount = data.GetWonHistoryCount();
    local poolCount = data.GetPoolCount();

    local enabled = gConfig.treasurePoolEnabled;
    local autoHide = gConfig.treasurePoolAutoHideWhenEmpty ~= false;
    local showWindow;
    if autoHide then
        showWindow = (hasRealItems or data.previewEnabled or M.forceShow) and enabled;
    else
        showWindow = (hasRealItems or hasHistory or data.previewEnabled or M.forceShow) and enabled;
    end

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

function M.SetHidden(hidden)
    M.visible = not hidden;
    display.SetHidden(hidden);
end

function M.Cleanup()
    if not M.initialized then return; end

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

function M.ToggleForceShow()
    M.forceShow = not M.forceShow;
    local state = M.forceShow and 'shown' or 'hidden';
    print('[XIUI] Treasure pool window ' .. state);
end

function M.IsForceShowActive()
    return M.forceShow;
end

return M;
