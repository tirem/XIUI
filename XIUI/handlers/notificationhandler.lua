--[[
* XIUI Notification Handler
* Handles packet parsing for notifications (party invites, trade requests, item/gil obtained, treasure pool)
* Follows patterns from debuffhandler.lua for O(1) hash table lookups
]]--

require('common');
local struct = require('struct');

local M = {};

-- ========================================
-- Zoning/Load State Tracking
-- ========================================

-- Track zoning/load state to ignore inventory sync packets
-- Initialize to current time so grace period is active on addon load
M.zoningTimestamp = os.clock();
M.ZONING_GRACE_PERIOD = 5.0;  -- Ignore inventory updates for 5 seconds after zoning/load

-- Called when zone packet is received OR on addon load
function M.HandleZonePacket()
    M.zoningTimestamp = os.clock();

    -- Clear party invite notifications (invites are invalid after zoning)
    if M.dataModule and M.dataModule.RemoveByType and M.dataModule.NOTIFICATION_TYPE then
        M.dataModule.RemoveByType(M.dataModule.NOTIFICATION_TYPE.PARTY_INVITE);
    end

    -- Clear toast tracking so items in new zone get fresh toasts
    M.ClearToastTracking();
end

-- Check if we're in the zoning/load grace period (for inventory packets only)
local function isInZoningGracePeriod()
    return (os.clock() - M.zoningTimestamp) < M.ZONING_GRACE_PERIOD;
end

-- ========================================
-- Treasure Pool Memory Sync (xitools approach)
-- ========================================

-- Track pending pool notifications by slot
-- Maps slot -> {itemId, count, timestamp}
-- Used to determine if item stays in pool (needs "Treasure Pool" notification)
-- or gets immediately awarded (only needs "Item Obtained" notification)
local pendingPoolNotifications = {};

-- Short delay to wait for 0x00D3 before showing "Treasure Pool" notification
-- If 0x00D3 arrives within this time, item was auto-awarded (show only "Item Obtained")
-- If not, item is staying in pool (show "Treasure Pool")
local POOL_NOTIFICATION_DELAY = 0.2;  -- 200ms - enough for packets to arrive

-- Test mode flag - when true, don't remove items not in memory (for UI testing)
M.testModeEnabled = false;

-- Timestamp cache for expiration times
local timestampCache = {};

-- ========================================
-- Treasure Pool Memory Sync (UI only)
-- ========================================

-- Sync treasure pool state from Ashita memory API for UI display.
-- This does NOT create notifications - that's handled by packet handlers
function M.SyncTreasurePoolFromMemory()
    if M.dataModule == nil then return end

    local memMgr = AshitaCore:GetMemoryManager();
    if not memMgr then return end

    local inventory = memMgr:GetInventory();
    if not inventory then return end

    local now = os.time();
    local activeSlots = {};

    -- Iterate all 10 treasure pool slots
    for slot = 0, 9 do
        local item = inventory:GetTreasurePoolItem(slot);

        if item ~= nil and item.ItemId ~= nil and item.ItemId > 0 then
            activeSlots[slot] = true;

            -- Check if we already have this item tracked
            local existingItem = M.dataModule.treasurePool and M.dataModule.treasurePool[slot];
            local isNewItem = not existingItem or existingItem.itemId ~= item.ItemId;

            if isNewItem then
                -- Cache expiration time
                if not timestampCache[item.DropTime] then
                    timestampCache[item.DropTime] = now + 300;
                end

                -- Add to treasure pool tracking (UI only, no notification)
                if M.dataModule.AddTreasurePoolItem then
                    M.dataModule.AddTreasurePoolItem(slot, item.ItemId, 0, 1, item.DropTime, false);
                end
            end

            -- Update lot information from memory
            if M.dataModule.treasurePool and M.dataModule.treasurePool[slot] then
                local poolItem = M.dataModule.treasurePool[slot];

                if item.WinningLot and item.WinningLot > 0 then
                    poolItem.highestLot = item.WinningLot;
                    poolItem.highestLotterName = item.WinningEntityName or poolItem.highestLotterName;
                end

                poolItem.playerLot = item.Lot;

                if timestampCache[item.DropTime] then
                    poolItem.expiresAt = timestampCache[item.DropTime];
                end
            end
        end
    end

    -- Remove items from tracking that are no longer in memory
    -- Skip this in test mode to allow test items to persist
    if not M.testModeEnabled and M.dataModule.treasurePool then
        for slot, poolItem in pairs(M.dataModule.treasurePool) do
            if not activeSlots[slot] then
                M.dataModule.treasurePool[slot] = nil;
                M.dataModule.MarkPoolDirty();

                if M.DEBUG_ENABLED then
                    print(string.format('[XIUI] POOL REMOVE: slot=%d', slot));
                end
            end
        end
    end
end

-- Clear tracking (call on zone change)
function M.ClearToastTracking()
    pendingPoolNotifications = {};
    timestampCache = {};
end

-- ========================================
-- Pending Pool Notification Check
-- ========================================

-- Check pending items and create "Treasure Pool" notifications for items
-- that have been in pool longer than POOL_NOTIFICATION_DELAY (not auto-awarded)
-- Call this from render loop
function M.CheckPendingPoolNotifications()
    if M.dataModule == nil then return end
    if not gConfig.notificationsShowTreasure then return end

    local now = os.clock();

    for slot, pending in pairs(pendingPoolNotifications) do
        if pending.timestamp and not pending.notified then
            local age = now - pending.timestamp;
            if age >= POOL_NOTIFICATION_DELAY then
                -- Item has been in pool long enough without 0x00D3 award
                -- This means it's genuinely staying in pool (party or full inventory)
                pending.notified = true;
                if M.dataModule.AddTreasurePoolNotification then
                    M.dataModule.AddTreasurePoolNotification(pending.itemId, pending.count or 1);
                    if M.DEBUG_ENABLED then
                        print(string.format('[XIUI] Pending: Created Treasure Pool notification after %.1fs', age));
                    end
                end
            end
        end
    end
end

-- ========================================
-- Message Type Lookup Tables (O(1) lookup)
-- ========================================

-- Debug flag - set to true to see message IDs and item IDs in log
M.DEBUG_ENABLED = false;

-- Item obtained message IDs (for MESSAGE packets 0x0029/0x002D only)
-- Reference: FFXI message packet (0x029) message types
-- Note: param field contains item ID, value field contains quantity
-- Important: Message 6 is a DEATH message, not item obtained!
-- Note: Steal/Despoil (125, 593-599) are handled via ACTION packets, not here
local itemObtainedMes = {
    -- Note: Message ID 9 is "<actor> attains level <number>!" (level up), NOT item obtained
    [65] = true,    -- You find [item] on the [mob]
    [69] = true,    -- [Player] finds [item] on the [mob]
    [98] = true,    -- You obtain an [item] from [target]
    [145] = true,   -- You obtain [item] from the [container]
    [149] = true,   -- [Player] obtains [item] from the [container]
    [376] = true,   -- [actor] uses [ability]. [target] obtains [item]
    [600] = true,   -- [actor] eats an [item]. [actor] finds an [item] inside!
};

-- Key item obtained message IDs
local keyItemObtainedMes = {
    [658] = true,   -- You obtain the key item [item]
    [659] = true,   -- [Player] obtains the key item [item]
};

-- Gil obtained message IDs (for MESSAGE packets 0x0029/0x002D only)
-- Note: param field contains gil amount
-- Note: Mug (129) is handled via ACTION packets, not here
local gilObtainedMes = {
    [8] = true,     -- You obtain [amount] gil
    [10] = true,    -- [Player] obtains [amount] gil
    [11] = true,    -- You find [amount] gil on the [mob]
    [127] = true,   -- You find [amount] gil on the [target] (additional mob drop)
    [131] = true,   -- [Player] finds [amount] gil on the [target]
    [144] = true,   -- You obtain [amount] gil from the [container]
    [148] = true,   -- [Player] obtains [amount] gil from the [container]
    [565] = true,   -- [target] obtains [gil]
    [582] = true,   -- [actor] obtains [gil]
};

-- ========================================
-- Data Module Reference
-- ========================================

-- Will be set by modules/notifications/init.lua
M.dataModule = nil;

function M.SetDataModule(dataModule)
    M.dataModule = dataModule;
end

-- ========================================
-- Helper Functions
-- ========================================

-- Get entity name from server ID
local function getEntityName(serverId)
    local index = GetIndexFromId(serverId);
    if index and index > 0 then
        local entity = GetEntity(index);
        if entity then
            return entity.Name;
        end
    end
    return "Unknown";
end

-- Trim null bytes from a fixed-length string
local function trimNullString(str)
    if str == nil then return "" end
    local nullPos = str:find('\0');
    if nullPos then
        return str:sub(1, nullPos - 1);
    end
    return str;
end

-- ========================================
-- Packet Handlers
-- ========================================

-- Handle party invite packet (0x00DC)
-- Structure: Party invite from another player
function M.HandlePartyInvite(e)
    if M.dataModule == nil then return end

    -- Parse packet data
    -- Offset 0x04: Unknown (index or flags)
    -- Offset 0x08: Unknown (flags)
    -- Offset 0x0C: Inviter name (16 bytes, null-terminated string)
    local inviterName = e.data:sub(0x0C + 1, 0x0C + 16);
    inviterName = inviterName:match("^[^%z]+") or "";  -- Trim at first null byte

    -- Debug output
    if M.DEBUG_ENABLED then
        print(string.format('[XIUI] 0x00DC PARTY_INVITE: name=[%s]', inviterName));
    end

    -- Validate - need a name
    if inviterName == nil or inviterName == '' then
        inviterName = 'Unknown';
    end

    -- Add notification via data module
    if M.dataModule.AddPartyInviteNotification then
        M.dataModule.AddPartyInviteNotification(inviterName, nil);
    end
end

-- Handle party invite response (outgoing packet 0x0074)
-- Called when player accepts or declines a party invite
function M.HandlePartyInviteResponse(e)
    if M.dataModule == nil then return end

    -- Debug output
    if M.DEBUG_ENABLED then
        print('[XIUI] 0x0074 PARTY_INVITE_RESPONSE: Removing party invite notification');
    end

    -- Remove party invite notification when player responds
    if M.dataModule.RemoveByType and M.dataModule.NOTIFICATION_TYPE then
        M.dataModule.RemoveByType(M.dataModule.NOTIFICATION_TYPE.PARTY_INVITE);
    end
end

-- Handle trade request packet (0x0021)
-- Structure: Trade request from another player
function M.HandleTradeRequest(e)
    if M.dataModule == nil then return end

    -- Parse packet data
    -- Offset 0x04: Trader server ID (4 bytes)
    local traderId = struct.unpack('I4', e.data, 0x04 + 1);

    -- Validate server ID
    if not valid_server_id(traderId) then
        return;
    end

    -- Get trader name from entity
    local traderName = getEntityName(traderId);

    -- Add notification via data module
    if M.dataModule.AddTradeRequestNotification then
        M.dataModule.AddTradeRequestNotification(traderName, traderId);
    end
end

-- Trade response kind values (GP_ITEM_TRADE_RES_KIND enum)
local TRADE_KIND = {
    START = 0,          -- Trade window opened
    CANCEL = 1,         -- Trade cancelled
    MAKE = 2,           -- Trade completed
    MAKE_CANCEL = 3,    -- Trade completion cancelled
    -- 4+ are various error types
};

-- Handle trade response packet (0x0022)
-- Structure: Trade action response (cancel, complete, error, etc.)
function M.HandleTradeResponse(e)
    if M.dataModule == nil then return end

    -- Parse packet data
    -- Offset 0x04: UniqueNo (server ID) - 4 bytes
    -- Offset 0x08: Kind (trade action type) - 4 bytes
    local serverId = struct.unpack('I4', e.data, 0x04 + 1);
    local kind = struct.unpack('I4', e.data, 0x08 + 1);

    -- Debug output
    if M.DEBUG_ENABLED then
        print(string.format('[XIUI] 0x0022 TRADE_RES: kind=%d serverId=%d', kind, serverId));
    end

    -- Any kind except START means the trade is ending/ended
    -- Remove trade notification
    if kind ~= TRADE_KIND.START then
        if M.dataModule.RemoveByType and M.dataModule.NOTIFICATION_TYPE then
            M.dataModule.RemoveByType(M.dataModule.NOTIFICATION_TYPE.TRADE_INVITE);
        end
    end
end

-- Handle message packet (0x0029/0x002D) for item/gil/key item obtained
-- This parses the already-parsed message packet structure
-- packetId: optional, the packet ID (0x0029 or 0x002D) for debug logging
function M.HandleMessagePacket(e, messagePacket, packetId)
    if M.dataModule == nil then return end
    if messagePacket == nil then return end

    local message = messagePacket.message;
    local param = messagePacket.param;
    local value = messagePacket.value;

    -- Debug output when enabled - log ALL messages to find item drop message IDs
    if M.DEBUG_ENABLED then
        local item = AshitaCore:GetResourceManager():GetItemById(param);
        local itemName = (item and item.Name and item.Name[1]) or 'nil';
        local handled = itemObtainedMes[message] and 'ITEM' or (gilObtainedMes[message] and 'GIL' or (keyItemObtainedMes[message] and 'KEY' or '-'));
        local pktStr = packetId and string.format('0x%04X', packetId) or '????';
        print(string.format('[XIUI] [%s] msg=%d p=%d v=%d item=%s [%s]',
            pktStr, message, param, value, itemName, handled));
    end

    -- Check for item obtained
    if itemObtainedMes[message] then
        -- Check if items notifications are enabled
        if not gConfig.notificationsShowItems then return end
        -- param contains item ID
        -- value contains quantity
        -- Validate item ID exists to prevent "Unknown Item" notifications from malformed packets
        local item = AshitaCore:GetResourceManager():GetItemById(param);
        if not item or not item.Name or not item.Name[1] or item.Name[1] == '' then
            if M.DEBUG_ENABLED then
                print(string.format('[XIUI] ITEM REJECTED: msg=%d param=%d (invalid item ID)', message, param));
            end
            return;
        end
        if M.dataModule.AddItemObtainedNotification then
            M.dataModule.AddItemObtainedNotification(param, value or 1);
        end
    -- Check for key item obtained
    elseif keyItemObtainedMes[message] then
        -- Check if key items notifications are enabled
        if not gConfig.notificationsShowKeyItems then return end
        -- param contains key item ID
        if M.dataModule.AddKeyItemObtainedNotification then
            M.dataModule.AddKeyItemObtainedNotification(param);
        end
    -- Check for gil obtained
    elseif gilObtainedMes[message] then
        -- Check if gil notifications are enabled
        if not gConfig.notificationsShowGil then return end
        -- param contains gil amount (not value)
        -- Sanity check: reject absurdly large values (likely server IDs being misinterpreted)
        -- Normal gil drops are typically under 100k, use 1M as safe threshold
        local gilAmount = param or 0;
        if gilAmount > 1000000 then
            if M.DEBUG_ENABLED then
                print(string.format('[XIUI] GIL REJECTED: msg=%d param=%d (too large, likely not gil)', message, gilAmount));
            end
            return;
        end
        if M.dataModule.AddGilObtainedNotification then
            M.dataModule.AddGilObtainedNotification(gilAmount);
        end
    end
end

-- ========================================
-- Action Packet Message IDs (0x0028)
-- ========================================

-- Steal message IDs (item obtained via Steal/Despoil)
-- These appear in action packet's action.Message field, with action.Param containing item ID
local stealItemMes = {
    [125] = true,   -- [Actor] steals an [item] from [target]. (Steal)
    [593] = true,   -- [Actor] steals [item] + Attack Down. (Despoil)
    [594] = true,   -- [Actor] steals [item] + Defense Down. (Despoil)
    [595] = true,   -- [Actor] steals [item] + Magic Atk. Down. (Despoil)
    [596] = true,   -- [Actor] steals [item] + Magic Def. Down. (Despoil)
    [597] = true,   -- [Actor] steals [item] + Evasion Down. (Despoil)
    [598] = true,   -- [Actor] steals [item] + Accuracy Down. (Despoil)
    [599] = true,   -- [Actor] steals [item] + Slow. (Despoil)
};

-- Mug message ID (gil obtained via Mug)
-- action.Param contains gil amount
local mugGilMes = {
    [129] = true,   -- [Actor] mugs [gil] from [target]. (Mug)
};

-- ========================================
-- Action Packet Handler (0x0028)
-- ========================================

-- Handle action packet (0x0028) for Steal/Mug notifications
-- Steal and Mug results come through action packets, not message packets
function M.HandleActionPacket(actionPacket)
    if M.dataModule == nil then return end
    if actionPacket == nil then return end

    -- Get player server ID to check if we're the actor
    local party = GetPartySafe();
    if not party then return end
    local playerServerId = party:GetMemberServerId(0);

    -- Only process our own actions
    if actionPacket.UserId ~= playerServerId then return end

    -- Check each target's actions for steal/mug messages
    if actionPacket.Targets then
        for _, target in ipairs(actionPacket.Targets) do
            if target.Actions then
                for _, action in ipairs(target.Actions) do
                    local message = action.Message;
                    local param = action.Param;

                    -- Debug output
                    if M.DEBUG_ENABLED then
                        print(string.format('[XIUI] ACTION: msg=%d param=%d', message or 0, param or 0));
                    end

                    -- Check for Steal (item obtained)
                    if stealItemMes[message] and param and param > 0 then
                        if gConfig.notificationsShowItems and M.dataModule.AddItemObtainedNotification then
                            M.dataModule.AddItemObtainedNotification(param, 1);
                            if M.DEBUG_ENABLED then
                                local item = AshitaCore:GetResourceManager():GetItemById(param);
                                local itemName = (item and item.Name and item.Name[1]) or 'Unknown';
                                print(string.format('[XIUI] STEAL: item=%d (%s)', param, itemName));
                            end
                        end
                    -- Check for Mug (gil obtained)
                    elseif mugGilMes[message] and param and param > 0 then
                        if gConfig.notificationsShowGil and M.dataModule.AddGilObtainedNotification then
                            M.dataModule.AddGilObtainedNotification(param);
                            if M.DEBUG_ENABLED then
                                print(string.format('[XIUI] MUG: gil=%d', param));
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ========================================
-- Inventory Update Packet (0x020)
-- ========================================

-- Handle inventory item update packet (0x020)
-- NOTE: This packet fires for ALL inventory changes including zone sync.
-- We do NOT use this for notifications - item notifications come from
-- the message packet (0x0029) which shows actual "You obtained X" messages.
-- This handler is kept for potential future use but does nothing currently.
function M.HandleInventoryUpdate(e)
    -- Intentionally empty - do not create notifications from inventory sync packets
    -- Item obtained notifications are handled by HandleMessagePacket (0x0029)
end

-- ========================================
-- Treasure Pool Packet (0x00D2) - Found Item
-- ========================================

-- Handle treasure pool update packet (0x00D2)
-- Packet structure (per Atom0s XiPackets):
-- 0x04-0x07: TrophyItemNum (item count) - 4 bytes
-- 0x08-0x0B: TargetUniqueNo (dropper server ID) - 4 bytes
-- 0x0C-0x0D: Gold - 2 bytes
-- 0x10-0x11: TrophyItemNo (item ID) - 2 bytes
-- 0x14: TrophyItemIndex (pool slot 0-9) - 1 byte
-- 0x15: Entry (lot status: 0=pending, 1=passed, 2=lotted) - 1 byte
function M.HandleTreasurePool(e)
    if M.dataModule == nil then return end

    -- Skip during zoning grace period to avoid false notifications
    if isInZoningGracePeriod() then return end

    -- Parse packet structure
    local count = struct.unpack('I4', e.data, 0x04 + 1);       -- TrophyItemNum
    local gil = struct.unpack('H', e.data, 0x0C + 1);          -- Gold
    local itemId = struct.unpack('H', e.data, 0x10 + 1);       -- TrophyItemNo
    local slot = struct.unpack('B', e.data, 0x14 + 1);         -- TrophyItemIndex

    -- Debug output
    if M.DEBUG_ENABLED then
        local item = AshitaCore:GetResourceManager():GetItemById(itemId);
        local itemName = (item and item.Name and item.Name[1]) or 'Unknown';
        print(string.format('[XIUI] 0x0D2: slot=%d item=%s gil=%d', slot or 255, itemName, gil or 0));
    end

    -- Handle gil notification FIRST (before any slot validation)
    if gil and gil > 0 and gConfig.notificationsShowGil and M.dataModule.AddGilObtainedNotification then
        M.dataModule.AddGilObtainedNotification(gil);
    end

    -- Validate slot is within bounds (0-9)
    if slot == nil or slot >= 10 then return end

    -- Skip invalid item IDs
    if itemId == nil or itemId == 0 or itemId == 65535 then return end

    -- Track item with timestamp - DON'T create notification yet
    -- Wait briefly to see if 0x00D3 (item awarded) arrives
    -- If it does, only "Item Obtained" notification is created
    -- If not (item stays in pool), CheckPendingPoolNotifications creates "Treasure Pool"
    pendingPoolNotifications[slot] = {
        itemId = itemId,
        count = count or 1,
        timestamp = os.clock(),
        notified = false,
    };

    if M.DEBUG_ENABLED then
        print(string.format('[XIUI] 0x0D2: Tracking item, waiting for 0x00D3'));
    end
end

-- ========================================
-- Treasure Lot/Drop Packet (0x00D3)
-- ========================================

-- Handle treasure lot/drop packet (0x00D3)
-- Packet structure:
-- 0x04-0x07: Highest Lotter ID - 4 bytes
-- 0x08-0x0B: Current Lotter ID - 4 bytes
-- 0x0C-0x0D: Highest Lotter Index - 2 bytes
-- 0x0E-0x0F: Highest Lot value - 2 bytes
-- 0x10-0x11: Current Lotter Index - 2 bytes
-- 0x12-0x13: Current Lot value - 2 bytes
-- 0x14: Pool slot index - 1 byte
-- 0x15: Drop status (0=pending, 1=awarded, 2=lost) - 1 byte
-- 0x16-0x25: Highest Lotter Name - 16 bytes
-- 0x26-0x35: Current Lotter Name - 16 bytes
function M.HandleTreasureLot(e)
    if M.dataModule == nil then return end

    -- No grace period - lot packets contain valuable name/lot data that memory doesn't have

    -- Parse packet structure
    local highestLotterId = struct.unpack('I4', e.data, 0x04 + 1);
    local currentLotterId = struct.unpack('I4', e.data, 0x08 + 1);
    local highestLot = struct.unpack('H', e.data, 0x0E + 1);
    local currentLot = struct.unpack('H', e.data, 0x12 + 1);
    local slot = struct.unpack('B', e.data, 0x14 + 1);
    local dropStatus = struct.unpack('B', e.data, 0x15 + 1);

    -- Validate slot is within bounds (0-9)
    if slot == nil or slot >= 10 then
        return;
    end

    local highestLotterNameRaw = struct.unpack('c16', e.data, 0x16 + 1);
    local currentLotterNameRaw = struct.unpack('c16', e.data, 0x26 + 1);
    local highestLotterName = trimNullString(highestLotterNameRaw);
    local currentLotterName = trimNullString(currentLotterNameRaw);

    -- Debug output
    if M.DEBUG_ENABLED then
        print(string.format('[XIUI] 0x0D3 LOT: slot=%d status=%d curr=%s(%d) high=%s(%d)',
            slot, dropStatus, currentLotterName or '-', currentLot or 0,
            highestLotterName or '-', highestLot or 0));
    end

    -- When item is won (status=1), create "Item Obtained" notification for the winner
    if dropStatus == 1 then
        -- Get current player's server ID to check if WE won
        local party = GetPartySafe();
        if party then
            local playerServerId = party:GetMemberServerId(0);
            if highestLotterId == playerServerId then
                -- We won! Get item ID from pendingPoolNotifications first, then treasurePool
                local itemId = nil;
                local count = 1;

                if pendingPoolNotifications[slot] then
                    itemId = pendingPoolNotifications[slot].itemId;
                    count = pendingPoolNotifications[slot].count or 1;
                elseif M.dataModule.treasurePool and M.dataModule.treasurePool[slot] then
                    local poolItem = M.dataModule.treasurePool[slot];
                    itemId = poolItem.itemId;
                    count = poolItem.count or 1;
                end

                if itemId and itemId > 0 then
                    -- Clear pending entry FIRST to prevent "Treasure Pool" notification
                    pendingPoolNotifications[slot] = nil;

                    if gConfig.notificationsShowItems and M.dataModule.AddItemObtainedNotification then
                        M.dataModule.AddItemObtainedNotification(itemId, count);

                        if M.DEBUG_ENABLED then
                            local item = AshitaCore:GetResourceManager():GetItemById(itemId);
                            local itemName = (item and item.Name and item.Name[1]) or 'Unknown';
                            print(string.format('[XIUI] 0x0D3: Created item obtained notification for %d(%s) x%d (we won!)',
                                itemId, itemName, count));
                        end
                    end
                elseif M.DEBUG_ENABLED then
                    print(string.format('[XIUI] 0x0D3: Item won but slot %d not found in pendingPoolNotifications or treasurePool', slot));
                end
            elseif M.DEBUG_ENABLED then
                print(string.format('[XIUI] 0x0D3: Item won by %s (id=%d), not us (id=%d)',
                    highestLotterName or 'Unknown', highestLotterId, playerServerId));
            end
        end
    end

    -- Check if treasure notifications are enabled
    if not gConfig.notificationsShowTreasure then return end

    -- Update treasure pool item with lot info
    if M.dataModule.UpdateTreasurePoolLot then
        M.dataModule.UpdateTreasurePoolLot(
            slot,
            currentLotterId,
            currentLotterName,
            currentLot,
            highestLotterId,
            highestLotterName,
            highestLot,
            dropStatus
        );
    end
end

-- Clear treasure state (call on zone change)
function M.ClearTreasureState()
    if M.dataModule and M.dataModule.ClearTreasurePool then
        M.dataModule.ClearTreasurePool();
    end
    -- Also clear toast tracking so items re-appearing in pool get toasts
    M.ClearToastTracking();
    -- Disable test mode (return to normal memory sync)
    M.testModeEnabled = false;
end

return M;
