--[[
* XIUI Notifications - Data Module
* Manages notification queue, state, and lifecycle
]]--

require('common');
local windowBg = require('libs.windowbackground');

local M = {};

-- ============================================
-- Constants
-- ============================================

-- Notification Types
M.NOTIFICATION_TYPE = {
    PARTY_INVITE = 1,
    TRADE_INVITE = 2,
    TREASURE_POOL = 3,
    TREASURE_LOT = 4,
    ITEM_OBTAINED = 5,
    KEY_ITEM_OBTAINED = 6,
    GIL_OBTAINED = 7,
};

-- Notification States
M.STATE = {
    ENTERING = 'entering',
    VISIBLE = 'visible',
    MINIFYING = 'minifying',
    MINIFIED = 'minified',
    EXITING = 'exiting',
    COMPLETE = 'complete',
};

-- Animation Durations (seconds)
M.DURATION = {
    ENTER = 0.4,      -- Slide in animation (matches exit)
    MINIFY = 0.4,     -- Shrink to minimized (longer for smooth transition)
    EXIT = 0.4,       -- Fade out
};

-- Queue Limits
M.MAX_ACTIVE_NOTIFICATIONS = 10;       -- Max active notifications on screen
M.MAX_PINNED_NOTIFICATIONS = 3;        -- Max minimized invites

-- Treasure Pool Constants
M.TREASURE_POOL_TIMEOUT = 300;         -- 5 minutes in seconds
M.TREASURE_POOL_MAX_SLOTS = 10;        -- Max items in treasure pool

-- Split Window Type Mapping
M.TYPE_TO_SPLIT_KEY = {
    [1] = 'PartyInvite',      -- PARTY_INVITE
    [2] = 'TradeInvite',      -- TRADE_INVITE
    [3] = 'TreasurePool',     -- TREASURE_POOL
    [4] = 'TreasurePool',     -- TREASURE_LOT (same window as pool)
    [5] = 'ItemObtained',     -- ITEM_OBTAINED
    [6] = 'KeyItemObtained',  -- KEY_ITEM_OBTAINED
    [7] = 'GilObtained',      -- GIL_OBTAINED
};

-- All unique split window keys (for font creation)
M.SPLIT_WINDOW_KEYS = {
    'PartyInvite',
    'TradeInvite',
    'TreasurePool',
    'ItemObtained',
    'KeyItemObtained',
    'GilObtained',
};

-- ============================================
-- State Variables
-- ============================================

-- Notification Queues
M.activeNotifications = {};     -- Currently displayed notifications
M.pinnedNotifications = {};     -- Minimized invite notifications
M.pendingQueue = {};            -- Waiting to display

-- Treasure Pool State (persistent tracking, separate from transient notifications)
-- Hash table: slot (0-9) -> pool item data
M.treasurePool = {};

-- ID Counter
M.nextId = 1;

-- Settings Cache
M.settings = nil;

-- ============================================
-- Font Objects (following petbar pattern)
-- ============================================

-- Font arrays indexed by slot (1 to MAX_ACTIVE_NOTIFICATIONS)
M.titleFonts = {};
M.subtitleFonts = {};
M.allFonts = {};

-- Split window placeholder fonts (indexed by split key)
M.splitTitleFonts = {};     -- splitKey -> font
M.splitSubtitleFonts = {};  -- splitKey -> font

-- Treasure pool window fonts (indexed by slot 0-9)
M.poolHeaderFont = nil;     -- Header font for "Treasure Pool" title
M.poolItemNameFonts = {};   -- slot -> font (item name)
M.poolTimerFonts = {};      -- slot -> font (countdown timer)
M.poolLotFonts = {};        -- slot -> font (lot info)

-- Treasure pool background primitives (indexed by slot 0-9)
M.poolBgPrims = {};

-- Cached colors to avoid expensive set_font_color calls
M.lastTitleColors = {};
M.lastSubtitleColors = {};

-- ============================================
-- Primitive Storage (following petbar pattern)
-- ============================================

-- Background primitives for each notification slot
M.bgPrims = {};  -- indexed by slot number

-- Split window placeholder primitives (indexed by split key)
M.splitBgPrims = {};  -- splitKey -> primitive

-- ============================================
-- Font/Primitive Helpers
-- ============================================

-- Set all fonts visible/hidden
function M.SetAllFontsVisible(visible)
    if M.allFonts then
        SetFontsVisible(M.allFonts, visible);
    end
end

-- Hide all background primitives (including pool backgrounds)
function M.HideAllBackgrounds()
    -- Hide notification backgrounds
    if M.bgPrims then
        for i = 1, M.MAX_ACTIVE_NOTIFICATIONS do
            if M.bgPrims[i] then
                windowBg.hide(M.bgPrims[i]);
            end
        end
    end
    -- Hide split window backgrounds
    if M.splitBgPrims then
        for _, handle in pairs(M.splitBgPrims) do
            if handle then
                windowBg.hide(handle);
            end
        end
    end
    -- Hide treasure pool backgrounds
    if M.poolBgPrims then
        for _, handle in pairs(M.poolBgPrims) do
            if handle then
                windowBg.hide(handle);
            end
        end
    end
end

-- Hide split window placeholder fonts
function M.HideSplitFonts()
    if M.splitTitleFonts then
        for _, font in pairs(M.splitTitleFonts) do
            if font then
                font:set_visible(false);
            end
        end
    end
    if M.splitSubtitleFonts then
        for _, font in pairs(M.splitSubtitleFonts) do
            if font then
                font:set_visible(false);
            end
        end
    end
end

-- Hide treasure pool window fonts
function M.HidePoolFonts()
    if M.poolHeaderFont then
        M.poolHeaderFont:set_visible(false);
    end
    if M.poolItemNameFonts then
        for _, font in pairs(M.poolItemNameFonts) do
            if font then
                font:set_visible(false);
            end
        end
    end
    if M.poolTimerFonts then
        for _, font in pairs(M.poolTimerFonts) do
            if font then
                font:set_visible(false);
            end
        end
    end
    if M.poolLotFonts then
        for _, font in pairs(M.poolLotFonts) do
            if font then
                font:set_visible(false);
            end
        end
    end
end

-- Hide treasure pool background primitives
function M.HidePoolBackgrounds()
    if M.poolBgPrims then
        for _, handle in pairs(M.poolBgPrims) do
            if handle then
                windowBg.hide(handle);
            end
        end
    end
end

-- Clear cached colors
function M.ClearColorCache()
    M.lastTitleColors = {};
    M.lastSubtitleColors = {};
end

-- ============================================
-- Window Flags (following petbar pattern)
-- ============================================

-- Cached window flags
local baseWindowFlags = nil;

-- Get cached base window flags
function M.getBaseWindowFlags()
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
    return baseWindowFlags;
end

-- ============================================
-- Helper Functions
-- ============================================

-- Check if a notification type is persistent (invites)
function M.IsPersistentType(notificationType)
    return notificationType == M.NOTIFICATION_TYPE.PARTY_INVITE
        or notificationType == M.NOTIFICATION_TYPE.TRADE_INVITE;
end

-- Check if a notification is fully minified (not during animation)
function M.IsMinified(notification)
    return notification.isMinified == true
        or notification.state == M.STATE.MINIFIED;
end

-- Check if notification is in minifying transition
function M.IsMinifying(notification)
    return notification.state == M.STATE.MINIFYING;
end

-- Get minify progress (0 = normal, 1 = fully minified)
function M.GetMinifyProgress(notification)
    return notification.minifyProgress or 0;
end

-- Get display duration for notification type (from settings)
function M.GetDurationForType(notificationType, settings)
    -- Get the user-configured display duration from gConfig
    local displayDuration = gConfig and gConfig.notificationsDisplayDuration or 3.0;

    if notificationType == M.NOTIFICATION_TYPE.PARTY_INVITE then
        return 999999;  -- Persistent until action
    elseif notificationType == M.NOTIFICATION_TYPE.TRADE_INVITE then
        return 999999;  -- Persistent until action
    end

    -- All other notification types use the configured display duration
    return displayDuration;
end

-- Get max active notifications from config (capped at hard limit)
local function GetMaxActiveNotifications()
    local configMax = gConfig and gConfig.notificationsMaxVisible or 5;
    return math.min(configMax, M.MAX_ACTIVE_NOTIFICATIONS);
end

-- Create a new notification object
local function CreateNotification(notificationType, data)
    local currentTime = os.clock();
    local duration = M.GetDurationForType(notificationType, M.settings);

    return {
        id = M.nextId,
        type = notificationType,
        createdAt = currentTime,
        displayDuration = duration,
        state = M.STATE.ENTERING,
        stateStartTime = currentTime,
        animationProgress = 0,
        alpha = 0,
        containerOffsetX = -50,  -- Container slides in from left
        iconOffsetX = -20,       -- Icon slides in from left (relative to container)
        textOffsetY = 8,         -- Text slides up from below
        data = data or {},
    };
end

-- Move notification from pending queue to active
local function ActivatePendingNotification()
    if #M.pendingQueue == 0 then return; end

    local maxActive = GetMaxActiveNotifications();
    if #M.activeNotifications >= maxActive then return; end

    local notification = table.remove(M.pendingQueue, 1);
    table.insert(M.activeNotifications, notification);
end

-- Update notification state based on time
local function UpdateNotificationState(notification, currentTime)
    local stateElapsed = currentTime - notification.stateStartTime;

    if notification.state == M.STATE.ENTERING then
        -- Entering animation (fade in + slide from left)
        notification.animationProgress = math.min(1.0, stateElapsed / M.DURATION.ENTER);

        -- Ease out cubic for smooth deceleration
        local t = notification.animationProgress;
        local eased = 1 - math.pow(1 - t, 3);

        notification.alpha = eased;
        notification.containerOffsetX = -50 * (1 - eased);  -- Container slides in from left
        notification.iconOffsetX = -20 * (1 - eased);       -- Icon slides from left (relative)
        notification.textOffsetY = 8 * (1 - eased);         -- Text slides up into position

        if notification.animationProgress >= 1.0 then
            notification.state = M.STATE.VISIBLE;
            notification.stateStartTime = currentTime;
            notification.animationProgress = 0;
            notification.alpha = 1;
            notification.containerOffsetX = 0;
            notification.iconOffsetX = 0;
            notification.textOffsetY = 0;
        end

    elseif notification.state == M.STATE.VISIBLE then
        -- Visible state - check if duration expired (for non-persistent)
        local visibleDuration = currentTime - notification.stateStartTime;
        if M.IsPersistentType(notification.type) then
            -- Persistent types (invites) minify after timeout
            local minifyTimeout = gConfig and gConfig.notificationsInviteMinifyTimeout or 10.0;
            if visibleDuration >= minifyTimeout then
                notification.state = M.STATE.MINIFYING;
                notification.stateStartTime = currentTime;
                notification.animationProgress = 0;
            end
        else
            -- Non-persistent types exit after duration
            -- Add stagger delay based on notification index to prevent all exiting at once
            local staggerDelay = (notification.staggerIndex or 0) * 0.1;  -- 100ms between each
            if visibleDuration >= (notification.displayDuration + staggerDelay) then
                notification.state = M.STATE.EXITING;
                notification.stateStartTime = currentTime;
                notification.animationProgress = 0;
            end
        end

    elseif notification.state == M.STATE.MINIFYING then
        -- Minifying animation (shrink to compact view)
        notification.animationProgress = math.min(1.0, stateElapsed / M.DURATION.MINIFY);

        -- Ease out cubic for smooth deceleration
        local t = notification.animationProgress;
        local eased = 1 - math.pow(1 - t, 3);

        notification.alpha = 1.0;  -- Keep visible
        notification.minifyProgress = eased;  -- 0 = normal, 1 = fully minified

        if notification.animationProgress >= 1.0 then
            notification.state = M.STATE.MINIFIED;
            notification.stateStartTime = currentTime;
            notification.animationProgress = 0;
            notification.isMinified = true;
            notification.minifyProgress = 1.0;
        end

    elseif notification.state == M.STATE.MINIFIED then
        -- Minified state - stays in active queue until action
        notification.alpha = 1.0;
        notification.isMinified = true;
        notification.minifyProgress = 1.0;

    elseif notification.state == M.STATE.EXITING then
        -- Exiting animation (fade out + translate right)
        notification.animationProgress = math.min(1.0, stateElapsed / M.DURATION.EXIT);

        -- Ease in for exit
        local t = notification.animationProgress;
        local eased = t * t;  -- Ease in quad

        notification.alpha = 1.0 - eased;
        notification.containerOffsetX = 50 * eased;  -- Container slides out to right
        notification.iconOffsetX = 0;                -- Icon follows container (no separate translation)
        notification.textOffsetY = 8 * eased;        -- Text slides down

        if notification.animationProgress >= 1.0 then
            notification.state = M.STATE.COMPLETE;
            notification.alpha = 0;
        end
    end
end

-- Remove completed notifications from active queue
local function RemoveCompletedNotifications()
    -- Remove from active
    for i = #M.activeNotifications, 1, -1 do
        if M.activeNotifications[i].state == M.STATE.COMPLETE then
            table.remove(M.activeNotifications, i);
        end
    end

    -- Remove from pinned
    for i = #M.pinnedNotifications, 1, -1 do
        if M.pinnedNotifications[i].state == M.STATE.COMPLETE then
            table.remove(M.pinnedNotifications, i);
        end
    end
end

-- ============================================
-- Public API
-- ============================================

-- Initialize notification system
function M.Initialize(settings)
    M.settings = settings;
    M.activeNotifications = {};
    -- Note: Font/primitive objects are created in init.lua, not here
    -- We just reset the tables that init.lua will populate
    M.splitTitleFonts = {};
    M.splitSubtitleFonts = {};
    M.splitBgPrims = {};
    M.poolItemNameFonts = {};
    M.poolTimerFonts = {};
    M.poolLotFonts = {};
    M.pinnedNotifications = {};
    M.pendingQueue = {};
    M.treasurePool = {};
    M.nextId = 1;
end

-- Add a new notification
-- Returns: notification ID
-- Track stagger index for notifications added in quick succession
M.lastAddTime = 0;
M.currentStaggerIndex = 0;
M.STAGGER_RESET_DELAY = 0.5;  -- Reset stagger counter after 500ms of no adds

function M.Add(notificationType, data)
    local notification = CreateNotification(notificationType, data);
    M.nextId = M.nextId + 1;

    -- Assign stagger index for exit animation timing
    local currentTime = os.clock();
    if (currentTime - M.lastAddTime) > M.STAGGER_RESET_DELAY then
        M.currentStaggerIndex = 0;  -- Reset if it's been a while since last add
    end
    notification.staggerIndex = M.currentStaggerIndex;
    M.currentStaggerIndex = M.currentStaggerIndex + 1;
    M.lastAddTime = currentTime;

    -- Check for duplicate invites and remove existing
    if M.IsPersistentType(notificationType) then
        M.RemoveByType(notificationType, notification.id);
    end

    -- Add to active if space available, otherwise queue
    local maxActive = GetMaxActiveNotifications();
    if #M.activeNotifications < maxActive then
        table.insert(M.activeNotifications, notification);
    else
        table.insert(M.pendingQueue, notification);
    end

    return notification.id;
end

-- Mark notification for exit animation
function M.Remove(notificationId)
    -- Check active
    for _, notification in ipairs(M.activeNotifications) do
        if notification.id == notificationId then
            if notification.state ~= M.STATE.EXITING and notification.state ~= M.STATE.COMPLETE then
                notification.state = M.STATE.EXITING;
                notification.stateStartTime = os.clock();
                notification.animationProgress = 0;
            end
            return;
        end
    end

    -- Check pinned
    for _, notification in ipairs(M.pinnedNotifications) do
        if notification.id == notificationId then
            if notification.state ~= M.STATE.EXITING and notification.state ~= M.STATE.COMPLETE then
                notification.state = M.STATE.EXITING;
                notification.stateStartTime = os.clock();
                notification.animationProgress = 0;
            end
            return;
        end
    end

    -- Check pending (remove immediately)
    for i, notification in ipairs(M.pendingQueue) do
        if notification.id == notificationId then
            table.remove(M.pendingQueue, i);
            return;
        end
    end
end

-- Remove all notifications of a specific type
function M.RemoveByType(notificationType, excludeId)
    -- Remove from active
    for _, notification in ipairs(M.activeNotifications) do
        if notification.type == notificationType and notification.id ~= excludeId then
            if notification.state ~= M.STATE.EXITING and notification.state ~= M.STATE.COMPLETE then
                notification.state = M.STATE.EXITING;
                notification.stateStartTime = os.clock();
                notification.animationProgress = 0;
            end
        end
    end

    -- Remove from pinned
    for _, notification in ipairs(M.pinnedNotifications) do
        if notification.type == notificationType and notification.id ~= excludeId then
            if notification.state ~= M.STATE.EXITING and notification.state ~= M.STATE.COMPLETE then
                notification.state = M.STATE.EXITING;
                notification.stateStartTime = os.clock();
                notification.animationProgress = 0;
            end
        end
    end

    -- Remove from pending (immediate)
    for i = #M.pendingQueue, 1, -1 do
        if M.pendingQueue[i].type == notificationType and M.pendingQueue[i].id ~= excludeId then
            table.remove(M.pendingQueue, i);
        end
    end
end

-- Minimize notification (convert to pinned)
function M.Minimize(notificationId)
    -- Only persistent types can be minimized
    for _, notification in ipairs(M.activeNotifications) do
        if notification.id == notificationId then
            if M.IsPersistentType(notification.type) then
                if #M.pinnedNotifications >= M.MAX_PINNED_NOTIFICATIONS then
                    -- Remove oldest pinned to make room
                    if #M.pinnedNotifications > 0 then
                        M.Remove(M.pinnedNotifications[1].id);
                    end
                end

                notification.state = M.STATE.MINIFYING;
                notification.stateStartTime = os.clock();
                notification.animationProgress = 0;
            end
            return;
        end
    end
end

-- Restore pinned notification to active
function M.Restore(notificationId)
    for i, notification in ipairs(M.pinnedNotifications) do
        if notification.id == notificationId then
            -- Move back to active
            table.remove(M.pinnedNotifications, i);

            -- Reset to entering state
            notification.state = M.STATE.ENTERING;
            notification.stateStartTime = os.clock();
            notification.animationProgress = 0;

            -- Add to active if space, otherwise pending
            local maxActive = GetMaxActiveNotifications();
            if #M.activeNotifications < maxActive then
                table.insert(M.activeNotifications, notification);
            else
                table.insert(M.pendingQueue, notification);
            end
            return;
        end
    end
end

-- Update all notifications (call every frame)
function M.Update(currentTime, settings)
    M.settings = settings;

    -- Update active notifications
    for _, notification in ipairs(M.activeNotifications) do
        UpdateNotificationState(notification, currentTime);
    end

    -- Update pinned notifications
    for _, notification in ipairs(M.pinnedNotifications) do
        UpdateNotificationState(notification, currentTime);
    end

    -- Update pending notifications (just state tracking)
    for _, notification in ipairs(M.pendingQueue) do
        UpdateNotificationState(notification, currentTime);
    end

    -- Remove completed
    RemoveCompletedNotifications();

    -- Activate pending if space available
    ActivatePendingNotification();
end

-- Get notification by ID
function M.GetNotification(notificationId)
    -- Check active
    for _, notification in ipairs(M.activeNotifications) do
        if notification.id == notificationId then
            return notification;
        end
    end

    -- Check pinned
    for _, notification in ipairs(M.pinnedNotifications) do
        if notification.id == notificationId then
            return notification;
        end
    end

    -- Check pending
    for _, notification in ipairs(M.pendingQueue) do
        if notification.id == notificationId then
            return notification;
        end
    end

    return nil;
end

-- Clear all notifications
function M.Cleanup()
    M.activeNotifications = {};
    M.pinnedNotifications = {};
    M.pendingQueue = {};
    M.treasurePool = {};
    M.settings = nil;
    -- Note: Font/primitive objects are destroyed in init.lua Cleanup
    -- We just clear the references here
    M.splitTitleFonts = {};
    M.splitSubtitleFonts = {};
    M.splitBgPrims = {};
    M.poolItemNameFonts = {};
    M.poolTimerFonts = {};
    M.poolLotFonts = {};
end

-- ============================================
-- Convenience Functions for Handlers
-- ============================================

-- Helper to get item name from resource manager
-- Note: Invalid item IDs include nil, 0, -1, and 65535 (0xFFFF)
local function getItemName(itemId)
    -- Check for invalid item IDs (matches equipmon pattern)
    if itemId == nil or itemId == 0 or itemId == -1 or itemId == 65535 then
        return 'Unknown Item';
    end
    local item = AshitaCore:GetResourceManager():GetItemById(itemId);
    if item and item.Name and item.Name[1] then
        local name = item.Name[1];
        -- Sometimes the name can be empty string
        if name ~= nil and name ~= '' then
            return name;
        end
    end
    return 'Unknown Item';
end

-- Helper to get key item name
-- Note: Similar validation to items
local function getKeyItemName(keyItemId)
    if keyItemId == nil or keyItemId == 0 or keyItemId == -1 or keyItemId == 65535 then
        return 'Unknown Key Item';
    end
    local keyItem = AshitaCore:GetResourceManager():GetKeyItemById(keyItemId);
    if keyItem and keyItem.Name and keyItem.Name[1] then
        local name = keyItem.Name[1];
        if name ~= nil and name ~= '' then
            return name;
        end
    end
    return 'Unknown Key Item';
end

-- Add party invite notification
function M.AddPartyInviteNotification(playerName, playerId)
    return M.Add(M.NOTIFICATION_TYPE.PARTY_INVITE, {
        playerName = playerName or 'Unknown',
        playerId = playerId,
    });
end

-- Add trade request notification
function M.AddTradeRequestNotification(playerName, playerId)
    return M.Add(M.NOTIFICATION_TYPE.TRADE_INVITE, {
        playerName = playerName or 'Unknown',
        playerId = playerId,
    });
end

-- Add item obtained notification
function M.AddItemObtainedNotification(itemId, quantity)
    return M.Add(M.NOTIFICATION_TYPE.ITEM_OBTAINED, {
        itemId = itemId,
        itemName = getItemName(itemId),
        quantity = quantity or 1,
    });
end

-- Add key item obtained notification
function M.AddKeyItemObtainedNotification(keyItemId)
    return M.Add(M.NOTIFICATION_TYPE.KEY_ITEM_OBTAINED, {
        itemId = keyItemId,
        itemName = getKeyItemName(keyItemId),
    });
end

-- Add gil obtained notification
function M.AddGilObtainedNotification(amount)
    return M.Add(M.NOTIFICATION_TYPE.GIL_OBTAINED, {
        amount = amount or 0,
    });
end

-- Add treasure pool notification (toast)
function M.AddTreasurePoolNotification(itemId, quantity)
    return M.Add(M.NOTIFICATION_TYPE.TREASURE_POOL, {
        itemId = itemId,
        itemName = getItemName(itemId),
        quantity = quantity or 1,
    });
end

-- ============================================
-- Treasure Pool State Management
-- ============================================

-- Add item to treasure pool state
-- showToast: if false, skip the toast notification (e.g., for items that existed before tracking)
function M.AddTreasurePoolItem(slot, itemId, dropperId, count, timestamp, showToast)
    local itemName = getItemName(itemId);
    local currentTime = os.time();

    -- Calculate expiration (5 minutes from now)
    local expiresAt = currentTime + M.TREASURE_POOL_TIMEOUT;

    M.treasurePool[slot] = {
        slot = slot,
        itemId = itemId,
        itemName = itemName,
        dropperId = dropperId,
        count = count or 1,
        timestamp = timestamp,
        expiresAt = expiresAt,
        lots = {},              -- Hash table: playerId -> {name, lot}
        highestLot = 0,
        highestLotterName = "",
        highestLotterId = 0,
        awarded = false,
        awardedTo = nil,
        addedAt = currentTime,  -- For display animation
        exitStartTime = nil,    -- For exit animation
    };

    -- Also add a toast notification if enabled (and showToast is not false)
    if showToast ~= false and gConfig and gConfig.notificationsShowTreasure then
        M.AddTreasurePoolNotification(itemId, count);
    end
end

-- Update lot information for treasure pool item
function M.UpdateTreasurePoolLot(slot, lotterId, lotterName, lotValue, highestId, highestName, highestLot, dropStatus)
    local item = M.treasurePool[slot];
    if not item then return end

    -- Update current lotter info (hash table for O(1) lookup)
    if lotterId and lotterId ~= 0 and lotValue and lotValue > 0 then
        item.lots[lotterId] = {
            name = lotterName or "Unknown",
            lot = lotValue,
        };
    end

    -- Update highest lot info
    if highestLot and highestLot > 0 then
        item.highestLot = highestLot;
        item.highestLotterName = highestName or item.highestLotterName;
        item.highestLotterId = highestId or item.highestLotterId;
    end

    -- Handle drop status - clear immediately on award or loss
    if dropStatus == 1 then  -- Awarded - clear immediately
        M.treasurePool[slot] = nil;
    elseif dropStatus == 2 then  -- Lost/Passed by all
        M.treasurePool[slot] = nil;
    end
end

-- Update treasure pool state (call every frame from display)
function M.UpdateTreasurePool(currentTime)
    local osTime = os.time();
    local clockTime = os.clock();

    for slot, item in pairs(M.treasurePool) do
        -- Check expiration
        if osTime >= item.expiresAt then
            M.treasurePool[slot] = nil;
        -- Handle awarded item removal after exit animation
        elseif item.exitStartTime and (clockTime - item.exitStartTime) > M.DURATION.EXIT then
            M.treasurePool[slot] = nil;
        end
    end
end

-- Get time remaining for pool item (in seconds)
function M.GetTreasurePoolTimeRemaining(slot)
    local item = M.treasurePool[slot];
    if not item then return 0 end

    local remaining = item.expiresAt - os.time();
    return math.max(0, remaining);
end

-- Format time as M:SS
function M.FormatPoolTimer(seconds)
    local mins = math.floor(seconds / 60);
    local secs = seconds % 60;
    return string.format("%d:%02d", mins, secs);
end

-- Get sorted treasure pool items for display
function M.GetSortedTreasurePool()
    local sorted = {};
    for slot, item in pairs(M.treasurePool) do
        table.insert(sorted, item);
    end
    -- Sort by slot index
    table.sort(sorted, function(a, b) return a.slot < b.slot end);
    return sorted;
end

-- Get treasure pool item count
function M.GetTreasurePoolCount()
    local count = 0;
    for _ in pairs(M.treasurePool) do
        count = count + 1;
    end
    return count;
end

-- Clear treasure pool (call on zone change)
function M.ClearTreasurePool()
    M.treasurePool = {};
end

-- ============================================
-- Split Window Helpers
-- ============================================

-- Check if split window is enabled for a notification type
function M.IsSplitWindowEnabled(notificationType)
    local splitKey = M.TYPE_TO_SPLIT_KEY[notificationType];
    if not splitKey then return false end

    local configKey = 'notificationsSplit' .. splitKey;
    return gConfig and gConfig[configKey] == true;
end

-- Get notifications filtered by type (for split windows)
function M.GetNotificationsByType(notificationType)
    local result = {};
    for _, notification in ipairs(M.activeNotifications) do
        if notification.type == notificationType then
            table.insert(result, notification);
        end
    end
    return result;
end

-- Get notifications NOT in split windows (for main window)
function M.GetNonSplitNotifications()
    local result = {};
    for _, notification in ipairs(M.activeNotifications) do
        if not M.IsSplitWindowEnabled(notification.type) then
            table.insert(result, notification);
        end
    end
    return result;
end

-- Get all enabled split window keys
function M.GetEnabledSplitKeys()
    local keys = {};
    local seen = {};
    for typeId, splitKey in pairs(M.TYPE_TO_SPLIT_KEY) do
        if not seen[splitKey] then
            local configKey = 'notificationsSplit' .. splitKey;
            if gConfig and gConfig[configKey] == true then
                table.insert(keys, splitKey);
                seen[splitKey] = true;
            end
        end
    end
    return keys;
end

-- Get notification type(s) for a split key
function M.GetTypesForSplitKey(splitKey)
    local types = {};
    for typeId, key in pairs(M.TYPE_TO_SPLIT_KEY) do
        if key == splitKey then
            table.insert(types, typeId);
        end
    end
    return types;
end

return M;
