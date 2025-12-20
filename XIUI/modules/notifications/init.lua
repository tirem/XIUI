--[[
* XIUI Notifications Module
* Main entry point that provides access to data, display, and handler modules
* Displays toast-style notifications for party invites, trades, treasure, and chat mentions
]]--

require('common');
require('handlers.helpers');
local gdi = require('submodules.gdifonts.include');
local primitives = require('primitives');
local windowBg = require('libs.windowbackground');

local data = require('modules.notifications.data');
local display = require('modules.notifications.display');
local handler = require('handlers.notificationhandler');

local notifications = {};

-- Connect handler to data module
handler.SetDataModule(data);

-- ============================================
-- Initialize
-- ============================================
notifications.Initialize = function(settings)
    -- Wrap in pcall to catch and report errors without crashing
    local success, err = pcall(function()
        -- Set zoning grace period immediately on initialize to block inventory sync
        handler.HandleZonePacket();

        -- Initialize data module (clears any leftover state)
        data.Initialize(settings);

        -- Get font settings
        local titleFontSettings = settings.title_font_settings or {};
        local fontSettings = settings.font_settings or {};

        -- Create fonts for each notification slot (following petbar pattern)
        data.titleFonts = {};
        data.subtitleFonts = {};
        data.allFonts = {};

        for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
            -- Title font for slot i
            data.titleFonts[i] = FontManager.create({
                font_alignment = titleFontSettings.font_alignment or gdi.Alignment.Left,
                font_family = titleFontSettings.font_family or 'Consolas',
                font_height = titleFontSettings.font_height or 14,
                font_color = titleFontSettings.font_color or 0xFFFFFFFF,
                font_flags = titleFontSettings.font_flags or gdi.FontFlags.Bold,
                outline_color = titleFontSettings.outline_color or 0xFF000000,
                outline_width = titleFontSettings.outline_width or 2,
            });

            -- Subtitle font for slot i
            data.subtitleFonts[i] = FontManager.create({
                font_alignment = fontSettings.font_alignment or gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = fontSettings.font_height or 12,
                font_color = fontSettings.font_color or 0xFFCCCCCC,
                font_flags = fontSettings.font_flags or gdi.FontFlags.None,
                outline_color = fontSettings.outline_color or 0xFF000000,
                outline_width = fontSettings.outline_width or 2,
            });

            -- Add to allFonts for batch visibility control
            table.insert(data.allFonts, data.titleFonts[i]);
            table.insert(data.allFonts, data.subtitleFonts[i]);
        end

        -- Create background primitives for each notification slot
        local prim_data = {
            visible = false,
            can_focus = false,
            locked = true,
            width = settings.width or 280,
            height = 80,
        };

        -- Get background theme and scales from config
        local bgTheme = gConfig.notificationsBackgroundTheme or 'Plain';
        local bgScale = gConfig.notificationsBgScale or 1.0;
        local borderScale = gConfig.notificationsBorderScale or 1.0;

        -- Track the loaded theme for change detection
        data.loadedBgTheme = bgTheme;

        data.bgPrims = {};
        for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
            data.bgPrims[i] = windowBg.create(prim_data, bgTheme, bgScale, borderScale);
        end

        -- Create fonts and primitives for split window placeholders
        data.splitTitleFonts = {};
        data.splitSubtitleFonts = {};
        data.splitBgPrims = {};

        for _, splitKey in ipairs(data.SPLIT_WINDOW_KEYS) do
            -- Title font for split window placeholder
            data.splitTitleFonts[splitKey] = FontManager.create({
                font_alignment = titleFontSettings.font_alignment or gdi.Alignment.Left,
                font_family = titleFontSettings.font_family or 'Consolas',
                font_height = titleFontSettings.font_height or 14,
                font_color = titleFontSettings.font_color or 0xFFFFFFFF,
                font_flags = titleFontSettings.font_flags or gdi.FontFlags.Bold,
                outline_color = titleFontSettings.outline_color or 0xFF000000,
                outline_width = titleFontSettings.outline_width or 2,
            });

            -- Subtitle font for split window placeholder
            data.splitSubtitleFonts[splitKey] = FontManager.create({
                font_alignment = fontSettings.font_alignment or gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = fontSettings.font_height or 12,
                font_color = fontSettings.font_color or 0xFFCCCCCC,
                font_flags = fontSettings.font_flags or gdi.FontFlags.None,
                outline_color = fontSettings.outline_color or 0xFF000000,
                outline_width = fontSettings.outline_width or 2,
            });

            -- Add to allFonts for batch visibility control
            table.insert(data.allFonts, data.splitTitleFonts[splitKey]);
            table.insert(data.allFonts, data.splitSubtitleFonts[splitKey]);

            -- Background primitive for split window placeholder
            data.splitBgPrims[splitKey] = windowBg.create(prim_data, bgTheme, bgScale, borderScale);
        end

        -- Clear cached colors
        data.ClearColorCache();

        -- Initialize display module (loads icons)
        display.Initialize(settings);
    end);

    if not success and err then
        print('[XIUI Notifications] Initialize Error: ' .. tostring(err));
    end
end

-- ============================================
-- UpdateVisuals
-- ============================================
notifications.UpdateVisuals = function(settings)
    -- Get font settings
    local titleFontSettings = settings.title_font_settings or {};
    local fontSettings = settings.font_settings or {};

    -- Recreate fonts for each slot
    for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
        if data.titleFonts[i] then
            data.titleFonts[i] = FontManager.recreate(data.titleFonts[i], {
                font_alignment = titleFontSettings.font_alignment or gdi.Alignment.Left,
                font_family = titleFontSettings.font_family or 'Consolas',
                font_height = titleFontSettings.font_height or 14,
                font_color = titleFontSettings.font_color or 0xFFFFFFFF,
                font_flags = titleFontSettings.font_flags or gdi.FontFlags.Bold,
                outline_color = titleFontSettings.outline_color or 0xFF000000,
                outline_width = titleFontSettings.outline_width or 2,
            });
        end

        if data.subtitleFonts[i] then
            data.subtitleFonts[i] = FontManager.recreate(data.subtitleFonts[i], {
                font_alignment = fontSettings.font_alignment or gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = fontSettings.font_height or 12,
                font_color = fontSettings.font_color or 0xFFCCCCCC,
                font_flags = fontSettings.font_flags or gdi.FontFlags.None,
                outline_color = fontSettings.outline_color or 0xFF000000,
                outline_width = fontSettings.outline_width or 2,
            });
        end
    end

    -- Recreate split window placeholder fonts
    for _, splitKey in ipairs(data.SPLIT_WINDOW_KEYS) do
        if data.splitTitleFonts[splitKey] then
            data.splitTitleFonts[splitKey] = FontManager.recreate(data.splitTitleFonts[splitKey], {
                font_alignment = titleFontSettings.font_alignment or gdi.Alignment.Left,
                font_family = titleFontSettings.font_family or 'Consolas',
                font_height = titleFontSettings.font_height or 14,
                font_color = titleFontSettings.font_color or 0xFFFFFFFF,
                font_flags = titleFontSettings.font_flags or gdi.FontFlags.Bold,
                outline_color = titleFontSettings.outline_color or 0xFF000000,
                outline_width = titleFontSettings.outline_width or 2,
            });
        end

        if data.splitSubtitleFonts[splitKey] then
            data.splitSubtitleFonts[splitKey] = FontManager.recreate(data.splitSubtitleFonts[splitKey], {
                font_alignment = fontSettings.font_alignment or gdi.Alignment.Left,
                font_family = fontSettings.font_family or 'Consolas',
                font_height = fontSettings.font_height or 12,
                font_color = fontSettings.font_color or 0xFFCCCCCC,
                font_flags = fontSettings.font_flags or gdi.FontFlags.None,
                outline_color = fontSettings.outline_color or 0xFF000000,
                outline_width = fontSettings.outline_width or 2,
            });
        end
    end

    -- Rebuild allFonts list
    data.allFonts = {};
    for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
        if data.titleFonts[i] then
            table.insert(data.allFonts, data.titleFonts[i]);
        end
        if data.subtitleFonts[i] then
            table.insert(data.allFonts, data.subtitleFonts[i]);
        end
    end
    -- Add split window fonts to allFonts
    for _, splitKey in ipairs(data.SPLIT_WINDOW_KEYS) do
        if data.splitTitleFonts[splitKey] then
            table.insert(data.allFonts, data.splitTitleFonts[splitKey]);
        end
        if data.splitSubtitleFonts[splitKey] then
            table.insert(data.allFonts, data.splitSubtitleFonts[splitKey]);
        end
    end

    -- Clear cached colors
    data.ClearColorCache();

    -- Update background themes for all primitives
    local bgTheme = gConfig.notificationsBackgroundTheme or 'Plain';
    local bgScale = gConfig.notificationsBgScale or 1.0;
    local borderScale = gConfig.notificationsBorderScale or 1.0;

    -- Update notification slot backgrounds
    if data.bgPrims then
        for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
            if data.bgPrims[i] then
                windowBg.setTheme(data.bgPrims[i], bgTheme, bgScale, borderScale);
            end
        end
    end

    -- Update split window backgrounds
    if data.splitBgPrims then
        for _, splitKey in ipairs(data.SPLIT_WINDOW_KEYS) do
            if data.splitBgPrims[splitKey] then
                windowBg.setTheme(data.splitBgPrims[splitKey], bgTheme, bgScale, borderScale);
            end
        end
    end

    -- Update display module
    display.UpdateVisuals(settings);
end

-- ============================================
-- DrawWindow
-- ============================================
notifications.DrawWindow = function(settings)
    local currentTime = os.clock();

    -- Update notification state (handle expiration, animations)
    data.Update(currentTime, settings);

    -- Render notification windows
    display.DrawWindow(settings, data.activeNotifications, data.pinnedNotifications);
end

-- ============================================
-- SetHidden
-- ============================================
notifications.SetHidden = function(hidden)
    -- Delegate to display module which has all hide calls
    display.SetHidden(hidden);
end

-- ============================================
-- Cleanup
-- ============================================
notifications.Cleanup = function()
    -- Cleanup fonts
    if data.titleFonts then
        for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
            if data.titleFonts[i] then
                data.titleFonts[i] = FontManager.destroy(data.titleFonts[i]);
            end
        end
        data.titleFonts = {};
    end

    if data.subtitleFonts then
        for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
            if data.subtitleFonts[i] then
                data.subtitleFonts[i] = FontManager.destroy(data.subtitleFonts[i]);
            end
        end
        data.subtitleFonts = {};
    end

    data.allFonts = {};

    -- Cleanup background primitives
    if data.bgPrims then
        for i = 1, data.MAX_ACTIVE_NOTIFICATIONS do
            if data.bgPrims[i] then
                windowBg.destroy(data.bgPrims[i]);
            end
        end
        data.bgPrims = {};
    end

    -- Cleanup split window placeholder fonts
    if data.splitTitleFonts then
        for splitKey, font in pairs(data.splitTitleFonts) do
            if font then
                FontManager.destroy(font);
            end
        end
        data.splitTitleFonts = {};
    end

    if data.splitSubtitleFonts then
        for splitKey, font in pairs(data.splitSubtitleFonts) do
            if font then
                FontManager.destroy(font);
            end
        end
        data.splitSubtitleFonts = {};
    end

    -- Cleanup split window placeholder primitives
    if data.splitBgPrims then
        for splitKey, prim in pairs(data.splitBgPrims) do
            if prim then
                windowBg.destroy(prim);
            end
        end
        data.splitBgPrims = {};
    end

    -- Clear cached colors
    data.ClearColorCache();

    -- Cleanup display resources (icons)
    display.Cleanup();

    -- Cleanup data module (clear notification state)
    data.Cleanup();
end

-- ============================================
-- Packet Handler Exports
-- ============================================
-- These are called from XIUI.lua packet_in handler
notifications.HandlePartyInvite = handler.HandlePartyInvite;
notifications.HandlePartyInviteResponse = handler.HandlePartyInviteResponse;
notifications.HandleTradeRequest = handler.HandleTradeRequest;
notifications.HandleTradeResponse = handler.HandleTradeResponse;
notifications.HandleMessagePacket = handler.HandleMessagePacket;
notifications.HandleActionPacket = handler.HandleActionPacket;
notifications.HandleInventoryUpdate = handler.HandleInventoryUpdate;
notifications.HandleTreasurePool = handler.HandleTreasurePool;
notifications.HandleTreasureLot = handler.HandleTreasureLot;
notifications.HandleZonePacket = handler.HandleZonePacket;
notifications.ClearTreasureState = handler.ClearTreasureState;
-- Wrap ClearTreasurePool to also disable test mode
function notifications.ClearTreasurePool()
    data.ClearTreasurePool();
    handler.testModeEnabled = false;
end
notifications.SyncTreasurePoolFromMemory = handler.SyncTreasurePoolFromMemory;
notifications.CheckPendingPoolNotifications = handler.CheckPendingPoolNotifications;

-- Test mode control (disables memory sync to allow test items to persist)
function notifications.SetTestMode(enabled)
    handler.testModeEnabled = enabled;
end

-- Export AddTreasurePoolNotification for treasure pool module to trigger toast notifications
notifications.AddTreasurePoolNotification = data.AddTreasurePoolNotification;

-- ============================================
-- Test Helper (for development)
-- ============================================
function notifications.TestNotification(type, testData)
    data.Add(type, testData or {});
end

-- Test treasure pool with multiple items (fills all 10 slots)
-- Uses common consumable item IDs that definitely have valid icons
function notifications.TestTreasurePool10()
    -- Enable test mode to prevent memory sync from removing test items
    handler.testModeEnabled = true;

    -- Clear existing pool first
    data.ClearTreasurePool();

    -- Test item IDs (common consumables - guaranteed to have valid icons)
    local testItems = {
        {id = 4096, name = 'Hi-Potion'},           -- slot 0
        {id = 4097, name = 'Hi-Potion +1'},        -- slot 1
        {id = 4098, name = 'Hi-Potion +2'},        -- slot 2
        {id = 4099, name = 'Hi-Potion +3'},        -- slot 3
        {id = 4112, name = 'Ether'},               -- slot 4
        {id = 4113, name = 'Ether +1'},            -- slot 5
        {id = 4114, name = 'Ether +2'},            -- slot 6
        {id = 4115, name = 'Ether +3'},            -- slot 7
        {id = 4116, name = 'Hi-Ether'},            -- slot 8
        {id = 4117, name = 'Hi-Ether +1'},         -- slot 9
    };

    -- Add all 10 items to treasure pool (with toast notifications)
    for slot = 0, 9 do
        local item = testItems[slot + 1];
        data.AddTreasurePoolItem(slot, item.id, 0, 1, 0, true);
    end

    print('[XIUI] Added 10 test items to treasure pool (test mode enabled)');
end

-- Test treasure pool ONLY (no toast notifications) - for crash isolation
function notifications.TestPoolOnly()
    -- Enable test mode to prevent memory sync from removing test items
    handler.testModeEnabled = true;

    data.ClearTreasurePool();
    for slot = 0, 9 do
        data.AddTreasurePoolItem(slot, 4096 + slot, 0, 1, 0, false);  -- false = no toast
    end
    print('[XIUI] Added 10 pool items (NO toasts, test mode enabled)');
end

-- Test toast notifications ONLY (no treasure pool) - for crash isolation
function notifications.TestToastsOnly()
    for i = 1, 10 do
        data.Add(data.NOTIFICATION_TYPE.ITEM_OBTAINED, {
            itemId = 4096 + i - 1,
            itemName = 'Test Item ' .. i,
            quantity = 1,
        });
    end
    print('[XIUI] Added 10 toast notifications (NO pool items)');
end

-- Stress test: attempt to add 25 items (tests bounds checking - only 0-9 are valid)
function notifications.TestTreasurePool25()
    -- Enable test mode to prevent memory sync from removing test items
    handler.testModeEnabled = true;

    -- Clear existing pool first
    data.ClearTreasurePool();

    -- Test item IDs (25 consumable items - only first 10 should be accepted)
    local testItems = {
        4096,   -- Hi-Potion
        4097,   -- Hi-Potion +1
        4098,   -- Hi-Potion +2
        4099,   -- Hi-Potion +3
        4112,   -- Ether
        4113,   -- Ether +1
        4114,   -- Ether +2
        4115,   -- Ether +3
        4116,   -- Hi-Ether
        4117,   -- Hi-Ether +1
        4118,   -- Hi-Ether +2 (slot 10 - should be rejected)
        4119,   -- Hi-Ether +3
        4120,   -- Super Ether
        4121,   -- Super Ether +1
        4122,   -- Super Ether +2
        4123,   -- Super Ether +3
        4128,   -- X-Potion
        4129,   -- X-Potion +1
        4130,   -- X-Potion +2
        4131,   -- X-Potion +3
        4144,   -- Pro-Ether
        4145,   -- Pro-Ether +1
        4146,   -- Pro-Ether +2
        4147,   -- Pro-Ether +3
        4148,   -- Elixir
    };

    -- Attempt to add 25 items (slots 10+ should be silently rejected by bounds check)
    local added = 0;
    for slot = 0, 24 do
        local itemId = testItems[slot + 1];
        -- Note: slots 10+ will be rejected by the bounds check in data.lua
        if slot < data.TREASURE_POOL_MAX_SLOTS then
            data.AddTreasurePoolItem(slot, itemId, 0, 1, 0, true);
            added = added + 1;
        end
    end

    print(string.format('[XIUI] Stress test: attempted 25 items, added %d (max slots: %d, test mode enabled)', added, data.TREASURE_POOL_MAX_SLOTS));
end

-- Clear test pool and disable test mode (returns to normal memory sync)
function notifications.ClearTestPool()
    data.ClearTreasurePool();
    handler.testModeEnabled = false;
    print('[XIUI] Cleared treasure pool and disabled test mode');
end

return notifications;
